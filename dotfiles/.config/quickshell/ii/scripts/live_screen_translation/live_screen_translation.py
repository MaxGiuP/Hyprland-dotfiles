#!/usr/bin/env python3
from __future__ import annotations

import argparse
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
from pathlib import Path

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
            ["trans", "-brief", "-no-ansi", "-no-browser", f":{target_language}", "--", f" {text}"],
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


class AsyncTranslator:
    """Translates in a background thread so it never blocks the OCR loop."""

    def __init__(self, language: str) -> None:
        self._language = language
        self._lock = threading.Lock()
        self._result = ""
        self._error = ""
        self._latest_text = ""
        self._generation = 0
        self._retry_after = 0.0
        self._pending: tuple[int, str] | None = None
        self._thread: threading.Thread | None = None
        self._closed = threading.Event()

    def submit(self, text: str) -> None:
        """Queue text for translation. Returns immediately."""
        if not text:
            self.reset()
            return
        with self._lock:
            if self._closed.is_set():
                return
            if text != self._latest_text:
                self._generation += 1
                self._latest_text = text
                self._result = ""
                self._error = ""
            elif (self._result or self._pending or self._thread is not None
                  or time.monotonic() < self._retry_after):
                return
            self._pending = (self._generation, text)
            if self._thread is None:
                self._thread = threading.Thread(target=self._run, daemon=True)
                self._thread.start()

    def reset(self) -> None:
        with self._lock:
            self._generation += 1
            self._latest_text = ""
            self._result = ""
            self._error = ""
            self._pending = None

    def close(self) -> None:
        self._closed.set()
        self.reset()
        with self._lock:
            thread = self._thread
        if thread:
            thread.join()

    def result(self) -> str:
        with self._lock:
            return self._result

    def snapshot(self) -> tuple[str, str]:
        with self._lock:
            return self._result, self._error

    def _run(self) -> None:
        while True:
            with self._lock:
                if self._closed.is_set() or self._pending is None:
                    self._thread = None
                    return
                generation, text = self._pending
                self._pending = None
            try:
                translated = translate_text(text, self._language, self._closed)
                error = ""
            except ProcessCancelled:
                translated, error = "", ""
            except Exception as exception:
                translated, error = "", str(exception)
            with self._lock:
                if generation == self._generation and not self._closed.is_set():
                    self._result = translated
                    self._error = error
                    self._retry_after = time.monotonic() + 2.0


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

    lines_dict: dict[tuple, list[tuple[int, str]]] = {}
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
            key = tuple(int(row[name]) for name in ("page_num", "block_num", "par_num", "line_num"))
            word_num = int(row["word_num"])
        except (KeyError, ValueError, TypeError):
            continue
        lines_dict.setdefault(key, []).append((word_num, text))
        confidences.append(conf)

    if not lines_dict:
        return "", 0.0

    text_lines = []
    for key in sorted(lines_dict):
        words = [w for _, w in sorted(lines_dict[key])]
        text_lines.append(" ".join(words))

    mean_conf = sum(confidences) / len(confidences)
    return normalize_lines("\n".join(text_lines)), mean_conf


def main() -> int:
    args = parse_args()
    state_path = Path(args.state_file)
    state: dict = {
        "status": "starting",
        "message": "Starting live screen translation…",
        "ocr_text": "",
        "translated_text": "",
        "target_language": args.target_language,
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
    translator = AsyncTranslator(args.target_language)
    exit_code = 0

    try:
        with tempfile.TemporaryDirectory(prefix="live-screen-translation-") as temp_dir:
            image_path = Path(temp_dir) / "capture.png"

            state.update({"status": "running", "message": "Reading selected screen area…"})
            write_state(state_path, state)

            while not STOP_REQUESTED.is_set():
                try:
                    capture_region(args.region, image_path)
                    image_bytes = preprocess_image(image_path)
                    ocr_text, confidence = ocr_image(image_bytes, args.ocr_language)
                except ProcessCancelled:
                    break
                except (FileNotFoundError, ValueError) as error:
                    state.update({"status": "error", "message": str(error)})
                    write_state(state_path, state)
                    exit_code = 2
                    break
                except Exception as error:
                    state.update({
                        "status": "error",
                        "message": str(error),
                        "ocr_text": last_ocr_text,
                        "translated_text": translator.result(),
                    })
                    write_state(state_path, state)
                    STOP_REQUESTED.wait(max(0.5, args.interval_seconds))
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
                translated, translation_error = translator.snapshot()
                state.update({
                    "status": "error" if translation_error else "running",
                    "message": translation_error or "Reading selected screen area…",
                    "ocr_text": last_ocr_text,
                    "translated_text": translated,
                    "target_language": args.target_language,
                    "ocr_language": args.ocr_language,
                    "region": args.region,
                })
                write_state(state_path, state)
                STOP_REQUESTED.wait(max(0.35, args.interval_seconds))
    finally:
        translator.close()

    if exit_code == 0:
        state.update({"status": "stopped", "message": "Live screen translation stopped.",
                      "ocr_text": "", "translated_text": ""})
        write_state(state_path, state)
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
