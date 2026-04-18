#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import io
import json
import re
import signal
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

RUNNING = True


def handle_signal(signum, frame):
    global RUNNING
    RUNNING = False


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
    m = re.match(r"^([\d.]+),([\d.]+)\s+([\d.]+)x([\d.]+)$", cleaned)
    if not m:
        raise ValueError(
            f"Cannot parse region '{cleaned}' — expected 'X,Y WxH' from slurp. "
            "Try drawing the selection again."
        )
    x = int(round(float(m.group(1))))
    y = int(round(float(m.group(2))))
    w = max(1, int(round(float(m.group(3)))))
    h = max(1, int(round(float(m.group(4)))))
    return f"{x},{y} {w}x{h}"


def normalize_lines(text: str) -> str:
    lines = [" ".join(line.split()) for line in (text or "").splitlines()]
    return "\n".join(line for line in lines if line).strip()


def write_state(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = path.with_suffix(".tmp")
    temp_path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
    temp_path.replace(path)


def translate_text(text: str, target_language: str) -> str:
    if not text:
        return ""
    try:
        result = subprocess.run(
            ["trans", "-brief", f":{target_language}", text],
            capture_output=True,
            text=True,
            timeout=15,
            check=True,
        )
    except Exception:
        return ""
    return normalize_lines(result.stdout or result.stderr)


class AsyncTranslator:
    """Translates in a background thread so it never blocks the OCR loop."""

    def __init__(self, language: str) -> None:
        self._language = language
        self._lock = threading.Lock()
        self._result = ""
        self._active_text: str | None = None
        self._pending_text: str | None = None
        self._thread: threading.Thread | None = None

    def submit(self, text: str) -> None:
        """Queue text for translation. Returns immediately."""
        with self._lock:
            if text == self._active_text:
                return  # already translating this
            self._pending_text = text  # supersede any waiting job
        self._maybe_start()

    def reset(self) -> None:
        with self._lock:
            self._result = ""
            self._pending_text = None

    def result(self) -> str:
        with self._lock:
            return self._result

    def _maybe_start(self) -> None:
        with self._lock:
            if self._thread and self._thread.is_alive():
                return  # will pick up pending when current job finishes
            text = self._pending_text
            if not text:
                return
            self._pending_text = None
            self._active_text = text
        t = threading.Thread(target=self._run, args=(text,), daemon=True)
        self._thread = t
        t.start()

    def _run(self, text: str) -> None:
        translated = translate_text(text, self._language)
        with self._lock:
            if self._active_text == text:
                self._result = translated
                self._active_text = None
        self._maybe_start()  # pick up any pending job


def capture_region(region: str, image_path: Path) -> None:
    normalized = normalize_geometry(region)
    result = subprocess.run(
        ["grim", "-g", normalized, str(image_path)],
        capture_output=True,
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
        from PIL import Image, ImageEnhance, ImageFilter, ImageOps
        img = Image.open(image_path).convert("L")
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
    result = subprocess.run(
        ["tesseract", "stdin", "stdout", "-l", language,
         "--psm", "6", "--oem", "3", "tsv"],
        input=image_bytes,
        capture_output=True,
        timeout=12,
    )
    if result.returncode != 0:
        detail = (result.stderr or b"").decode(errors="replace").strip()
        raise RuntimeError(f"tesseract failed: {detail}" if detail else "tesseract: OCR failed")

    lines_dict: dict[tuple, list[tuple[int, str]]] = {}
    confidences: list[float] = []
    stdout_text = result.stdout.decode(errors="replace")
    reader = csv.DictReader(io.StringIO(stdout_text), delimiter="\t")
    for row in reader:
        try:
            conf = float(row.get("conf", -1))
        except (ValueError, TypeError):
            continue
        text = (row.get("text") or "").strip()
        if conf < 0 or not text:
            continue
        key = (int(row["block_num"]), int(row["par_num"]), int(row["line_num"]))
        lines_dict.setdefault(key, []).append((int(row["word_num"]), text))
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

    last_ocr_text = ""
    translator = AsyncTranslator(args.target_language)

    with tempfile.TemporaryDirectory(prefix="live-screen-translation-") as temp_dir:
        image_path = Path(temp_dir) / "capture.png"

        state.update({"status": "running", "message": "Reading selected screen area…"})
        write_state(state_path, state)

        while RUNNING:
            try:
                capture_region(args.region, image_path)
                image_bytes = preprocess_image(image_path)
                ocr_text, confidence = ocr_image(image_bytes, args.ocr_language)
            except (FileNotFoundError, ValueError) as error:
                state.update({"status": "error", "message": str(error)})
                write_state(state_path, state)
                return 2
            except Exception as error:
                state.update({
                    "status": "error",
                    "message": str(error),
                    "ocr_text": last_ocr_text,
                    "translated_text": translator.result(),
                })
                write_state(state_path, state)
                time.sleep(max(0.5, args.interval_seconds))
                continue

            # Skip low-confidence frames — keep last good result visible
            if confidence < args.confidence_threshold:
                time.sleep(max(0.35, args.interval_seconds))
                continue

            if ocr_text != last_ocr_text:
                last_ocr_text = ocr_text
                if ocr_text:
                    translator.submit(ocr_text)
                else:
                    translator.reset()

            state.update({
                "status": "running",
                "message": "Reading selected screen area…",
                "ocr_text": ocr_text,
                "translated_text": translator.result(),
                "target_language": args.target_language,
                "ocr_language": args.ocr_language,
                "region": args.region,
            })
            write_state(state_path, state)
            time.sleep(max(0.35, args.interval_seconds))

    state.update({"status": "stopped", "message": "Live screen translation stopped."})
    write_state(state_path, state)
    return 0


if __name__ == "__main__":
    sys.exit(main())
