import json
import logging
import os
import re
from typing import Any, Optional

import httpx

logger = logging.getLogger("expense_tracker_server")

OLLAMA_URL = os.getenv("OLLAMA_URL", "http://127.0.0.1:11434")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "qwen3:8b")
OPENROUTER_API_KEY = os.getenv("OPENROUTER_API_KEY", "").strip()
OPENROUTER_MODEL = os.getenv("OPENROUTER_MODEL", "openrouter/free").strip()
ENRICHMENT_SOFT_TIMEOUT = float(os.getenv("ENRICHMENT_SOFT_TIMEOUT", "60"))
ENRICHMENT_HARD_TIMEOUT = float(os.getenv("ENRICHMENT_HARD_TIMEOUT", "300"))

# Back-compat aliases
OLLAMA_SOFT_TIMEOUT = ENRICHMENT_SOFT_TIMEOUT
OLLAMA_HARD_TIMEOUT = ENRICHMENT_HARD_TIMEOUT

# Tokenizer artifacts leaked by some LLM models (e.g. <pad>, <|pad|>).
_PIPE_SPECIAL_TOKEN_RE = re.compile(r"<\|[^|>]+\|>", re.IGNORECASE)
_ANGLE_SPECIAL_TOKEN_RE = re.compile(
    r"</?(?:pad|s|unk|bos|eos|im_start|im_end)\b[^>]*>",
    re.IGNORECASE,
)


def strip_tokenizer_artifacts(text: str) -> str:
    """Remove special tokens from raw LLM output (including inside JSON syntax)."""
    text = _PIPE_SPECIAL_TOKEN_RE.sub("", text)
    text = _ANGLE_SPECIAL_TOKEN_RE.sub("", text)
    return text


def sanitize_llm_string(value: str) -> str:
    text = strip_tokenizer_artifacts(value)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def sanitize_llm_value(value: Any) -> Any:
    if isinstance(value, str):
        return sanitize_llm_string(value)
    if isinstance(value, list):
        return [sanitize_llm_value(item) for item in value]
    if isinstance(value, dict):
        return {key: sanitize_llm_value(item) for key, item in value.items()}
    return value


def is_free_openrouter_model(model: str) -> bool:
    return model == "openrouter/free" or model.endswith(":free")


def openrouter_client_config() -> dict:
    """Shared OpenRouter credentials for tailnet clients (not used server-side)."""
    configured = bool(OPENROUTER_API_KEY) and is_free_openrouter_model(OPENROUTER_MODEL)
    return {
        "configured": configured,
        "openrouter_api_key": OPENROUTER_API_KEY if configured else None,
        "openrouter_model": OPENROUTER_MODEL,
    }


def enrichment_health() -> dict:
    info = {
        "status": "ok",
        "enrichment_provider": "ollama",
        "ollama_url": OLLAMA_URL,
        "ollama_model": OLLAMA_MODEL,
        "openrouter_client_configured": openrouter_client_config()["configured"],
    }
    return info


def _parse_json_content(message_content: str) -> dict:
    content = message_content.strip()
    if content.startswith("```"):
        lines = content.splitlines()
        if len(lines) >= 3:
            content = "\n".join(lines[1:-1])
    content = strip_tokenizer_artifacts(content)
    return sanitize_llm_value(json.loads(content))


def _request_timeout() -> httpx.Timeout:
    return httpx.Timeout(
        connect=10.0,
        read=ENRICHMENT_HARD_TIMEOUT,
        write=10.0,
        pool=10.0,
    )


async def call_llm(
    raw_input: str,
    system_prompt: str,
    *,
    think: Optional[bool] = None,
) -> dict:
    payload = {
        "model": OLLAMA_MODEL,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": raw_input},
        ],
        "format": "json",
        "stream": False,
        "options": {"temperature": 0.1},
    }
    if think is not None:
        payload["think"] = think

    async with httpx.AsyncClient(timeout=_request_timeout()) as client:
        think_note = f", think={think}" if think is not None else ""
        logger.info(
            f"Sending request to Ollama: {OLLAMA_URL}/api/chat "
            f"with model {OLLAMA_MODEL}{think_note}"
        )
        response = await client.post(f"{OLLAMA_URL}/api/chat", json=payload)

    if response.status_code != 200:
        raise RuntimeError(
            f"Ollama server returned status code {response.status_code}: {response.text}"
        )

    resp_data = response.json()
    message_content = resp_data.get("message", {}).get("content", "").strip()
    logger.info(f"Received response from Ollama: {message_content}")
    return _parse_json_content(message_content)
