#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import shutil
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path

import numpy as np

RUNNING = True
SAMPLE_RATE = 16000
MAX_BUFFER_SECS = 8.0
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
    parser.add_argument("--model", default="tiny")
    parser.add_argument("--preset", choices=["realtime", "snappy", "balanced", "accurate"], default="realtime")
    parser.add_argument("--model-cache-dir", default="")
    parser.add_argument("--step-seconds", type=float, default=0.12)
    parser.add_argument("--commit-ratio", type=float, default=0.45)
    parser.add_argument("--min-buffer-seconds", type=float, default=0.18)
    parser.add_argument("--silence-threshold", type=float, default=0.0035)
    parser.add_argument("--stabilize-seconds", type=float, default=0.34)
    parser.add_argument("--fast-window-seconds", type=float, default=2.4)
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
    args.step_seconds = preset["step_seconds"]
    args.stabilize_seconds = preset["stabilize_seconds"]
    args.commit_ratio = preset["commit_ratio"]
    args.fast_window_seconds = preset["fast_window_seconds"]
    args.min_buffer_seconds = preset["min_buffer_seconds"]
    args.silence_threshold = preset["silence_threshold"]
    return args


def write_state(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = path.with_suffix(".tmp")
    temp_path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
    temp_path.replace(path)


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


def pcm_to_float(pcm_bytes: bytes) -> np.ndarray:
    return np.frombuffer(pcm_bytes, dtype=np.int16).astype(np.float32) / 32768.0


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

    base_lower = base.lower()
    next_lower = nxt.lower()
    if base_lower == next_lower or base_lower.endswith(next_lower):
        return base
    if base_lower in next_lower:
        return nxt

    base_words = normalized_words(base)
    next_words = normalized_words(nxt)
    max_overlap = min(len(base_words), len(next_words), 16)

    for overlap in range(max_overlap, 0, -1):
        base_slice = " ".join(base_words[-overlap:]).lower()
        next_slice = " ".join(next_words[:overlap]).lower()
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


def translate_text(text: str, target_language: str) -> str:
    if not text:
        return ""
    try:
        result = subprocess.run(
            ["trans", "-brief", f":{target_language}", text],
            capture_output=True, text=True, timeout=10, check=True,
        )
    except Exception:
        return ""
    return normalize_text(result.stdout or result.stderr)


def set_status(path: Path, state: dict, status: str, message: str, *, backend_ready: bool = True) -> None:
    state.update({"status": status, "message": message, "backend_ready": backend_ready})
    write_state(path, state)


def is_cuda_runtime_error(error: Exception) -> bool:
    text = str(error or "").lower()
    return (
        "libcublas" in text
        or "cuda failed" in text
        or "no cuda-capable device" in text
        or "cannot be loaded" in text and "cuda" in text
    )


class CaptionRuntimeFallback(RuntimeError):
    pass


def model_is_complete(path: Path) -> bool:
    return path.joinpath("model.bin").is_file()


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
    def __init__(self):
        self._lock = threading.Lock()
        self._wake_event = threading.Event()
        self._stop_event = threading.Event()
        self._pending: tuple[str, str, str] | None = None
        self._current: tuple[str, str, str] | None = None
        self._cache: dict[tuple[str, str], str] = {}
        self._latest_by_target: dict[str, tuple[str, str]] = {}
        self._thread = threading.Thread(target=self._run, name="live-captions-translator", daemon=True)
        self._thread.start()

    def request(self, text: str, target_language: str, source_language: str = "") -> str:
        normalized_text = normalize_text(text)
        source_code = source_language.split("-")[0].lower()

        if not normalized_text:
            return ""
        if source_code and source_code == target_language:
            return normalized_text

        cache_key = (normalized_text, target_language)
        with self._lock:
            if cache_key in self._cache:
                return self._cache[cache_key]

            latest = self._latest_by_target.get(target_language)
            pending_key = self._pending[:2] if self._pending else None
            if pending_key != cache_key:
                self._pending = (normalized_text, target_language, source_language)
                self._wake_event.set()

            if latest is not None:
                latest_source, latest_translation = latest
                if latest_translation and self._is_reusable_translation(latest_source, normalized_text):
                    return latest_translation
        return ""

    @staticmethod
    def _is_reusable_translation(previous_source: str, next_source: str) -> bool:
        previous_words = normalized_words(previous_source)
        next_words = normalized_words(next_source)
        if not previous_words or not next_words:
            return False

        shared_prefix = 0
        for previous_word, next_word in zip(previous_words, next_words):
            if comparable_word(previous_word) != comparable_word(next_word):
                break
            shared_prefix += 1

        min_words = min(len(previous_words), len(next_words))
        return (
            shared_prefix >= 4
            or (min_words > 0 and shared_prefix / min_words >= 0.72)
        )

    def stop(self) -> None:
        self._stop_event.set()
        self._wake_event.set()
        self._thread.join(timeout=1.0)

    def _run(self) -> None:
        while not self._stop_event.is_set():
            self._wake_event.wait(timeout=0.1)
            self._wake_event.clear()

            while True:
                with self._lock:
                    task = self._pending
                    self._pending = None

                if task is None:
                    break

                self._current = task
                text, target_language, _source_language = task
                translated = translate_text(text, target_language)
                cache_key = (text, target_language)

                with self._lock:
                    self._cache[cache_key] = translated
                    if translated:
                        self._latest_by_target[target_language] = (text, translated)

                if self._stop_event.is_set():
                    break


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
        if partial and self.committed_segments:
            partial = strip_committed_overlap(self.committed_segments[-1], partial)
            partial = clean_transcript_text(partial)
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

        if self.committed_segments:
            previous = self.committed_segments[-1]
            previous_words = normalized_words(previous)
            segment_words = normalized_words(segment)

            if normalize_text(previous).lower() == normalize_text(segment).lower():
                return

            if len(previous_words) <= 2 or len(segment_words) <= 2:
                merged = merge_continuous_text(previous, segment)
                cleaned = clean_transcript_text(merged)
                if cleaned:
                    self.committed_segments[-1] = cleaned
                    return

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
        self.committed_words: list[str] = []
        self.source_language = ""
        self.last_partial = ""
        self.pending_partial = ""
        self.pending_partial_count = 0
        self.runtime_device = "cpu"

    def feed(self, chunk: np.ndarray) -> None:
        self.audio_buffer = np.concatenate([self.audio_buffer, chunk])
        if len(self.audio_buffer) > self.MAX_BUFFER_SAMPLES:
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
            return ""

    def stabilize(self) -> str:
        audio = self.audio_buffer
        if not self._audio_usable(audio):
            return self._committed_tail()

        buf_dur = len(audio) / SAMPLE_RATE
        threshold = buf_dur * self.commit_ratio

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
            return self._committed_tail()

        if not words:
            return self._committed_tail()

        to_commit = [(s, e, w) for s, e, w in words if e <= threshold]

        if to_commit:
            last_end = to_commit[-1][1]
            self._append_committed_words([w for _, _, w in to_commit])
            trim_secs = max(0.0, last_end - 0.45)
            trim_samples = int(trim_secs * SAMPLE_RATE)
            if trim_samples > 0:
                self.audio_buffer = self.audio_buffer[trim_samples:]
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
        self.committed_words = normalized_words(committed_text)

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
        if not candidate:
            return False

        committed_context = " ".join(self.committed_words[-12:])
        if committed_context:
            candidate = strip_committed_overlap(committed_context, candidate)
            candidate = clean_transcript_text(candidate)

        candidate_words = normalized_words(candidate)
        if len(candidate_words) < 2:
            return False

        self._append_committed_words(candidate_words)
        self.audio_buffer = np.zeros(0, dtype=np.float32)
        self.last_partial = ""
        self.pending_partial = ""
        self.pending_partial_count = 0
        return True

    def reset(self) -> None:
        self.audio_buffer = np.zeros(0, dtype=np.float32)
        self.committed_words = []
        self.source_language = ""


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

    capture_proc = start_audio_capture(pulse_device)
    translator = AsyncTranslator()
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
            if capture_proc.poll() is not None:
                print("Audio capture process exited unexpectedly.", file=sys.stderr)
                state.update({"status": "error", "message": "Audio capture process exited unexpectedly."})
                write_state(state_path, state)
                return 4

            chunk = capture_proc.stdout.read(4096)
            if not chunk:
                time.sleep(0.01)
                continue

            transcriber.feed(chunk)
            display_text, stable_text, unstable_text = transcriber.texts()
            speech_active = transcriber.speech_active()
            committed_count = transcriber.committed_word_count()

            translated_text = last_translated_text if args.display_mode != "captions" else ""
            translated_stable_text = last_translated_stable_text if args.display_mode != "captions" else ""
            translated_unstable_text = last_translated_unstable_text if args.display_mode != "captions" else ""
            if args.display_mode != "captions":
                if stable_text:
                    requested_stable_translation = translator.request(
                        stable_text,
                        args.target_language,
                        transcriber.source_language,
                    )
                    if requested_stable_translation:
                        translated_stable_text = requested_stable_translation
                else:
                    translated_stable_text = ""

                if display_text:
                    requested_translation = translator.request(
                        display_text,
                        args.target_language,
                        transcriber.source_language,
                    )
                    if requested_translation:
                        translated_text = requested_translation
                else:
                    translated_text = ""

                if translated_text and normalize_text(translated_text) != normalize_text(translated_stable_text):
                    translated_unstable_text = translated_text
                else:
                    translated_unstable_text = ""

            if (
                display_text == last_display_text
                and translated_text == last_translated_text
                and translated_stable_text == last_translated_stable_text
                and translated_unstable_text == last_translated_unstable_text
                and committed_count == last_committed_count
            ):
                continue

            last_display_text = display_text
            last_translated_text = translated_text
            last_translated_stable_text = translated_stable_text
            last_translated_unstable_text = translated_unstable_text
            last_committed_count = committed_count

            state.update({
                "status": "running",
                "message": language_message or "Listening to audio…",
                "current_text": display_text,
                "stable_text": stable_text,
                "unstable_text": unstable_text,
                "translated_text": translated_text,
                "translated_stable_text": translated_stable_text,
                "translated_unstable_text": translated_unstable_text,
                "source_language": transcriber.source_language,
                "target_language": args.target_language,
                "history": [],
                "speech_active": speech_active,
                "runtime_device": transcriber.runtime_device,
                "backend_ready": True,
            })
            write_state(state_path, state)
    finally:
        translator.stop()
        capture_proc.terminate()
        try:
            capture_proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            capture_proc.kill()

    state.update({"status": "stopped", "message": "Live captions stopped."})
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

    capture_proc = start_audio_capture(pulse_device)
    transcriber = StreamingTranscriber(
        model,
        args.language,
        args.commit_ratio,
        args.min_buffer_seconds,
        args.silence_threshold,
        args.fast_window_seconds,
    )
    transcriber.runtime_device = runtime_device
    translator = AsyncTranslator()
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
            if capture_proc.poll() is not None:
                print("Audio capture process exited unexpectedly.", file=sys.stderr)
                state.update({"status": "error", "message": "Audio capture process exited unexpectedly."})
                write_state(state_path, state)
                return 4

            chunk = capture_proc.stdout.read(1024)
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
                    if transcriber.commit_partial_phrase(current_partial or transcriber.last_partial):
                        committed_tail = transcriber._committed_tail()
                    phrase_closed_for_silence = True
                current_partial = ""

            committed_count = len(transcriber.committed_words)

            _stable_preview, unstable_text = split_display_text(transcriber.committed_words, current_partial)
            stable_text = " ".join(transcriber.committed_words)
            display_text = merge_continuous_text(stable_text, unstable_text)

            translated_text = last_translated_text if args.display_mode != "captions" else ""
            translated_stable_text = last_translated_stable_text if args.display_mode != "captions" else ""
            translated_unstable_text = last_translated_unstable_text if args.display_mode != "captions" else ""
            if args.display_mode != "captions":
                if stable_text:
                    requested_stable_translation = translator.request(
                        stable_text,
                        args.target_language,
                        transcriber.source_language,
                    )
                    if requested_stable_translation:
                        translated_stable_text = requested_stable_translation
                else:
                    translated_stable_text = ""

                if display_text:
                    requested_translation = translator.request(
                        display_text,
                        args.target_language,
                        transcriber.source_language,
                    )
                    if requested_translation:
                        translated_text = requested_translation
                else:
                    translated_text = ""

                if translated_text and normalize_text(translated_text) != normalize_text(translated_stable_text):
                    translated_unstable_text = translated_text
                else:
                    translated_unstable_text = ""

            if (
                display_text == last_display_text
                and translated_text == last_translated_text
                and translated_stable_text == last_translated_stable_text
                and translated_unstable_text == last_translated_unstable_text
                and committed_count == last_committed_count
            ):
                continue

            last_display_text = display_text
            last_translated_text = translated_text
            last_translated_stable_text = translated_stable_text
            last_translated_unstable_text = translated_unstable_text
            last_committed_count = committed_count

            state.update({
                "status": "running",
                "message": "Listening to audio…",
                "current_text": display_text,
                "stable_text": stable_text,
                "unstable_text": unstable_text,
                "translated_text": translated_text,
                "translated_stable_text": translated_stable_text,
                "translated_unstable_text": translated_unstable_text,
                "source_language": transcriber.source_language,
                "target_language": args.target_language,
                "history": [],
                "speech_active": speech_active,
                "runtime_device": transcriber.runtime_device,
                "backend_ready": True,
            })
            write_state(state_path, state)
    finally:
        translator.stop()
        capture_proc.terminate()
        try:
            capture_proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            capture_proc.kill()

    state.update({"status": "stopped", "message": "Live captions stopped."})
    write_state(state_path, state)
    return 0


if __name__ == "__main__":
    sys.exit(main())
