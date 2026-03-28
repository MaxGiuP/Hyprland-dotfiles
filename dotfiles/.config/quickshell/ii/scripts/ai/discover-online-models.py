#!/usr/bin/env python3
import json
import os
import urllib.request
import urllib.error


def fetch_json(url, headers=None, timeout=6):
    req = urllib.request.Request(url, headers=headers or {})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read().decode("utf-8", errors="replace")
        return json.loads(raw)


def add_gemini(models, errors):
    api_key = (os.environ.get("GEMINI_API_KEY") or "").strip()
    if not api_key:
        return
    url = f"https://generativelanguage.googleapis.com/v1beta/models?key={api_key}"
    try:
        payload = fetch_json(url)
        for item in payload.get("models", []):
            name = item.get("name", "")
            if not name.startswith("models/"):
                continue
            model_id = name.split("/", 1)[1]
            methods = item.get("supportedGenerationMethods", []) or []
            if "generateContent" not in methods:
                continue
            models.append(
                {
                    "provider": "gemini",
                    "id": model_id,
                    "display_name": item.get("displayName") or model_id,
                    "description": item.get("description") or "",
                    "endpoint": f"https://generativelanguage.googleapis.com/v1beta/models/{model_id}:streamGenerateContent",
                    "api_format": "gemini",
                    "icon": "google-gemini-symbolic",
                    "requires_key": True,
                    "key_id": "gemini",
                    "homepage": "https://aistudio.google.com",
                }
            )
    except Exception as exc:
        errors.append(f"gemini: {exc}")


def add_openrouter(models, errors):
    headers = {}
    api_key = (os.environ.get("OPENROUTER_API_KEY") or "").strip()
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    try:
        payload = fetch_json("https://openrouter.ai/api/v1/models", headers=headers)
        for item in payload.get("data", [])[:120]:
            model_id = (item.get("id") or "").strip()
            if not model_id:
                continue
            models.append(
                {
                    "provider": "openrouter",
                    "id": model_id,
                    "display_name": item.get("name") or model_id,
                    "description": "",
                    "endpoint": "https://openrouter.ai/api/v1/chat/completions",
                    "api_format": "openai",
                    "icon": "language-symbolic",
                    "requires_key": True,
                    "key_id": "openrouter",
                    "homepage": "https://openrouter.ai",
                }
            )
    except Exception as exc:
        errors.append(f"openrouter: {exc}")


def add_mistral(models, errors):
    api_key = (os.environ.get("MISTRAL_API_KEY") or "").strip()
    if not api_key:
        return
    try:
        payload = fetch_json(
            "https://api.mistral.ai/v1/models",
            headers={"Authorization": f"Bearer {api_key}"},
        )
        for item in payload.get("data", []):
            model_id = (item.get("id") or "").strip()
            if not model_id:
                continue
            models.append(
                {
                    "provider": "mistral",
                    "id": model_id,
                    "display_name": model_id,
                    "description": "",
                    "endpoint": "https://api.mistral.ai/v1/chat/completions",
                    "api_format": "mistral",
                    "icon": "mistral-symbolic",
                    "requires_key": True,
                    "key_id": "mistral",
                    "homepage": "https://console.mistral.ai",
                }
            )
    except Exception as exc:
        errors.append(f"mistral: {exc}")


def main():
    models = []
    errors = []
    add_gemini(models, errors)
    add_openrouter(models, errors)
    add_mistral(models, errors)
    print(json.dumps({"models": models, "errors": errors}))


if __name__ == "__main__":
    main()
