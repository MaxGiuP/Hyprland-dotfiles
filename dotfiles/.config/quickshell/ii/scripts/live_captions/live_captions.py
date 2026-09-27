#!/usr/bin/env python3
from __future__ import annotations

import argparse
from collections import OrderedDict, deque
import json
import os
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unicodedata
from pathlib import Path

import numpy as np

# Resolve this also when loaded by importlib or launched from another directory.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from translation_segments import SegmentTracker

RUNNING = True
SAMPLE_RATE = 16000
MAX_BUFFER_SECS = 8.0
MAX_COMMITTED_WORDS = 128
REVISABLE_COMMITTED_WORDS = 5
TAIL_GUESS_CONFIRMATIONS = 3
SMALL_REVISION_CONFIRMATIONS = 2
MAX_SMALL_REVISION_WORDS = 3
HALLUCINATION_PHRASES = [
    "copyright wdr 2021",
    "copyright wdr mediagroup digital gmbh",
]
VOSK_SUPPORTED_LANGUAGES = {"en", "de", "it"}


def handle_signal(signum, frame):
    global RUNNING
    RUNNING = False


for _sig in (signal.SIGINT, signal.SIGTERM):
    signal.signal(_sig, handle_signal)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--state-file", required=True)
    parser.add_argument("--backend", choices=["whisper", "asr"], default="whisper")
    parser.add_argument("--source", choices=["system", "mic"], default="system")
    parser.add_argument("--display-mode", choices=["captions", "translated", "bilingual"], default="bilingual")
    parser.add_argument("--language", default="auto")
    parser.add_argument("--target-language", choices=["en", "fr", "de", "es", "it", "pt", "nl", "ru", "zh", "ja", "ko", "pl", "ar", "hi", "tr", "sv", "da", "fi", "cs", "ro"], default="en")
    parser.add_argument("--translation-granularity", choices=["phrase", "sentence"], default="sentence")
    parser.add_argument("--translation-style", choices=["natural", "literal"], default="natural")
    parser.add_argument("--model", default="tiny")
    parser.add_argument("--preset", choices=["realtime", "snappy", "balanced", "accurate"], default="realtime")
    parser.add_argument("--model-cache-dir", default="")
    parser.add_argument("--step-seconds", type=float)
    parser.add_argument("--commit-ratio", type=float)
    parser.add_argument("--min-buffer-seconds", type=float)
    parser.add_argument("--silence-threshold", type=float)
    parser.add_argument("--stabilize-seconds", type=float)
    parser.add_argument("--fast-window-seconds", type=float)
    parser.add_argument("--history-limit", type=int, default=8)
    return parser.parse_args()


PRESET_DEFAULTS = {
    "realtime": {
        "step_seconds": 0.055,
        "stabilize_seconds": 0.72,
        "commit_ratio": 0.24,
        "fast_window_seconds": 1.05,
        "min_buffer_seconds": 0.09,
        "silence_threshold": 0.0029,
    },
    "snappy": {
        "step_seconds": 0.07,
        "stabilize_seconds": 0.56,
        "commit_ratio": 0.3,
        "fast_window_seconds": 1.35,
        "min_buffer_seconds": 0.11,
        "silence_threshold": 0.0031,
    },
    "balanced": {
        "step_seconds": 0.09,
        "stabilize_seconds": 0.44,
        "commit_ratio": 0.38,
        "fast_window_seconds": 1.75,
        "min_buffer_seconds": 0.13,
        "silence_threshold": 0.0033,
    },
    "accurate": {
        "step_seconds": 0.12,
        "stabilize_seconds": 0.32,
        "commit_ratio": 0.48,
        "fast_window_seconds": 2.35,
        "min_buffer_seconds": 0.16,
        "silence_threshold": 0.0036,
    },
}


def apply_preset(args: argparse.Namespace) -> argparse.Namespace:
    preset = PRESET_DEFAULTS.get(args.preset, PRESET_DEFAULTS["balanced"])
    for key, value in preset.items():
        if getattr(args, key, None) is None:
            setattr(args, key, value)
    return args


def write_state(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                     prefix=f".{path.name}.", suffix=".tmp", delete=False) as stream:
        temp_path = Path(stream.name)
        try:
            json.dump(payload, stream, ensure_ascii=False)
            stream.flush()
            temp_path.replace(path)
        finally:
            temp_path.unlink(missing_ok=True)


def build_base_state(args: argparse.Namespace) -> dict:
    return {
        "status": "starting",
        "message": "",
        "current_text": "",
        "stable_text": "",
        "unstable_text": "",
        "translated_text": "",
        "translated_stable_text": "",
        "translated_unstable_text": "",
        "translation_segments": [],
        "translation_style": getattr(args, "translation_style", "natural"),
        "translation_error": "",
        "source_language": "",
        "target_language": args.target_language,
        "history": [],
        "speech_active": False,
        "runtime_device": "",
        "backend_ready": True,
    }


def run_command(command: list[str], timeout: float = 5.0) -> str:
    result = subprocess.run(command, capture_output=True, text=True, timeout=timeout, check=True)
    return result.stdout.strip()


def resolve_pulse_device(source_mode: str) -> str:
    if source_mode == "mic":
        source_name = run_command(["pactl", "get-default-source"])
        if not source_name:
            raise RuntimeError("Could not determine default microphone source.")
        return source_name
    sink_name = run_command(["pactl", "get-default-sink"])
    if not sink_name:
        raise RuntimeError("Could not determine default output sink.")
    return f"{sink_name}.monitor"


def start_audio_capture(device_name: str) -> subprocess.Popen:
    return subprocess.Popen(
        [
            "ffmpeg", "-hide_banner", "-loglevel", "error",
            "-f", "pulse", "-i", device_name,
            "-ac", "1", "-ar", str(SAMPLE_RATE), "-f", "s16le", "-",
        ],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0,
    )


def stop_process(process: subprocess.Popen, *, process_group: bool = False) -> None:
    def send_signal(sig):
        try:
            if process_group:
                os.killpg(process.pid, sig)
            else:
                process.send_signal(sig)
        except ProcessLookupError:
            pass

    send_signal(signal.SIGTERM)
    try:
        process.wait(timeout=0.5)
    except subprocess.TimeoutExpired:
        send_signal(signal.SIGKILL)
        process.wait(timeout=1)
    finally:
        if process_group:
            # A shell can exit while its network helper ignores SIGTERM.
            send_signal(signal.SIGKILL)


