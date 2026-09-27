#!/usr/bin/env python3
from __future__ import annotations

import argparse
from collections import OrderedDict
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
import csv
import io
import json
import math
import os
import re
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unicodedata
from pathlib import Path

# Shared source pairing is resolved relative to the installed scripts, not cwd.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "live_captions"))
from translation_segments import SegmentTracker

STOP_REQUESTED = threading.Event()


def handle_signal(signum, frame):
    STOP_REQUESTED.set()


for _sig in (signal.SIGINT, signal.SIGTERM):
    signal.signal(_sig, handle_signal)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--state-file", required=True)
    parser.add_argument("--region", required=True)
    parser.add_argument("--target-language", default="en")
    parser.add_argument("--ocr-language", default="eng")
    parser.add_argument("--translation-granularity", choices=["phrase", "sentence"], default="sentence")
    parser.add_argument("--translation-style", choices=["natural", "literal"], default="natural")
    parser.add_argument("--interval-seconds", type=float, default=0.6)
    parser.add_argument("--confidence-threshold", type=float, default=60.0,
                        help="Minimum mean word confidence (0-100) to accept an OCR result")
    return parser.parse_args()


def normalize_geometry(region: str) -> str:
    cleaned = " ".join(region.strip().split())
    number = r"(?:\d+(?:\.\d+)?|\.\d+)"
    m = re.fullmatch(rf"([+-]?{number}),([+-]?{number})\s+({number})x({number})", cleaned)
    if not m:
        raise ValueError(
            f"Cannot parse region '{cleaned}' — expected 'X,Y WxH' from slurp. "
            "Try drawing the selection again."
        )
    x, y, w, h = (float(value) for value in m.groups())
    if not all(math.isfinite(value) for value in (x, y, w, h)) or w <= 0 or h <= 0:
        raise ValueError("Capture region must have finite coordinates and positive dimensions.")
    x, y = int(round(x)), int(round(y))
    w, h = max(1, int(round(w))), max(1, int(round(h)))
    return f"{x},{y} {w}x{h}"


def normalize_lines(text: str) -> str:
    lines = [" ".join(line.split()) for line in (text or "").splitlines()]
    return "\n".join(line for line in lines if line).strip()


def write_state(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                     prefix=f".{path.name}.", delete=False) as handle:
        temp_path = Path(handle.name)
        try:
            json.dump(payload, handle, ensure_ascii=False)
            handle.close()
            temp_path.replace(path)
        finally:
            temp_path.unlink(missing_ok=True)


class ProcessCancelled(Exception):
    """The backend or translator was stopped while a subprocess was running."""


def run_command(command: list[str], *, timeout: float, input=None, text: bool = False,
                stop_event: threading.Event | None = None) -> subprocess.CompletedProcess:
    """Bound subprocess lifetime, including children spawned by translate-shell."""
    if STOP_REQUESTED.is_set() or (stop_event and stop_event.is_set()):
        raise ProcessCancelled()
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=text, start_new_session=True)
    deadline = time.monotonic() + timeout
    try:
        while True:
            if STOP_REQUESTED.is_set() or (stop_event and stop_event.is_set()):
                raise ProcessCancelled()
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise subprocess.TimeoutExpired(command, timeout)
            try:
                stdout, stderr = process.communicate(input=input, timeout=min(0.1, remaining))
                return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)
            except subprocess.TimeoutExpired:
                # communicate() keeps unsent input internally after the first call.
                input = None
    finally:
        # A shell can exit while its children still own our pipes. Kill the whole
        # isolated group on cancellation/timeout, then reap the direct child.
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.communicate()


