#!/usr/bin/env python3
import html
import json
import os
import re
import urllib.request
from html.parser import HTMLParser


USER_AGENT = "quickshell-model-discovery/1.0"
SIZE_TOKEN_RE = re.compile(r"\b(?:\d+(?:\.\d+)?b|e\d+b)\b", re.IGNORECASE)
RELEVANT_OLLAMA_INSTALLS = {
    "deepseek-r1": {
        "install_id": "deepseek-r1:8b",
        "reason": "Reasoning-heavy local model that still fits on stronger desktop hardware.",
        "use_cases": ["reasoning", "analysis"],
        "hardware_hint": "Best on mid/high-end GPUs",
    },
    "devstral-small-2": {
        "install_id": "devstral-small-2:24b",
        "reason": "Focused on software engineering agents and codebase tasks.",
        "use_cases": ["coding", "agents"],
        "hardware_hint": "Needs stronger desktop hardware",
    },
    "gemma4": {
        "install_id": "gemma4:e4b",
        "reason": "Efficient recent Google-family open model for local chat and light coding.",
        "use_cases": ["chat", "lightweight"],
        "hardware_hint": "Easy local footprint",
    },
    "glm-4.7-flash": {
        "install_id": "glm-4.7-flash",
        "reason": "Recent lightweight coding and reasoning model.",
        "use_cases": ["lightweight", "coding", "reasoning"],
        "hardware_hint": "Easy local footprint",
    },
    "gpt-oss": {
        "install_id": "gpt-oss:20b",
        "reason": "OpenAI's open-weight reasoning model line on Ollama.",
        "use_cases": ["reasoning", "coding", "agents"],
        "hardware_hint": "Best on stronger desktop GPUs",
    },
    "lfm2": {
        "install_id": "lfm2",
        "reason": "Hybrid on-device model family with strong local efficiency.",
        "use_cases": ["chat", "lightweight"],
        "hardware_hint": "Easy local footprint",
    },
    "lfm2.5-thinking": {
        "install_id": "lfm2.5-thinking",
        "reason": "Recent local reasoning-focused hybrid model.",
        "use_cases": ["reasoning", "analysis"],
        "hardware_hint": "Moderate local footprint",
    },
    "nemotron-cascade-2": {
        "install_id": "nemotron-cascade-2",
        "reason": "Newer NVIDIA open model with agentic and reasoning capabilities.",
        "use_cases": ["agents", "reasoning", "coding"],
        "hardware_hint": "Needs stronger desktop hardware",
    },
    "qwen3": {
        "install_id": "qwen3:8b",
        "reason": "Balanced modern local model for chat, coding, and reasoning.",
        "use_cases": ["chat", "coding", "reasoning"],
        "hardware_hint": "Good general local size",
    },
    "qwen3-coder": {
        "install_id": "qwen3-coder:30b",
        "reason": "Strong coding-focused model family for local development.",
        "use_cases": ["coding", "agents"],
        "hardware_hint": "Needs stronger desktop hardware",
    },
    "qwen3.5": {
        "install_id": "qwen3.5:4b",
        "reason": "Recent Qwen general-purpose local model line with smaller runnable sizes.",
        "use_cases": ["chat", "lightweight"],
        "hardware_hint": "Easy local footprint",
    },
}


def make_headers(headers=None):
    merged = {"User-Agent": USER_AGENT}
    if headers:
        merged.update(headers)
    return merged


def fetch_text(url, headers=None, timeout=8):
    req = urllib.request.Request(url, headers=make_headers(headers))
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read().decode("utf-8", errors="replace")


def fetch_json(url, headers=None, timeout=8):
    return json.loads(fetch_text(url, headers=headers, timeout=timeout))


class OllamaSearchParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.entries = []
        self._current_href = None
        self._parts = []

    def handle_starttag(self, tag, attrs):
        if tag != "a":
            return
        href = dict(attrs).get("href", "")
        if href.startswith("/library/"):
            self._current_href = href.split("/library/", 1)[1].strip("/")
            self._parts = []

    def handle_data(self, data):
        if self._current_href and data:
            self._parts.append(data)

    def handle_endtag(self, tag):
        if tag != "a" or not self._current_href:
            return
        text = normalize_spaces("".join(self._parts))
        if text:
            self.entries.append({"slug": self._current_href, "text": html.unescape(text)})
        self._current_href = None
        self._parts = []


class PlainTextParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []

    def handle_data(self, data):
        if data:
            self.parts.append(data)

    def text(self):
        return normalize_spaces(" ".join(self.parts))


def normalize_spaces(value):
    return " ".join(str(value or "").split()).strip()


