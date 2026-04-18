#!/usr/bin/env bash
set -euo pipefail

STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
BASE_DIR="${STATE_HOME}/quickshell/user/live-captions"
VENV_DIR="${BASE_DIR}/venv"
MODELS_DIR="${BASE_DIR}/models"
PREFETCH_MODELS=("tiny" "base")
GPU_RUNTIME_PACKAGES=(
  "nvidia-cublas-cu12"
  "nvidia-cudnn-cu12"
)
VOSK_MODEL_URLS=(
  "en|https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip|vosk-model-small-en-us-0.15"
  "de|https://alphacephei.com/vosk/models/vosk-model-small-de-0.15.zip|vosk-model-small-de-0.15"
  "it|https://alphacephei.com/vosk/models/vosk-model-small-it-0.22.zip|vosk-model-small-it-0.22"
)

mkdir -p "${BASE_DIR}"
mkdir -p "${MODELS_DIR}"
export MODELS_DIR
export PREFETCH_MODELS_STR="${PREFETCH_MODELS[*]}"
export VOSK_MODEL_URLS_STR="$(printf '%s\n' "${VOSK_MODEL_URLS[@]}")"

python3 -m venv "${VENV_DIR}"
"${VENV_DIR}/bin/pip" install --upgrade pip setuptools wheel
"${VENV_DIR}/bin/pip" install faster-whisper vosk "${GPU_RUNTIME_PACKAGES[@]}"
"${VENV_DIR}/bin/python" - <<'PY'
from faster_whisper.utils import download_model
from pathlib import Path
import os

models_dir = Path(os.environ["MODELS_DIR"])
for model_name in os.environ["PREFETCH_MODELS_STR"].split():
    model_dir = models_dir / model_name
    model_dir.mkdir(parents=True, exist_ok=True)
    resolved = Path(download_model(model_name, output_dir=str(model_dir), cache_dir=str(model_dir)))
    print(f"Prefetched Whisper {model_name} model at {resolved}.")
PY

"${VENV_DIR}/bin/python" - <<'PY'
from pathlib import Path
import sys

site_packages_candidates = sorted(
    Path(sys.prefix, "lib").glob("python*/site-packages")
)
if not site_packages_candidates:
    raise SystemExit("Could not locate the live captions site-packages directory.")

site_packages = site_packages_candidates[0]
cuda_lib_dirs = sorted(
    path for path in site_packages.glob("nvidia/*/lib")
    if path.is_dir()
)

if not cuda_lib_dirs:
    raise SystemExit("Installed NVIDIA Python runtime packages but no CUDA library directories were found.")

print("CUDA runtime library paths:")
for path in cuda_lib_dirs:
    print(path)
PY

"${VENV_DIR}/bin/python" - <<'PY'
from pathlib import Path
from urllib.request import urlretrieve
import os
import shutil
import tempfile
import zipfile

models_dir = Path(os.environ["MODELS_DIR"]) / "vosk"
models_dir.mkdir(parents=True, exist_ok=True)

for spec in os.environ.get("VOSK_MODEL_URLS_STR", "").splitlines():
    if not spec.strip():
        continue
    lang, url, extracted_name = spec.split("|", 2)
    target_dir = models_dir / lang
    if target_dir.joinpath("am").exists():
        print(f"Vosk {lang} model already present at {target_dir}.")
        continue

    with tempfile.TemporaryDirectory(prefix=f"vosk-{lang}-") as tmpdir:
        archive_path = Path(tmpdir) / "model.zip"
        print(f"Downloading Vosk {lang} model from {url} ...")
        urlretrieve(url, archive_path)

        extract_root = Path(tmpdir) / "extract"
        extract_root.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(archive_path) as zf:
            zf.extractall(extract_root)

        extracted_dir = extract_root / extracted_name
        if not extracted_dir.exists():
            candidates = [p for p in extract_root.iterdir() if p.is_dir()]
            if len(candidates) == 1:
                extracted_dir = candidates[0]
            else:
                raise SystemExit(f"Could not locate extracted Vosk model directory for {lang}.")

        shutil.rmtree(target_dir, ignore_errors=True)
        shutil.move(str(extracted_dir), str(target_dir))
        print(f"Installed Vosk {lang} model at {target_dir}.")
PY

printf '\nLive captions backend installed in %s\n' "${VENV_DIR}"