def translate_text(text: str, target_language: str,
                   stop_event: threading.Event | None = None) -> str:
    if not text:
        return ""
    try:
        result = run_command(
            # '--' prevents OCR from becoming flags. Leading whitespace prevents
            # translate-shell from treating file:// or URLs as files/web pages.
            ["trans", "-brief", "-no-init", "-no-ansi", "-no-bidi", "-no-browser", "-no-play",
             f":{target_language}", "--", f" {text}"],
            text=True,
            timeout=15,
            stop_event=stop_event,
        )
    except FileNotFoundError as error:
        raise RuntimeError("Translation tool 'trans' is not installed.") from error
    except subprocess.TimeoutExpired as error:
        raise RuntimeError("Translation timed out; retrying…") from error
    translated = normalize_lines(result.stdout)
    if result.returncode != 0 or not translated:
        raise RuntimeError("Translation unavailable; check your connection. Retrying…")
    return translated


def translate_literal(text: str, target_language: str, source_language: str = "",
                      stop_event: threading.Event | None = None, *, on_progress=None, cache=None) -> str:
    # Keep normal translation independent of the optional local model helper.
    # Missing literal support is an explicit error, never a natural fallback.
    try:
        from literal_translation import translate_literal as translate
    except ImportError as error:
        raise RuntimeError("Literal translation backend is not installed.") from error
    return translate(text, target_language, source_language=source_language, stop_event=stop_event,
                     on_progress=on_progress, cache=cache)


def create_literal_cache():
    try:
        from literal_translation import LiteralCache
    except ImportError as error:
        raise RuntimeError("Literal translation backend does not support streaming yet.") from error
    return LiteralCache()


def can_reuse_literal_source(previous: str, current: str) -> bool:
    from literal_translation import LiteralCache
    return LiteralCache.can_reuse_source(previous, current)