def unique_strings(values):
    seen = set()
    result = []
    for value in values or []:
        text = normalize_spaces(value)
        if not text or text in seen:
            continue
        seen.add(text)
        result.append(text)
    return result


def fetch_ollama_storage_size(slug, install_id):
    parser = PlainTextParser()
    parser.feed(fetch_text(f"https://ollama.com/library/{slug}/tags"))
    plain_text = parser.text()

    model_candidates = [install_id, f"{install_id}:latest", f"{slug}:latest", slug]
    for candidate in unique_strings(model_candidates):
        match = re.search(
            rf"\b{re.escape(candidate)}\b.*?\b(\d+(?:\.\d+)?(?:MB|GB|TB))\b",
            plain_text,
            flags=re.IGNORECASE,
        )
        if match:
            return match.group(1).upper()

    return ""


def score_ollama_relevance(slug, text):
    lowered = text.lower()
    score = 0

    positive_terms = [
        "coding",
        "code",
        "agentic",
        "reasoning",
        "workflow",
        "productivity",
        "software engineering",
        "developer",
        "tool",
        "tools",
    ]
    negative_terms = [
        "embedding",
        "ocr",
        "translation",
        "translate",
        "speech",
        "audio generation",
    ]

    if slug in RELEVANT_OLLAMA_INSTALLS:
        score += 4
    score += sum(1 for term in positive_terms if term in lowered)
    score -= sum(2 for term in negative_terms if term in lowered)

    if any(prefix in slug for prefix in ("qwen", "gemma", "gpt-oss", "glm", "deepseek", "devstral", "nemotron", "lfm")):
        score += 1

    return score


def add_ollama_recommendations(suggestions, errors):
    seen_install_ids = set()

    def append_suggestion(slug, text, install_info=None):
        install_info = install_info or RELEVANT_OLLAMA_INSTALLS.get(slug, {})
        install_id = install_info.get("install_id") or slug
        if install_id in seen_install_ids:
            return

        storage_size = ""
        try:
            storage_size = fetch_ollama_storage_size(slug, install_id)
        except Exception:
            storage_size = ""

        lowered = text.lower()
        size_tokens = SIZE_TOKEN_RE.findall(lowered)
        display_name = slug
        if lowered.startswith(slug.lower() + " "):
            display_name = text[: len(slug)]
        description = text[len(display_name) :].strip() if lowered.startswith(display_name.lower()) else text
        updated_match = re.search(r"Updated\s+(.+?)$", text, flags=re.IGNORECASE)
        updated_label = updated_match.group(1).strip() if updated_match else ""

        suggestions.append(
            {
                "provider": "ollama",
                "id": slug,
                "display_name": display_name,
                "description": description,
                "homepage": f"https://ollama.com/library/{slug}",
                "install_id": install_id,
                "storage_size": storage_size,
                "updated_label": updated_label,
                "reason": install_info.get("reason", ""),
                "use_cases": install_info.get("use_cases", []),
                "hardware_hint": install_info.get("hardware_hint", ""),
                "size_tokens": unique_strings(token.upper() for token in size_tokens),
            }
        )
        seen_install_ids.add(install_id)

    try:
        parser = OllamaSearchParser()
        parser.feed(fetch_text("https://ollama.com/search"))

        seen = set()
        for entry in parser.entries:
            slug = entry["slug"]
            text = normalize_spaces(entry["text"])
            lowered = text.lower()
            if slug in seen:
                continue
            seen.add(slug)

            if score_ollama_relevance(slug, text) < 3:
                continue

            size_tokens = SIZE_TOKEN_RE.findall(lowered)
            cloud_only = (" cloud " in f" {lowered} ") and not size_tokens and slug not in RELEVANT_OLLAMA_INSTALLS
            if cloud_only:
                continue

            append_suggestion(slug, text)

            if len(suggestions) >= 8:
                break
    except Exception as exc:
        errors.append(f"ollama: {exc}")

    # Keep a curated catalog available even when live discovery fails or filters everything out.
    if len(suggestions) < 6:
        for slug, install_info in RELEVANT_OLLAMA_INSTALLS.items():
            text = f"{slug} {install_info.get('reason', '')}".strip()
            append_suggestion(slug, text, install_info)
            if len(suggestions) >= 8:
                break


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
    ollama_recommendations = []
    errors = []
    add_gemini(models, errors)
    add_openrouter(models, errors)
    add_mistral(models, errors)
    add_ollama_recommendations(ollama_recommendations, errors)
    print(
        json.dumps(
            {
                "models": models,
                "ollama_recommendations": ollama_recommendations,
                "errors": errors,
            }
        )
    )


if __name__ == "__main__":
    main()