class AudioCaptureReader:
    """Drain capture continuously so decoding cannot build a delayed audio queue."""

    MAX_BYTES = int(MAX_BUFFER_SECS * SAMPLE_RATE * 2)

    def __init__(self, process: subprocess.Popen):
        self.process = process
        self._chunks: deque[bytes] = deque()
        self._buffered_bytes = 0
        self._lock = threading.Lock()
        self._stop_event = threading.Event()
        self._ready = threading.Event()
        self._error = ""
        self._thread = threading.Thread(target=self._run, name="live-captions-audio", daemon=True)
        self._thread.start()

    def _run(self) -> None:
        pending = b""
        try:
            while not self._stop_event.is_set():
                readable, _, _ = select.select([self.process.stdout], [], [], 0.1)
                if not readable:
                    continue
                chunk = os.read(self.process.stdout.fileno(), 16384)
                if not chunk:
                    raise RuntimeError("Audio capture process exited unexpectedly.")
                pending += chunk
                complete_bytes = len(pending) - len(pending) % 2
                if not complete_bytes:
                    continue
                chunk, pending = pending[:complete_bytes], pending[complete_bytes:]
                with self._lock:
                    self._chunks.append(chunk)
                    self._buffered_bytes += len(chunk)
                    while self._buffered_bytes > self.MAX_BYTES:
                        oldest = self._chunks.popleft()
                        excess = self._buffered_bytes - self.MAX_BYTES
                        if len(oldest) > excess:
                            self._chunks.appendleft(oldest[excess:])
                            self._buffered_bytes -= excess
                        else:
                            self._buffered_bytes -= len(oldest)
                    self._ready.set()
        except (OSError, ValueError, RuntimeError) as error:
            if not self._stop_event.is_set():
                self._error = str(error)
        finally:
            self._ready.set()

    def read(self) -> bytes:
        self._ready.wait(timeout=0.1)
        with self._lock:
            chunk = b"".join(self._chunks)
            self._chunks.clear()
            self._buffered_bytes = 0
            self._ready.clear()
        if not chunk and self._error:
            raise RuntimeError(self._error)
        return chunk

    def stop(self) -> None:
        self._stop_event.set()
        stop_process(self.process)
        self._thread.join(timeout=0.5)
        if self.process.stdout is not None:
            self.process.stdout.close()


def pcm_to_float(pcm_bytes: bytes) -> np.ndarray:
    return np.frombuffer(pcm_bytes, dtype="<i2").astype(np.float32) / 32768.0


def normalize_text(text: str) -> str:
    return " ".join((text or "").split()).strip()


def normalized_words(text: str) -> list[str]:
    normalized = normalize_text(text)
    return normalized.split() if normalized else []


def comparable_word(word: str) -> str:
    return word.lower().strip(".,!?;:()[]{}\"'`")


def collapse_repeated_words(text: str, max_run: int = 2) -> str:
    words = normalized_words(text)
    if not words:
        return ""

    collapsed: list[str] = []
    previous_key = ""
    run_length = 0

    for word in words:
        key = comparable_word(word)
        if key and key == previous_key:
            run_length += 1
        else:
            previous_key = key
            run_length = 1

        if run_length <= max_run:
            collapsed.append(word)

    if not collapsed:
        return ""

    keys = [comparable_word(word) for word in collapsed if comparable_word(word)]
    if len(keys) >= 6:
        unique_ratio = len(set(keys)) / len(keys)
        if unique_ratio <= 0.34:
            deduped: list[str] = []
            seen: set[str] = set()
            for word in collapsed:
                key = comparable_word(word)
                if not key or key in seen:
                    continue
                deduped.append(word)
                seen.add(key)
            if deduped:
                return " ".join(deduped[:4])

    return " ".join(collapsed)