class AsyncTranslator:
    """Translate source groups without blocking capture or guessing correspondence."""

    CACHE_LIMIT = 128
    MAX_CONCURRENT = 2

    def __init__(self, language: str, granularity: str = "sentence",
                 translation_style: str = "natural") -> None:
        if translation_style not in {"natural", "literal"}:
            raise ValueError("Translation style must be 'natural' or 'literal'.")
        self._language = language
        # Style is fixed for this worker's lifetime, isolating its source cache.
        self._translation_style = translation_style
        self._max_concurrent = 1 if translation_style == "literal" else self.MAX_CONCURRENT
        self._lock = threading.Lock()
        self._error = ""
        self._latest_text = ""
        self._generation = 0
        self._reset_epoch = 0
        self._retry_after = 0.0
        self._tracker = SegmentTracker(granularity=granularity)
        self._segments: list[dict] = []
        self._cache: OrderedDict[str, str] = OrderedDict()
        self._progress: OrderedDict[str, dict] = OrderedDict()
        self._literal_cache = None
        self._literal_active: dict[str, threading.Event] = {}
        self._pending: tuple[int, list[dict]] | None = None
        self._thread: threading.Thread | None = None
        self._closed = threading.Event()

    def submit(self, text: str) -> None:
        """Queue only changed/missing groups with bounded concurrent requests."""
        if not text:
            self.reset()
            return
        with self._lock:
            if self._closed.is_set():
                return
            if text != self._latest_text:
                self._generation += 1
                self._latest_text = text
                self._segments = self._tracker.update(text)
                self._error = ""
                for requested_source, cancel in self._literal_active.items():
                    if not any(can_reuse_literal_source(requested_source, item["source"])
                               for item in self._segments):
                        cancel.set()
            elif (all(item["source"] in self._cache for item in self._segments)
                  or self._pending or self._thread is not None
                  or time.monotonic() < self._retry_after):
                return
            self._pending = (self._generation, [dict(item) for item in self._segments])
            if self._thread is None:
                self._thread = threading.Thread(target=self._run, daemon=True)
                self._thread.start()
        self._refresh_literal_progress()

    def reset(self) -> None:
        with self._lock:
            self._generation += 1
            self._reset_epoch += 1
            self._latest_text = ""
            self._error = ""
            self._pending = None
            self._segments = []
            self._progress.clear()
            self._tracker.reset()
            for cancel in self._literal_active.values():
                cancel.set()

    def close(self) -> None:
        self._closed.set()
        self.reset()
        with self._lock:
            thread = self._thread
        if thread:
            thread.join()

    def _snapshot_locked(self) -> tuple[str, str, list[dict]]:
        segments = []
        for item in self._segments:
            translated_source, translated, complete = self._completed_prefix_locked(item["source"])
            segments.append({**item, "translated": translated, "translated_source": translated_source,
                             "pending": not complete})
        translated_parts = []
        pending_break = False
        for item in segments:
            pending_break = pending_break or item.get("separator", "\n") == "\n"
            if item["translated"]:
                if translated_parts:
                    translated_parts.append("\n" if pending_break else " ")
                translated_parts.append(item["translated"])
                pending_break = False
        translated_text = "".join(translated_parts)
        return (translated_text,
                self._error, segments)

    def result(self) -> str:
        return self.snapshot()[0]

    def snapshot(self) -> tuple[str, str]:
        with self._lock:
            translated, error, _ = self._snapshot_locked()
            return translated, error

    def snapshot_segments(self) -> tuple[str, str, list[dict]]:
        with self._lock:
            return self._snapshot_locked()

    @staticmethod
    def _source_prefix(prefix: str, source: str) -> bool:
        if not prefix or not source.startswith(prefix):
            return False
        if len(prefix) == len(source):
            return True
        following = source[len(prefix)]
        return following.isspace() or (unicodedata.category(following).startswith("P")
                                      and following not in "'’_-\u2010\u2011")

    def _completed_prefix_locked(self, source: str) -> tuple[str, str, bool]:
        if source in self._cache:
            return source, self._cache[source], True
        best_source, best_text, complete = "", "", False
        if self._translation_style == "natural":
            for previous, translated in self._cache.items():
                if len(previous) > len(best_source) and self._source_prefix(previous, source):
                    best_source, best_text = previous, translated
        for requested_source, progress in self._progress.items():
            prefix = progress["source"]
            if (requested_source == source
                    and len(prefix) >= len(best_source) and self._source_prefix(prefix, source)):
                best_source, best_text = prefix, progress["translated"]
                complete = prefix == source and progress["complete"]
        return best_source, best_text, complete

    def _publish_progress(self, current_source: str, epoch: int, snapshot,
                          stop_event: threading.Event | None = None) -> None:
        if not isinstance(snapshot, dict):
            return
        prefix, translated = snapshot.get("source"), snapshot.get("translated")
        if (not isinstance(prefix, str) or not isinstance(translated, str)
                or not translated.strip() or not self._source_prefix(prefix, current_source)):
            return
        with self._lock:
            if (self._closed.is_set() or epoch != self._reset_epoch
                    or (stop_event is not None and stop_event.is_set())):
                return
            if not any(current_source == item["source"] for item in self._segments):
                return
            previous = self._progress.get(current_source)
            if previous and len(prefix) < len(previous["source"]):
                return
            self._progress[current_source] = {
                "source": prefix, "translated": translated.strip(),
                "complete": snapshot.get("complete") is True,
            }
            self._progress.move_to_end(current_source)
            while len(self._progress) > self.CACHE_LIMIT:
                self._progress.popitem(last=False)

    def _refresh_literal_progress(self) -> None:
        with self._lock:
            cache, epoch = self._literal_cache, self._reset_epoch
            sources = [item["source"] for item in self._segments]
        if cache is not None:
            for source in sources:
                self._publish_progress(source, epoch, cache.snapshot(source, self._language, ""))

    def _accept_progress(self, requested_source: str, epoch: int, snapshot,
                         stop_event: threading.Event) -> None:
        if (not isinstance(snapshot, dict) or not isinstance(snapshot.get("source"), str)
                or not self._source_prefix(snapshot["source"], requested_source)):
            return
        with self._lock:
            if epoch != self._reset_epoch or stop_event.is_set() or self._closed.is_set():
                return
            sources = [item["source"] for item in self._segments
                       if can_reuse_literal_source(requested_source, item["source"])]
            cache = self._literal_cache
        for current_source in sources:
            # Growth and tail revisions need context-sensitive projection.
            # Raw old glosses would bypass the helper's revisable word buffer.
            projected = (snapshot if current_source == requested_source
                         else cache.snapshot(current_source, self._language, "") if cache else None)
            self._publish_progress(current_source, epoch, projected, stop_event)

    def _translate(self, text: str, epoch: int,
                   stop_event: threading.Event | None = None) -> str:
        if self._translation_style == "natural":
            return translate_text(text, self._language, self._closed)
        try:
            # Tesseract's English recognition model does not prove the source
            # is English; let the local literal translator identify it.
            if self._literal_cache is None:
                self._literal_cache = create_literal_cache()
            on_progress = lambda snapshot: self._accept_progress(text, epoch, snapshot, stop_event)
            cached = self._literal_cache.snapshot(text, self._language, "")
            if cached:
                on_progress(cached)
            translated = translate_literal(text, self._language, source_language="", stop_event=stop_event,
                                           on_progress=on_progress, cache=self._literal_cache)
            if not isinstance(translated, str) or not translated.strip():
                raise RuntimeError("The local model returned no text.")
            return translated.strip()
        except Exception as error:
            message = str(error)
            if message.lower().startswith("literal translation"):
                raise
            raise RuntimeError(f"Literal translation unavailable: {message}") from error

    def _run(self) -> None:
        active = {}
        queued = []
        generation = -1
        with ThreadPoolExecutor(max_workers=self._max_concurrent,
                                thread_name_prefix="screen-phrase") as pool:
            while True:
                with self._lock:
                    if self._pending is not None:
                        generation, segments = self._pending
                        self._pending = None
                        # Replacing the queue drops obsolete text before a
                        # network call. Start the latest visible groups first.
                        queued = list(reversed(segments))
                    if self._closed.is_set() or generation != self._generation:
                        queued = []
                    queued = [item for item in queued if item["source"] not in self._cache]
                    active_sources = {text for _, text, _ in active.values()}
                    while queued and len(active) < self._max_concurrent:
                        candidate = next((index for index, item in enumerate(queued)
                                          if item["source"] not in active_sources), None)
                        if candidate is None:
                            break
                        text = queued.pop(candidate)["source"]
                        cancel = threading.Event() if self._translation_style == "literal" else None
                        if cancel is not None:
                            self._literal_active[text] = cancel
                        future = pool.submit(self._translate, text, self._reset_epoch, cancel)
                        active[future] = (generation, text, cancel)
                        active_sources.add(text)
                    if not active:
                        self._thread = None
                        return

                completed, _ = wait(active, timeout=0.1, return_when=FIRST_COMPLETED)
                for future in completed:
                    task_generation, text, cancel = active.pop(future)
                    try:
                        translated, error = future.result(), ""
                    except ProcessCancelled:
                        translated, error = "", ""
                    except Exception as exception:
                        translated, error = "", str(exception)
                    with self._lock:
                        if cancel is not None:
                            self._literal_active.pop(text, None)
                        if self._closed.is_set() or (cancel is not None and cancel.is_set()):
                            continue
                        if translated:
                            # Exact keys allow caching a late result without
                            # ever pairing it with a changed source group.
                            self._cache[text] = translated
                            self._cache.move_to_end(text)
                            while len(self._cache) > self.CACHE_LIMIT:
                                self._cache.popitem(last=False)
                        else:
                            # A new generation may still contain this phrase;
                            # do not immediately repeat its failed request.
                            queued = [item for item in queued if item["source"] != text]
                        if task_generation == self._generation and error:
                            self._error = error
                        self._retry_after = time.monotonic() + 2.0
                        if all(item["source"] in self._cache for item in self._segments):
                            self._error = ""