def collapse_repeated_phrases(text: str, max_phrase_words: int = 4) -> str:
    words = normalized_words(text)
    if len(words) < 4:
        return " ".join(words)

    collapsed: list[str] = []
    i = 0
    while i < len(words):
        repeated = False
        max_size = min(max_phrase_words, (len(words) - i) // 2)
        for size in range(max_size, 1, -1):
            phrase = [comparable_word(word) for word in words[i:i + size]]
            next_phrase = [comparable_word(word) for word in words[i + size:i + (size * 2)]]
            if phrase and phrase == next_phrase:
                collapsed.extend(words[i:i + size])
                i += size * 2
                repeated = True
                break

        if repeated:
            continue

        collapsed.append(words[i])
        i += 1

    return " ".join(collapsed)


def clean_transcript_text(text: str) -> str:
    cleaned = collapse_repeated_phrases(collapse_repeated_words(text, max_run=2))
    normalized_lower = comparable_word(cleaned)
    if any(phrase in normalized_lower for phrase in HALLUCINATION_PHRASES):
        return ""
    return cleaned


def strip_committed_overlap(committed_text: str, partial_text: str) -> str:
    committed_words = normalized_words(committed_text)
    partial_words = normalized_words(partial_text)
    max_overlap = min(len(committed_words), len(partial_words), 8)

    for overlap in range(max_overlap, 0, -1):
        committed_slice = [comparable_word(word) for word in committed_words[-overlap:]]
        partial_slice = [comparable_word(word) for word in partial_words[:overlap]]
        if committed_slice == partial_slice:
            return " ".join(partial_words[overlap:])

    return " ".join(partial_words)


def merge_continuous_text(base_text: str, next_text: str) -> str:
    base = normalize_text(base_text)
    nxt = normalize_text(next_text)

    if not base:
        return nxt
    if not nxt:
        return base

    base_words = normalized_words(base)
    next_words = normalized_words(nxt)
    base_keys = [comparable_word(word) for word in base_words]
    next_keys = [comparable_word(word) for word in next_words]
    if len(next_keys) <= len(base_keys) and base_keys[-len(next_keys):] == next_keys:
        return base
    if len(base_keys) <= len(next_keys) and next_keys[:len(base_keys)] == base_keys:
        return nxt
    max_overlap = min(len(base_words), len(next_words), 16)

    for overlap in range(max_overlap, 0, -1):
        base_slice = base_keys[-overlap:]
        next_slice = next_keys[:overlap]
        if base_slice == next_slice:
            return " ".join(base_words + next_words[overlap:])

    return f"{base} {nxt}"


def build_display_text(committed_words: list[str], partial_text: str, revisable_words: int = REVISABLE_COMMITTED_WORDS) -> str:
    stable_text, unstable_text = split_display_text(committed_words, partial_text, revisable_words)
    return merge_continuous_text(stable_text, unstable_text)


def split_display_text(committed_words: list[str], partial_text: str, revisable_words: int = REVISABLE_COMMITTED_WORDS) -> tuple[str, str]:
    committed = [normalize_text(word) for word in committed_words if normalize_text(word)]
    partial = normalize_text(partial_text)

    if not committed:
        return "", partial
    if not partial:
        return " ".join(committed), ""

    frozen_count = max(0, len(committed) - revisable_words)
    frozen_text = " ".join(committed[:frozen_count])
    revisable_text = " ".join(committed[frozen_count:])
    candidate_partial = clean_transcript_text(partial)

    if frozen_text:
        candidate_partial = strip_committed_overlap(frozen_text, candidate_partial)

    unstable_text = merge_continuous_text(revisable_text, candidate_partial)
    return frozen_text, unstable_text


def translate_literal(text: str, target_language: str, source_language: str = "",
                      stop_event: threading.Event | None = None, *, on_progress=None,
                      cache=None) -> str:
    # Natural translation remains independent of the optional local provider.
    try:
        from literal_translation import translate_literal as local_literal_translation
    except ImportError as error:
        raise RuntimeError("Literal translation backend is not installed.") from error
    return local_literal_translation(text, target_language, source_language, stop_event,
                                     on_progress=on_progress, cache=cache)


def translate_text(text: str, target_language: str, source_language: str = "",
                   stop_event: threading.Event | None = None) -> str:
    if not text:
        return ""
    try:
        process = subprocess.Popen(
            ["trans", "-brief", "-no-init", "-no-ansi", "-no-bidi", "-no-browser", "-no-play",
             f"{source_language}:{target_language}", "-i", "/dev/stdin"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            text=True, encoding="utf-8", start_new_session=True,
        )
    except OSError:
        return ""
    deadline = time.monotonic() + 10
    # translate-shell also interprets leading https:// in stdin as a web request.
    # A leading space keeps every input line literal, including URLs and file://.
    input_text = "\n".join(" " + line for line in text.splitlines()) + "\n"
    try:
        while time.monotonic() < deadline and not (stop_event and stop_event.is_set()):
            try:
                stdout, _ = process.communicate(input=input_text, timeout=0.1)
                return normalize_text(stdout) if process.returncode == 0 else ""
            except subprocess.TimeoutExpired:
                input_text = None
        return ""
    finally:
        stop_process(process, process_group=True)
        for stream in (process.stdin, process.stdout):
            if stream is not None:
                stream.close()


def set_status(path: Path, state: dict, status: str, message: str, *, backend_ready: bool = True) -> None:
    state.update({"status": status, "message": message, "backend_ready": backend_ready})
    if status == "error":
        state["translation_segments"] = []
    write_state(path, state)


def is_cuda_runtime_error(error: Exception) -> bool:
    text = str(error or "").lower()
    return (
        "libcublas" in text
        or "libcudnn" in text
        or "cudnn" in text
        or "cuda error" in text
        or "cuda failed" in text
        or "no cuda-capable device" in text
        or "cannot be loaded" in text and "cuda" in text
    )


class CaptionRuntimeFallback(RuntimeError):
    pass


def model_is_complete(path: Path) -> bool:
    return all(path.joinpath(name).is_file() for name in ("model.bin", "config.json", "tokenizer.json"))


def ensure_model(model_name: str, cache_root: str, state_path: Path, state: dict) -> str:
    from faster_whisper.utils import download_model
    model_dir = Path(cache_root) / model_name
    if not model_is_complete(model_dir):
        shutil.rmtree(model_dir, ignore_errors=True)
    if model_is_complete(model_dir):
        return str(model_dir)
    set_status(state_path, state, "downloading", f"Preparing the {model_name} speech model…")
    try:
        resolved_path = download_model(model_name, output_dir=str(model_dir), cache_dir=str(model_dir))
    except Exception:
        shutil.rmtree(model_dir, ignore_errors=True)
        resolved_path = download_model(model_name, output_dir=str(model_dir), cache_dir=str(model_dir))
    resolved = Path(resolved_path)
    if not model_is_complete(resolved):
        raise RuntimeError(f"Model download is incomplete at {resolved}.")
    return str(resolved)


def resolve_vosk_language(language: str) -> tuple[str, str]:
    code = normalize_text(language).split("-")[0].lower()
    if code in VOSK_SUPPORTED_LANGUAGES:
        return code, ""
    if code in {"", "auto"}:
        return "en", "Streaming ASR does not support auto-detect yet. Using English."
    return "en", (
        "Streaming ASR currently supports English, German, and Italian only. "
        f"Falling back to English instead of {code.upper()}."
    )


def ensure_vosk_model(language: str, cache_root: str) -> str:
    model_dir = Path(cache_root) / "vosk" / language
    if model_dir.joinpath("am").is_dir():
        return str(model_dir)
    raise RuntimeError(
        f"Vosk model for {language.upper()} is not installed at {model_dir}. "
        "Run the live captions installer again."
    )


def resolve_model_runtime() -> tuple[str, str]:
    try:
        import ctranslate2
        supported = ctranslate2.get_supported_compute_types("cuda")
        if supported:
            if "float16" in supported:
                return "cuda", "float16"
            if "int8_float16" in supported:
                return "cuda", "int8_float16"
            if "float32" in supported:
                return "cuda", "float32"
    except Exception:
        pass

    return "cpu", "int8"


def model_runtime_candidates(preferred_device: str, preferred_compute_type: str) -> list[tuple[str, str]]:
    candidates: list[tuple[str, str]] = []

    def add(device: str, compute_type: str) -> None:
        candidate = (device, compute_type)
        if candidate not in candidates:
            candidates.append(candidate)

    add(preferred_device, preferred_compute_type)

    if preferred_device == "cuda":
        add("cuda", "int8_float16")
        add("cuda", "float32")

    add("cpu", "int8")
    add("cpu", "float32")
    return candidates


def validate_model_runtime(model, device: str) -> None:
    if device != "cuda":
        return

    warmup_audio = np.zeros(int(0.25 * SAMPLE_RATE), dtype=np.float32)
    segments, _info = model.transcribe(
        warmup_audio,
        language="en",
        beam_size=1,
        best_of=1,
        vad_filter=False,
        condition_on_previous_text=False,
        temperature=0.0,
        word_timestamps=False,
    )

    try:
        next(iter(segments), None)
    except Exception as error:
        raise RuntimeError(f"CUDA warmup failed: {error}") from error


def load_model(model_path: str, force_device: str | None = None):
    from faster_whisper import WhisperModel
    if force_device == "cpu":
        preferred_device, preferred_compute_type = "cpu", "int8"
    else:
        preferred_device, preferred_compute_type = resolve_model_runtime()
    cpu_threads = max(4, min(16, os.cpu_count() or 4))
    last_error: Exception | None = None

    for device, compute_type in model_runtime_candidates(preferred_device, preferred_compute_type):
        try:
            model = WhisperModel(
                model_path,
                device=device,
                compute_type=compute_type,
                cpu_threads=cpu_threads,
                num_workers=1,
                local_files_only=True,
            )
            validate_model_runtime(model, device)
            return model, device
        except Exception as error:
            last_error = error

    raise RuntimeError(f"Could not initialize any caption runtime: {last_error}")


class AsyncTranslator:
    CACHE_LIMIT = 128
    RETRY_SECONDS = 2.0
    MAX_WORKERS = 2

    def __init__(self, translation_style: str = "natural"):
        if translation_style not in {"natural", "literal"}:
            raise ValueError("Translation style must be 'natural' or 'literal'.")
        self.translation_style = translation_style
        self._lock = threading.Lock()
        self._ready = threading.Condition(self._lock)
        self._stop_event = threading.Event()
        self._pending: OrderedDict[str, tuple[str, str, str]] = OrderedDict()
        self._inflight: set[tuple[str, str, str]] = set()
        self._task_stops: dict[tuple[str, str, str], threading.Event] = {}
        self._desired_by_stream: dict[str, tuple[str, str, str]] = {}
        self._visible_tasks: dict[str, tuple[str, str, str]] = {}
        self._errors: OrderedDict[tuple[str, str, str], str] = OrderedDict()
        self._cache: OrderedDict[tuple[str, str, str], str] = OrderedDict()
        self._progress: OrderedDict[tuple[str, str, str], dict] = OrderedDict()
        self._literal_cache = None
        if translation_style == "literal":
            from literal_translation import LiteralCache
            self._literal_cache = LiteralCache()
        self._retry_after: OrderedDict[tuple[str, str, str], float] = OrderedDict()
        self._latest_by_target: dict[tuple[str, str, str], tuple[str, str]] = {}
        self._threads = [threading.Thread(target=self._run,
                                         name=f"live-captions-translator-{index + 1}", daemon=True)
                         for index in range(1 if translation_style == "literal" else self.MAX_WORKERS)]
        for thread in self._threads:
            thread.start()

    def request(self, text: str, target_language: str, source_language: str = "", *,
                stream: str = "live", allow_partial: bool = True) -> str:
        normalized_text = normalize_text(text)
        source_code = source_language.replace("_", "-").split("-")[0].lower()
        if source_code == "auto":
            source_code = ""

        cache_key = (normalized_text, target_language, source_code)
        with self._lock:
            if not normalized_text or (source_code and source_code == target_language):
                self._pending.pop(stream, None)
                self._desired_by_stream.pop(stream, None)
                self._visible_tasks.pop(stream, None)
                self._cancel_obsolete_literal_work()
                return normalized_text

            self._visible_tasks[stream] = cache_key
            self._cancel_obsolete_literal_work()
            if cache_key in self._cache:
                self._pending.pop(stream, None)
                self._desired_by_stream.pop(stream, None)
                self._cache.move_to_end(cache_key)
                self._remember_latest(stream, cache_key, self._cache[cache_key])
                return self._cache[cache_key]

            latest = self._latest_by_target.get((target_language, source_code, stream))
            if self._stop_event.is_set() or time.monotonic() < self._retry_after.get(cache_key, 0):
                self._pending.pop(stream, None)
                self._desired_by_stream.pop(stream, None)
            elif cache_key in self._inflight and not (
                    cache_key in self._task_stops and self._task_stops[cache_key].is_set()):
                # A revision can revert to text already being translated. Remove
                # its superseded queue entry even though no new task is needed.
                self._pending.pop(stream, None)
                self._desired_by_stream[stream] = cache_key
            else:
                # Replacing a queued revision preserves its position, so a
                # frequently changing live phrase cannot starve other streams.
                self._pending[stream] = cache_key
                self._desired_by_stream[stream] = cache_key
                self._ready.notify_all()

            if allow_partial and self.translation_style == "natural" and latest is not None:
                latest_source, latest_translation = latest
                if latest_translation and self._is_reusable_translation(latest_source, normalized_text):
                    return latest_translation
        return ""

    @staticmethod
    def _exact_prefix(prefix: str, text: str) -> bool:
        # Never reuse half of a word, or a translation of text Whisper revised.
        return bool(prefix) and text.startswith(prefix) and (
            len(prefix) == len(text) or text[len(prefix)].isspace()
            or (unicodedata.category(text[len(prefix)]).startswith("P")
                and text[len(prefix)] not in "'’_-\u2010\u2011")
        )

    def request_snapshot(self, text: str, target_language: str, source_language: str = "", *,
                         stream: str = "live") -> dict:
        """Keep completed prefixes visible while a growing source is translated."""
        empty = {"source": "", "translated": "", "complete": False}
        if self._stop_event.is_set():
            return empty
        text = normalize_text(text)
        source_code = source_language.replace("_", "-").split("-")[0].lower()
        if source_code == "auto":
            source_code = ""
        translated = self.request(text, target_language, source_code,
                                  stream=stream, allow_partial=False)
        if translated:
            with self._lock:
                if self._stop_event.is_set():
                    return empty
                return {"source": text, "translated": translated, "complete": True}
        # The literal cache keeps a revisable tail for new right-hand context.
        # Do not bypass that safeguard by exposing all of an older callback.
        best = (self._literal_cache.snapshot(text, target_language, source_code)
                if self._literal_cache is not None else None) or empty
        with self._lock:
            if self._stop_event.is_set():
                return empty
            candidates = [(key, {"source": key[0], "translated": value})
                          for key, value in self._cache.items()]
            candidates.extend(self._progress.items())
            for key, candidate in candidates:
                if self.translation_style == "literal" and key[0] != text:
                    continue
                prefix = candidate["source"]
                if (key[1:] == (target_language, source_code)
                        and candidate["translated"] and self._exact_prefix(prefix, text)
                        and len(prefix) >= len(best["source"])):
                    best = {"source": prefix, "translated": candidate["translated"],
                            "complete": prefix == text and candidate.get("complete", True)}
        return best

    def _publish_progress(self, task: tuple[str, str, str], snapshot: dict) -> None:
        prefix = normalize_text(snapshot.get("source", ""))
        translated = normalize_text(snapshot.get("translated", ""))
        if not translated or not self._exact_prefix(prefix, task[0]):
            return
        with self._lock:
            task_stop = self._task_stops.get(task)
            if self._stop_event.is_set() or (task_stop is not None and task_stop.is_set()):
                return
            self._progress[task] = {"source": prefix, "translated": translated,
                                    "complete": bool(snapshot.get("complete", False))}
            self._progress.move_to_end(task)
            while len(self._progress) > self.CACHE_LIMIT:
                self._progress.popitem(last=False)

    def retain_streams(self, streams: set[str]) -> None:
        """Drop obsolete queued phrases when the source window scrolls."""
        with self._lock:
            self._pending = OrderedDict((key, value) for key, value in self._pending.items()
                                        if key in streams)
            self._desired_by_stream = {key: value for key, value in self._desired_by_stream.items()
                                       if key in streams}
            self._visible_tasks = {key: value for key, value in self._visible_tasks.items()
                                   if key in streams}
            self._latest_by_target = {key: value for key, value in self._latest_by_target.items()
                                      if key[2] in streams}
            self._cancel_obsolete_literal_work()

    def _cancel_obsolete_literal_work(self) -> None:
        """Cancel unrelated work, while useful prefixes survive ASR tail edits."""
        for task, stop in self._task_stops.items():
            if not any(task[1:] == visible[1:] and self._literal_cache is not None
                       and self._literal_cache.can_reuse_source(task[0], visible[0])
                       for visible in self._visible_tasks.values()):
                stop.set()

    def error(self) -> str:
        """Expose errors only for source revisions still visible in this pane."""
        with self._lock:
            return next((self._errors[task] for task in self._visible_tasks.values()
                         if task in self._errors), "")

    @staticmethod
    def _is_reusable_translation(previous_source: str, next_source: str) -> bool:
        previous_words = normalized_words(previous_source)
        next_words = normalized_words(next_source)
        if not previous_words or not next_words:
            return False

        return len(previous_words) <= len(next_words) and all(
            comparable_word(previous_word) == comparable_word(next_word)
            for previous_word, next_word in zip(previous_words, next_words)
        )

    def stop(self) -> None:
        with self._ready:
            self._stop_event.set()
            self._pending.clear()
            self._desired_by_stream.clear()
            self._visible_tasks.clear()
            for stop in self._task_stops.values():
                stop.set()
            self._ready.notify_all()
        # Both subprocesses receive cancellation together. Use one bounded
        # deadline rather than adding a full shutdown timeout per worker.
        deadline = time.monotonic() + 2.0
        for thread in self._threads:
            thread.join(timeout=max(0, deadline - time.monotonic()))

    def _remember_latest(self, stream: str, task: tuple[str, str, str], translated: str) -> None:
        text, target_language, source_language = task
        self._latest_by_target[(target_language, source_language, stream)] = (text, translated)
        while len(self._latest_by_target) > self.CACHE_LIMIT:
            del self._latest_by_target[next(iter(self._latest_by_target))]

    def _finish(self, task: tuple[str, str, str], translated: str, error: str = "") -> None:
        """Publish under the lock only to streams still requesting this revision."""
        if translated:
            self._cache[task] = translated
            self._cache.move_to_end(task)
            self._retry_after.pop(task, None)
            self._errors.pop(task, None)
            while len(self._cache) > self.CACHE_LIMIT:
                self._cache.popitem(last=False)
        else:
            if self.translation_style == "literal":
                self._errors[task] = error or "Literal translation unavailable. Retrying…"
                self._errors.move_to_end(task)
                while len(self._errors) > self.CACHE_LIMIT:
                    self._errors.popitem(last=False)
            self._retry_after[task] = time.monotonic() + self.RETRY_SECONDS
            self._retry_after.move_to_end(task)
            while len(self._retry_after) > self.CACHE_LIMIT:
                self._retry_after.popitem(last=False)

        for stream, desired in list(self._desired_by_stream.items()):
            if desired == task:
                self._desired_by_stream.pop(stream)
                if translated:
                    self._remember_latest(stream, task, translated)

    def _run(self) -> None:
        while True:
            with self._ready:
                while True:
                    if self._stop_event.is_set():
                        return
                    if not self._pending:
                        self._ready.wait()
                        continue
                    stream, task = self._pending.popitem(last=False)
                    if task in self._inflight:
                        continue
                    cached = self._cache.get(task)
                    if cached:
                        self._finish(task, cached)
                        continue
                    if time.monotonic() < self._retry_after.get(task, 0):
                        self._desired_by_stream.pop(stream, None)
                        continue
                    self._inflight.add(task)
                    task_stop = self._stop_event
                    if self.translation_style == "literal":
                        task_stop = threading.Event()
                        self._task_stops[task] = task_stop
                    break

            text, target_language, source_language = task
            error = ""
            try:
                if self.translation_style == "literal":
                    translated = translate_literal(text, target_language, source_language,
                        task_stop, cache=self._literal_cache,
                        on_progress=lambda snapshot: self._publish_progress(task, snapshot))
                else:
                    translated = translate_text(text, target_language, source_language, self._stop_event)
            except Exception as exception:
                # A provider or decoding error must not permanently kill a worker.
                translated = ""
                if self.translation_style == "literal":
                    error = str(exception) or "Literal translation unavailable. Retrying…"

            with self._ready:
                self._inflight.discard(task)
                self._task_stops.pop(task, None)
                if self._stop_event.is_set():
                    return
                if not task_stop.is_set():
                    self._finish(task, translated, error)
                self._ready.notify_all()


def translated_texts(translator: AsyncTranslator, display_text: str, stable_text: str,
                     target_language: str, source_language: str) -> tuple[str, str, str]:
    stable = translator.request(stable_text, target_language, source_language, stream="stable")
    full = translator.request(display_text, target_language, source_language, stream="live")
    if not full:
        return stable, stable, ""
    stable_words = normalized_words(stable)
    full_words = normalized_words(full)
    if stable_words and len(stable_words) <= len(full_words) and all(
        comparable_word(left) == comparable_word(right)
        for left, right in zip(stable_words, full_words)
    ):
        return full, stable, " ".join(full_words[len(stable_words):])
    # A translation may reorder the sentence. Show its complete current version
    # once instead of presenting it underneath a duplicate earlier translation.
    return full, "", full


def paired_translations(translator: AsyncTranslator, tracker: SegmentTracker,
                        display_text: str, stable_text: str, target_language: str,
                        source_language: str) -> tuple[str, str, str, list[dict]]:
    """Translate exact source units, without guessing alignment from target order."""
    segments = tracker.update(display_text)
    translator.retain_streams({item["id"] for item in segments})
    # Start the most recent phrase first; unchanged older phrases use the cache.
    for item in reversed(segments):
        snapshot = translator.request_snapshot(item["source"], target_language, source_language,
                                               stream=item["id"])
        item.update({"translated": snapshot["translated"], "translated_source": snapshot["source"],
                     "pending": not snapshot["complete"]})

    stable_source = normalize_text(stable_text)
    stable_parts, live_parts = [], []
    offset = 0
    for item in segments:
        completed_source = item["translated_source"]
        position = stable_source.find(completed_source, offset)
        if completed_source and position >= 0:
            stable_parts.append(item["translated"])
            offset = position + len(completed_source)
        else:
            live_parts.append(item["translated"])
    return (" ".join(item["translated"] for item in segments if item["translated"]),
            " ".join(part for part in stable_parts if part),
            " ".join(part for part in live_parts if part), segments)


class VoskStreamingTranscriber:
    RECENT_AUDIO_SAMPLES = int(0.35 * SAMPLE_RATE)

    def __init__(self, model_path: str, language: str, silence_threshold: float = 0.005):
        from vosk import KaldiRecognizer, Model, SetLogLevel

        SetLogLevel(-1)
        self.language = language
        self.silence_threshold = silence_threshold
        self.model = Model(model_path)
        self.recognizer = KaldiRecognizer(self.model, SAMPLE_RATE)
        self.recognizer.SetWords(True)
        self.committed_segments: list[str] = []
        self.partial_text = ""
        self.source_language = language
        self.runtime_device = "vosk"
        self.recent_audio = np.zeros(0, dtype=np.float32)

    def feed(self, pcm_bytes: bytes) -> None:
        audio_chunk = pcm_to_float(pcm_bytes)
        self.recent_audio = np.concatenate([self.recent_audio, audio_chunk])
        if len(self.recent_audio) > self.RECENT_AUDIO_SAMPLES:
            self.recent_audio = self.recent_audio[-self.RECENT_AUDIO_SAMPLES:]

        if self.recognizer.AcceptWaveform(pcm_bytes):
            result = json.loads(self.recognizer.Result() or "{}")
            final_text = clean_transcript_text(result.get("text", ""))
            if final_text:
                self._append_committed_segment(final_text)
            self.partial_text = ""
            return

        result = json.loads(self.recognizer.PartialResult() or "{}")
        partial = clean_transcript_text(result.get("partial", ""))
        self.partial_text = partial

    def speech_active(self) -> bool:
        if len(self.recent_audio) == 0:
            return False
        return float(np.sqrt(np.mean(self.recent_audio ** 2))) >= self.silence_threshold

    def texts(self) -> tuple[str, str, str]:
        stable_text = "\n".join(self.committed_segments[-4:])
        unstable_text = normalize_text(self.partial_text)
        display_text = stable_text
        if unstable_text:
            display_text = f"{stable_text}\n{unstable_text}".strip() if stable_text else unstable_text
        return display_text, stable_text, unstable_text

    def committed_word_count(self) -> int:
        return sum(len(normalized_words(segment)) for segment in self.committed_segments)

    def _append_committed_segment(self, text: str) -> None:
        segment = clean_transcript_text(text)
        if not segment:
            return

        # Vosk final results are separate utterances, not overlapping windows.
        self.committed_segments.append(segment)
        self.committed_segments = self.committed_segments[-8:]


class StreamingTranscriber:
    """
    Uses a fast partial pass for responsiveness and a slower stabilizer pass to
    commit older words from a larger rolling buffer.
    """

    MAX_BUFFER_SAMPLES = int(MAX_BUFFER_SECS * SAMPLE_RATE)

    def __init__(
        self,
        model,
        language: str,
        commit_ratio: float = 0.6,
        min_buffer_seconds: float = 0.3,
        silence_threshold: float = 0.005,
        fast_window_seconds: float = 2.4,
    ):
        self.model = model
        self.language = None if language == "auto" else language
        self.commit_ratio = commit_ratio
        self.min_buffer_seconds = min_buffer_seconds
        self.silence_threshold = silence_threshold
        self.fast_window_samples = int(fast_window_seconds * SAMPLE_RATE)
        self.audio_buffer = np.zeros(0, dtype=np.float32)
        self.committed_audio_end = 0.0
        self.committed_words: list[str] = []
        self.source_language = ""
        self.last_partial = ""
        self.pending_partial = ""
        self.pending_partial_count = 0
        self.runtime_device = "cpu"

    def feed(self, chunk: np.ndarray) -> None:
        self.audio_buffer = np.concatenate([self.audio_buffer, chunk])
        if len(self.audio_buffer) > self.MAX_BUFFER_SAMPLES:
            dropped_seconds = (len(self.audio_buffer) - self.MAX_BUFFER_SAMPLES) / SAMPLE_RATE
            self.committed_audio_end = max(0.0, self.committed_audio_end - dropped_seconds)
            self.audio_buffer = self.audio_buffer[-self.MAX_BUFFER_SAMPLES:]

    def _audio_usable(self, audio: np.ndarray) -> bool:
        buf_dur = len(audio) / SAMPLE_RATE
        if buf_dur < self.min_buffer_seconds:
            return False

        if float(np.sqrt(np.mean(audio ** 2))) < self.silence_threshold:
            return False
        return True

    def fast_partial(self) -> str:
        audio = self.audio_buffer[-self.fast_window_samples:]
        if not self._audio_usable(audio):
            return ""

        try:
            segs, info = self.model.transcribe(
                audio,
                language=self.language,
                beam_size=1,
                best_of=1,
                vad_filter=False,
                condition_on_previous_text=False,
                temperature=0.0,
                repetition_penalty=1.18,
                no_repeat_ngram_size=3,
                compression_ratio_threshold=1.9,
                no_speech_threshold=0.45,
                word_timestamps=False,
                initial_prompt=self._committed_tail(),
            )
            if info.language:
                self.source_language = info.language
            partial = normalize_text(" ".join(
                normalize_text(seg.text)
                for seg in segs
                if normalize_text(seg.text)
            ))
            partial = clean_transcript_text(partial)
            return self._smooth_partial(partial)
        except Exception as error:
            if self.runtime_device == "cuda" and is_cuda_runtime_error(error):
                raise CaptionRuntimeFallback(str(error))
            raise RuntimeError(f"Speech decoding failed: {error}") from error

    def stabilize(self, final: bool = False) -> str:
        audio = self.audio_buffer
        if not self._audio_usable(audio):
            return self._committed_tail()

        buf_dur = len(audio) / SAMPLE_RATE
        threshold = buf_dur if final else buf_dur * self.commit_ratio

        try:
            segs, info = self.model.transcribe(
                audio,
                language=self.language,
                beam_size=1,
                best_of=1,
                vad_filter=False,
                condition_on_previous_text=False,
                temperature=0.0,
                repetition_penalty=1.12,
                no_repeat_ngram_size=3,
                compression_ratio_threshold=2.0,
                no_speech_threshold=0.45,
                word_timestamps=True,
                initial_prompt=self._committed_tail(),
            )
            words = [
                (w.start, w.end, normalize_text(w.word))
                for seg in segs
                for w in (seg.words or [])
                if normalize_text(w.word)
            ]
            if info.language:
                self.source_language = info.language
        except Exception as error:
            if self.runtime_device == "cuda" and is_cuda_runtime_error(error):
                raise CaptionRuntimeFallback(str(error))
            raise RuntimeError(f"Speech decoding failed: {error}") from error

        if not words:
            return self._committed_tail()

        to_commit = [
            (s, e, w) for s, e, w in words
            if e <= threshold and e > self.committed_audio_end
            and s >= self.committed_audio_end - 0.05
            and (not final or self._word_has_audio(s, e))
        ]

        if to_commit:
            last_end = to_commit[-1][1]
            self._append_committed_words([w for _, _, w in to_commit])
            # A final pass must cover the entire remaining utterance. Keep its
            # timestamp origin intact until finalize_phrase clears the buffer.
            trim_secs = 0.0 if final else max(0.0, last_end - 0.45)
            trim_samples = int(trim_secs * SAMPLE_RATE)
            self.committed_audio_end = last_end - trim_samples / SAMPLE_RATE
            if trim_samples > 0:
                self.audio_buffer = self.audio_buffer[trim_samples:]
        return self._committed_tail()

    def _word_has_audio(self, start: float, end: float) -> bool:
        first = max(0, int(start * SAMPLE_RATE))
        last = min(len(self.audio_buffer), int(end * SAMPLE_RATE))
        audio = self.audio_buffer[first:last]
        return bool(len(audio)) and float(np.sqrt(np.mean(audio ** 2))) >= self.silence_threshold

    def finalize_phrase(self, partial_text: str = "") -> str:
        """Flush real uncommitted speech before discarding a silent audio window."""
        previous_end = self.committed_audio_end
        uncommitted = self.audio_buffer[max(0, int(previous_end * SAMPLE_RATE)):]
        had_uncommitted_speech = self._audio_usable(uncommitted)
        # Exceptions leave the buffer intact so a CPU fallback can retry it.
        self.stabilize(final=True)
        fallback = partial_text if had_uncommitted_speech and self.committed_audio_end <= previous_end else ""
        self.commit_partial_phrase(fallback)
        return self._committed_tail()

    def speech_active(self) -> bool:
        audio = self.audio_buffer[-int(0.25 * SAMPLE_RATE):]
        if len(audio) == 0:
            return False
        return float(np.sqrt(np.mean(audio ** 2))) >= self.silence_threshold

    def _append_committed_words(self, new_words: list[str]) -> None:
        for word in new_words:
            normalized = normalize_text(word)
            if not normalized:
                continue

            if self.committed_words:
                if comparable_word(self.committed_words[-1]) == comparable_word(normalized):
                    run = 1
                    for previous in reversed(self.committed_words[:-1]):
                        if comparable_word(previous) != comparable_word(normalized):
                            break
                        run += 1
                    if run >= 2:
                        continue

            self.committed_words.append(normalized)

        committed_text = clean_transcript_text(" ".join(self.committed_words))
        self.committed_words = normalized_words(committed_text)[-MAX_COMMITTED_WORDS:]

    def _smooth_partial(self, candidate: str) -> str:
        candidate = normalize_text(candidate)
        if not candidate:
            self.last_partial = ""
            self.pending_partial = ""
            self.pending_partial_count = 0
            return ""

        previous_words = normalized_words(self.last_partial)
        candidate_words = normalized_words(candidate)

        if previous_words:
            common_prefix = 0
            for prev_word, next_word in zip(previous_words, candidate_words):
                if comparable_word(prev_word) != comparable_word(next_word):
                    break
                common_prefix += 1

            changed_tail = max(len(previous_words), len(candidate_words)) - common_prefix
            only_tail_guessing = (
                common_prefix >= max(0, min(len(previous_words), len(candidate_words)) - 1)
                and changed_tail <= 2
                and len(candidate_words) <= len(previous_words) + 1
            )
            extension_only = (
                common_prefix == len(previous_words)
                and len(candidate_words) > len(previous_words)
            )
            small_revision = (
                not extension_only
                and common_prefix >= max(0, min(len(previous_words), len(candidate_words)) - MAX_SMALL_REVISION_WORDS)
                and changed_tail <= MAX_SMALL_REVISION_WORDS + 1
            )

            confirmation_goal = 1

            if only_tail_guessing:
                confirmation_goal = TAIL_GUESS_CONFIRMATIONS
            elif small_revision:
                confirmation_goal = SMALL_REVISION_CONFIRMATIONS
            elif extension_only and len(candidate_words) == len(previous_words) + 1:
                confirmation_goal = SMALL_REVISION_CONFIRMATIONS

            if confirmation_goal > 1:
                if candidate == self.pending_partial:
                    self.pending_partial_count += 1
                else:
                    self.pending_partial = candidate
                    self.pending_partial_count = 1

                if self.pending_partial_count < confirmation_goal:
                    return self.last_partial

                self.pending_partial = ""
                self.pending_partial_count = 0
            else:
                self.pending_partial = ""
                self.pending_partial_count = 0

        self.last_partial = candidate
        return candidate

    def _committed_tail(self) -> str:
        return " ".join(self.committed_words[-8:])

    def commit_partial_phrase(self, partial_text: str) -> bool:
        candidate = clean_transcript_text(normalize_text(partial_text))

        committed_context = " ".join(self.committed_words[-12:])
        if committed_context:
            candidate = strip_committed_overlap(committed_context, candidate)
            candidate = clean_transcript_text(candidate)

        candidate_words = normalized_words(candidate)
        if candidate_words:
            self._append_committed_words(candidate_words)
        # Silence closes the audio window even if its final word was already committed.
        self.audio_buffer = np.zeros(0, dtype=np.float32)
        self.committed_audio_end = 0.0
        self.last_partial = ""
        self.pending_partial = ""
        self.pending_partial_count = 0
        return bool(candidate_words)

    def reset(self) -> None:
        self.audio_buffer = np.zeros(0, dtype=np.float32)
        self.committed_audio_end = 0.0
        self.committed_words = []
        self.source_language = ""
        self.last_partial = ""
        self.pending_partial = ""
        self.pending_partial_count = 0


def run_streaming_asr_backend(args: argparse.Namespace, state_path: Path, state: dict) -> int:
    resolved_language, language_message = resolve_vosk_language(args.language)

    try:
        model_path = ensure_vosk_model(resolved_language, args.model_cache_dir)
    except Exception as error:
        print(f"Could not prepare streaming ASR model: {error}", file=sys.stderr)
        state.update({
            "status": "error",
            "message": f"Could not prepare streaming ASR model: {error}",
            "backend_ready": False,
        })
        write_state(state_path, state)
        return 2

    try:
        pulse_device = resolve_pulse_device(args.source)
    except Exception as error:
        print(str(error), file=sys.stderr)
        state.update({"status": "error", "message": str(error)})
        write_state(state_path, state)
        return 3

    set_status(
        state_path,
        state,
        "loading",
        language_message or "Loading streaming ASR…",
    )

    try:
        transcriber = VoskStreamingTranscriber(
            model_path,
            resolved_language,
            args.silence_threshold,
        )
    except Exception as error:
        print(f"Could not load streaming ASR: {error}", file=sys.stderr)
        state.update({
            "status": "error",
            "message": f"Could not load streaming ASR: {error}",
            "runtime_device": "",
            "backend_ready": False,
        })
        write_state(state_path, state)
        return 2

    try:
        capture = AudioCaptureReader(start_audio_capture(pulse_device))
    except OSError as error:
        set_status(state_path, state, "error", f"Could not start audio capture: {error}")
        return 3
    translator = AsyncTranslator(getattr(args, "translation_style", "natural"))
    segment_tracker = SegmentTracker(granularity=getattr(args, "translation_granularity", "sentence"))
    last_display_text = ""
    last_translated_text = ""
    last_translated_stable_text = ""
    last_translated_unstable_text = ""
    last_committed_count = 0

    state.update({
        "status": "running",
        "message": language_message or "Listening to audio…",
        "runtime_device": transcriber.runtime_device,
        "source_language": resolved_language,
        "backend_ready": True,
    })
    write_state(state_path, state)

    try:
        while RUNNING:
            chunk = capture.read()
            if not chunk:
                time.sleep(0.01)
                continue

            transcriber.feed(chunk)
            display_text, stable_text, unstable_text = transcriber.texts()
            speech_active = transcriber.speech_active()
            committed_count = transcriber.committed_word_count()

            if args.display_mode == "captions":
                translated_text, translated_stable_text, translated_unstable_text = "", "", ""
                translation_segments = []
            else:
                (translated_text, translated_stable_text, translated_unstable_text,
                 translation_segments) = paired_translations(
                    translator, segment_tracker, display_text, stable_text,
                    args.target_language, transcriber.source_language,
                )

            translation_error = translator.error() if args.display_mode != "captions" else ""

            if (
                display_text == last_display_text
                and translated_text == last_translated_text
                and translated_stable_text == last_translated_stable_text
                and translated_unstable_text == last_translated_unstable_text
                and translation_segments == state.get("translation_segments")
                and translation_error == state.get("translation_error", "")
                and committed_count == last_committed_count
                and stable_text == state.get("stable_text")
                and unstable_text == state.get("unstable_text")
                and speech_active == state.get("speech_active")
                and transcriber.source_language == state.get("source_language")
            ):
                continue

            last_display_text = display_text
            last_translated_text = translated_text
            last_translated_stable_text = translated_stable_text
            last_translated_unstable_text = translated_unstable_text
            last_committed_count = committed_count

            state.update({
                "status": "running",
                "message": translation_error or language_message or "Listening to audio…",
                "translation_error": translation_error,
                "current_text": display_text,
                "stable_text": stable_text,
                "unstable_text": unstable_text,
                "translated_text": translated_text,
                "translated_stable_text": translated_stable_text,
                "translated_unstable_text": translated_unstable_text,
                "translation_segments": translation_segments,
                "source_language": transcriber.source_language,
                "target_language": args.target_language,
                "history": [],
                "speech_active": speech_active,
                "runtime_device": transcriber.runtime_device,
                "backend_ready": True,
            })
            write_state(state_path, state)
    except Exception as error:
        print(str(error), file=sys.stderr)
        set_status(state_path, state, "error", str(error))
        return 4
    finally:
        translator.stop()
        capture.stop()

    state.update({"status": "stopped", "message": "Live captions stopped.",
                  "translation_segments": [], "translation_error": ""})
    write_state(state_path, state)
    return 0


def main() -> int:
    args = parse_args()
    args = apply_preset(args)
    state_path = Path(args.state_file)
    state = build_base_state(args)
    write_state(state_path, state)

    if args.backend == "asr":
        return run_streaming_asr_backend(args, state_path, state)

    model_path = args.model
    if args.model_cache_dir:
        try:
            model_path = ensure_model(args.model, args.model_cache_dir, state_path, state)
        except Exception as error:
            print(f"Could not prepare speech model: {error}", file=sys.stderr)
            state.update({
                "status": "error",
                "message": f"Could not prepare speech model: {error}",
                "backend_ready": False,
            })
            write_state(state_path, state)
            return 2

    set_status(state_path, state, "loading", "Loading caption model…")

    try:
        model, runtime_device = load_model(model_path)
    except Exception as error:
        print(f"Could not load faster-whisper: {error}", file=sys.stderr)
        state.update({
            "status": "error",
            "message": f"Could not load faster-whisper: {error}",
            "runtime_device": "",
            "backend_ready": False,
        })
        write_state(state_path, state)
        return 2

    try:
        pulse_device = resolve_pulse_device(args.source)
    except Exception as error:
        print(str(error), file=sys.stderr)
        state.update({"status": "error", "message": str(error)})
        write_state(state_path, state)
        return 3

    try:
        capture = AudioCaptureReader(start_audio_capture(pulse_device))
    except OSError as error:
        set_status(state_path, state, "error", f"Could not start audio capture: {error}")
        return 3
    transcriber = StreamingTranscriber(
        model,
        args.language,
        args.commit_ratio,
        args.min_buffer_seconds,
        args.silence_threshold,
        args.fast_window_seconds,
    )
    transcriber.runtime_device = runtime_device
    translator = AsyncTranslator(getattr(args, "translation_style", "natural"))
    segment_tracker = SegmentTracker(granularity=getattr(args, "translation_granularity", "sentence"))
    last_fast_tick = time.monotonic()
    last_stable_tick = time.monotonic()
    last_display_text = ""
    last_translated_text = ""
    last_translated_stable_text = ""
    last_translated_unstable_text = ""
    last_committed_count = 0
    current_partial = ""
    committed_tail = ""
    phrase_closed_for_silence = False

    state.update({
        "status": "running",
        "message": "Listening to audio…",
        "runtime_device": runtime_device,
        "backend_ready": True,
    })
    write_state(state_path, state)
    silence_started_at = time.monotonic()

    try:
        while RUNNING:
            chunk = capture.read()
            if not chunk:
                time.sleep(0.01)
                continue

            transcriber.feed(pcm_to_float(chunk))

            now = time.monotonic()
            if now - last_fast_tick >= args.step_seconds:
                try:
                    current_partial = transcriber.fast_partial()
                except CaptionRuntimeFallback:
                    model, runtime_device = load_model(model_path, force_device="cpu")
                    transcriber.model = model
                    transcriber.runtime_device = runtime_device
                    state.update({
                        "status": "running",
                        "message": "CUDA failed during decoding, fell back to CPU.",
                        "runtime_device": runtime_device,
                        "backend_ready": True,
                    })
                    write_state(state_path, state)
                    current_partial = ""
                last_fast_tick = now

            if now - last_stable_tick >= args.stabilize_seconds:
                try:
                    committed_tail = transcriber.stabilize()
                except CaptionRuntimeFallback:
                    model, runtime_device = load_model(model_path, force_device="cpu")
                    transcriber.model = model
                    transcriber.runtime_device = runtime_device
                    state.update({
                        "status": "running",
                        "message": "CUDA failed during decoding, fell back to CPU.",
                        "runtime_device": runtime_device,
                        "backend_ready": True,
                    })
                    write_state(state_path, state)
                    committed_tail = transcriber._committed_tail()
                last_stable_tick = now

            speech_active = transcriber.speech_active()
            if speech_active:
                silence_started_at = now
                phrase_closed_for_silence = False
            elif now - silence_started_at > 0.75:
                if not phrase_closed_for_silence:
                    final_partial = current_partial or transcriber.last_partial
                    try:
                        committed_tail = transcriber.finalize_phrase(final_partial)
                    except CaptionRuntimeFallback:
                        model, runtime_device = load_model(model_path, force_device="cpu")
                        transcriber.model = model
                        transcriber.runtime_device = runtime_device
                        state.update({
                            "status": "running",
                            "message": "CUDA failed during decoding, fell back to CPU.",
                            "runtime_device": runtime_device,
                            "backend_ready": True,
                        })
                        write_state(state_path, state)
                        committed_tail = transcriber.finalize_phrase(final_partial)
                    phrase_closed_for_silence = True
                current_partial = ""

            committed_count = len(transcriber.committed_words)

            stable_text, unstable_text = split_display_text(transcriber.committed_words, current_partial)
            display_text = merge_continuous_text(stable_text, unstable_text)

            if args.display_mode == "captions":
                translated_text, translated_stable_text, translated_unstable_text = "", "", ""
                translation_segments = []
            else:
                (translated_text, translated_stable_text, translated_unstable_text,
                 translation_segments) = paired_translations(
                    translator, segment_tracker, display_text, stable_text,
                    args.target_language, transcriber.source_language,
                )

            translation_error = translator.error() if args.display_mode != "captions" else ""

            if (
                display_text == last_display_text
                and translated_text == last_translated_text
                and translated_stable_text == last_translated_stable_text
                and translated_unstable_text == last_translated_unstable_text
                and translation_segments == state.get("translation_segments")
                and translation_error == state.get("translation_error", "")
                and committed_count == last_committed_count
                and stable_text == state.get("stable_text")
                and unstable_text == state.get("unstable_text")
                and speech_active == state.get("speech_active")
                and transcriber.source_language == state.get("source_language")
            ):
                continue

            last_display_text = display_text
            last_translated_text = translated_text
            last_translated_stable_text = translated_stable_text
            last_translated_unstable_text = translated_unstable_text
            last_committed_count = committed_count

            state.update({
                "status": "running",
                "message": translation_error or "Listening to audio…",
                "translation_error": translation_error,
                "current_text": display_text,
                "stable_text": stable_text,
                "unstable_text": unstable_text,
                "translated_text": translated_text,
                "translated_stable_text": translated_stable_text,
                "translated_unstable_text": translated_unstable_text,
                "translation_segments": translation_segments,
                "source_language": transcriber.source_language,
                "target_language": args.target_language,
                "history": [],
                "speech_active": speech_active,
                "runtime_device": transcriber.runtime_device,
                "backend_ready": True,
            })
            write_state(state_path, state)
    except Exception as error:
        print(str(error), file=sys.stderr)
        set_status(state_path, state, "error", str(error))
        return 4
    finally:
        translator.stop()
        capture.stop()

    state.update({"status": "stopped", "message": "Live captions stopped.",
                  "translation_segments": [], "translation_error": ""})
    write_state(state_path, state)
    return 0


if __name__ == "__main__":
    sys.exit(main())