def capture_region(region: str, image_path: Path) -> None:
    normalized = normalize_geometry(region)
    result = run_command(
        ["grim", "-g", normalized, str(image_path)],
        text=True,
        timeout=8,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip()
        msg = (f"grim '{normalized}': {detail}" if detail
               else f"grim: screenshot failed for region '{normalized}'")
        raise RuntimeError(msg)


def preprocess_image(image_path: Path) -> bytes:
    """
    Preprocess screenshot for better OCR accuracy.
    Returns PNG bytes to pass directly to tesseract stdin.
    Falls back to raw file bytes if PIL is unavailable.
    """
    try:
        from PIL import Image, ImageFilter, ImageOps
        with Image.open(image_path) as original:
            img = original.convert("L")
        img = img.resize((img.width * 3, img.height * 3), Image.BILINEAR)
        img = img.filter(ImageFilter.SMOOTH)          # reduce compression noise
        img = ImageOps.autocontrast(img, cutoff=2)   # normalise brightness range
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        return buf.getvalue()
    except Exception:
        return image_path.read_bytes()


def ocr_image(image_bytes: bytes, language: str) -> tuple[str, float]:
    """
    Run OCR on preprocessed image bytes via tesseract stdin.
    Returns (text, mean_confidence) where confidence is 0–100.
    """
    result = run_command(
        ["tesseract", "stdin", "stdout", "-l", language,
         "--psm", "6", "--oem", "3", "tsv"],
        input=image_bytes,
        timeout=12,
    )
    if result.returncode != 0:
        detail = (result.stderr or b"").decode(errors="replace").strip()
        raise RuntimeError(f"tesseract failed: {detail}" if detail else "tesseract: OCR failed")

    paragraphs: dict[tuple, list[tuple[int, int, str]]] = {}
    confidences: list[float] = []
    stdout_text = result.stdout.decode(errors="replace")
    reader = csv.DictReader(io.StringIO(stdout_text), delimiter="\t", quoting=csv.QUOTE_NONE)
    for row in reader:
        try:
            conf = float(row.get("conf", -1))
        except (ValueError, TypeError):
            continue
        text = (row.get("text") or "").strip()
        if not math.isfinite(conf) or not 0 <= conf <= 100 or not text:
            continue
        try:
            key = tuple(int(row[name]) for name in ("page_num", "block_num", "par_num"))
            line_num = int(row["line_num"])
            word_num = int(row["word_num"])
        except (KeyError, ValueError, TypeError):
            continue
        paragraphs.setdefault(key, []).append((line_num, word_num, text))
        confidences.append(conf)

    if not paragraphs:
        return "", 0.0

    text_paragraphs = []
    for key in sorted(paragraphs):
        # A wrapped display line is not a new utterance. Keep sentence context
        # within each OCR paragraph, while retaining actual paragraph breaks.
        words = [word for _, _, word in sorted(paragraphs[key])]
        text_paragraphs.append(" ".join(words))

    mean_conf = sum(confidences) / len(confidences)
    return normalize_lines("\n".join(text_paragraphs)), mean_conf


class OcrFrameCache:
    """Reuse OCR only for the exact last successfully processed capture."""

    def __init__(self) -> None:
        self._image: bytes | None = None
        self._language = ""
        self._result: tuple[str, float] = ("", 0.0)

    def read(self, image_path: Path, language: str) -> tuple[str, float]:
        image = image_path.read_bytes()
        if image == self._image and language == self._language:
            return self._result
        result = ocr_image(preprocess_image(image_path), language)
        # Failed processing must retry, even if the next image is unchanged.
        self._image, self._language, self._result = image, language, result
        return result


def capture_wait_seconds(started_at: float, interval: float, *, failed: bool = False) -> float:
    """Target capture start-to-start cadence instead of adding processing time."""
    period = max(0.5 if failed else 0.35, interval)
    return max(0.1 if failed else 0.0, period - (time.monotonic() - started_at))


def main() -> int:
    args = parse_args()
    state_path = Path(args.state_file)
    state: dict = {
        "status": "starting",
        "message": "Starting live screen translation…",
        "ocr_text": "",
        "translated_text": "",
        "translation_segments": [],
        "target_language": args.target_language,
        "translation_style": args.translation_style,
        "ocr_language": args.ocr_language,
        "region": args.region,
    }
    write_state(state_path, state)

    try:
        args.region = normalize_geometry(args.region)
        state["region"] = args.region
        if not math.isfinite(args.interval_seconds) or args.interval_seconds <= 0:
            raise ValueError("Capture interval must be a positive finite number.")
        if not math.isfinite(args.confidence_threshold) or not 0 <= args.confidence_threshold <= 100:
            raise ValueError("OCR confidence threshold must be between 0 and 100.")
    except ValueError as error:
        state.update({"status": "error", "message": str(error)})
        write_state(state_path, state)
        return 2

    last_ocr_text = ""
    empty_frames = 0
    translator = AsyncTranslator(args.target_language, args.translation_granularity, args.translation_style)
    frame_cache = OcrFrameCache()
    exit_code = 0

    try:
        with tempfile.TemporaryDirectory(prefix="live-screen-translation-") as temp_dir:
            image_path = Path(temp_dir) / "capture.png"

            state.update({"status": "running", "message": "Reading selected screen area…"})
            write_state(state_path, state)

            while not STOP_REQUESTED.is_set():
                frame_started_at = time.monotonic()
                try:
                    capture_region(args.region, image_path)
                    ocr_text, confidence = frame_cache.read(image_path, args.ocr_language)
                except ProcessCancelled:
                    break
                except (FileNotFoundError, ValueError) as error:
                    state.update({"status": "error", "message": str(error),
                                  "translation_segments": []})
                    write_state(state_path, state)
                    exit_code = 2
                    break
                except Exception as error:
                    translated, _, translation_segments = translator.snapshot_segments()
                    state.update({
                        "status": "error",
                        "message": str(error),
                        "ocr_text": last_ocr_text,
                        "translated_text": translated,
                        "translation_segments": translation_segments,
                    })
                    write_state(state_path, state)
                    STOP_REQUESTED.wait(capture_wait_seconds(frame_started_at, args.interval_seconds, failed=True))
                    continue

                if not ocr_text:
                    # A single bad frame should not flicker, but a blank selection
                    # must eventually clear its old translation (confidence is 0).
                    empty_frames += 1
                    if empty_frames >= 2:
                        last_ocr_text = ""
                        translator.reset()
                else:
                    empty_frames = 0
                    if confidence >= args.confidence_threshold:
                        last_ocr_text = ocr_text

                # Re-submit unchanged text too: failures are retried with a short
                # backoff, and completed/active requests are deduplicated.
                if last_ocr_text:
                    translator.submit(last_ocr_text)
                translated, translation_error, translation_segments = translator.snapshot_segments()
                state.update({
                    "status": "error" if translation_error else "running",
                    "message": translation_error or "Reading selected screen area…",
                    "ocr_text": last_ocr_text,
                    "translated_text": translated,
                    "translation_segments": translation_segments,
                    "target_language": args.target_language,
                    "translation_style": args.translation_style,
                    "ocr_language": args.ocr_language,
                    "region": args.region,
                })
                write_state(state_path, state)
                STOP_REQUESTED.wait(capture_wait_seconds(frame_started_at, args.interval_seconds))
    finally:
        translator.close()

    if exit_code == 0:
        state.update({"status": "stopped", "message": "Live screen translation stopped.",
                      "ocr_text": "", "translated_text": "", "translation_segments": []})
        write_state(state_path, state)
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
