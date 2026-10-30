"""AI providers. Both stream plain text chunks; errors raise AIError with a code the UI translates."""
import json
from typing import AsyncIterator

import httpx

from . import config

SYSTEM_PROMPT = (
    "You are the assistant inside a file and image analysis app. Answer in the same language the user writes in "
    "(Arabic or English), clearly and without filler.\n"
    "Important: file and image analysis is NOT enabled yet in this version of the app. You cannot see the contents of "
    "any attached file or image; you only see its name and type. If the user asks about an attachment's contents, say "
    "plainly that analysis of attachments is not available yet, and never guess or invent what it contains."
)


class AIError(Exception):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def provider_name() -> str:
    return "claude" if config.AI_PROVIDER == "claude" else "ollama"


def model_name() -> str:
    return config.CLAUDE_MODEL if provider_name() == "claude" else config.OLLAMA_MODEL


async def status() -> dict:
    provider = provider_name()
    info = {"provider": provider, "model": model_name(), "available": False, "reason": None}
    if provider == "claude":
        if not config.ANTHROPIC_API_KEY:
            info["reason"] = "missing_api_key"
        else:
            info["available"] = True
        return info
    try:
        async with httpx.AsyncClient(timeout=3) as client:
            resp = await client.get(f"{config.OLLAMA_URL}/api/tags")
            resp.raise_for_status()
            names = {m.get("name") for m in resp.json().get("models", [])}
    except (httpx.HTTPError, ValueError):
        info["reason"] = "ollama_not_running"
        return info
    wanted = config.OLLAMA_MODEL
    if wanted in names or f"{wanted}:latest" in names:
        info["available"] = True
    else:
        info["reason"] = "model_missing"
    return info


async def stream_reply(history: list[dict]) -> AsyncIterator[str]:
    """history: [{'role': 'user'|'assistant', 'content': str}], oldest first, ending with the user turn."""
    if provider_name() == "claude":
        async for chunk in _stream_claude(history):
            yield chunk
    else:
        async for chunk in _stream_ollama(history):
            yield chunk


async def _stream_ollama(history: list[dict]) -> AsyncIterator[str]:
    payload = {
        "model": config.OLLAMA_MODEL,
        "stream": True,
        "messages": [{"role": "system", "content": SYSTEM_PROMPT}, *history],
    }
    try:
        async with httpx.AsyncClient(timeout=httpx.Timeout(10, read=300)) as client:
            async with client.stream("POST", f"{config.OLLAMA_URL}/api/chat", json=payload) as resp:
                if resp.status_code == 404:
                    raise AIError("model_missing", f"Model '{config.OLLAMA_MODEL}' is not installed in Ollama.")
                if resp.status_code >= 400:
                    body = (await resp.aread()).decode("utf-8", "replace")[:300]
                    raise AIError("provider_error", f"Ollama returned HTTP {resp.status_code}: {body}")
                async for line in resp.aiter_lines():
                    if not line.strip():
                        continue
                    event = json.loads(line)
                    if event.get("error"):
                        raise AIError("provider_error", str(event["error"]))
                    text = (event.get("message") or {}).get("content", "")
                    if text:
                        yield text
                    if event.get("done"):
                        return
    except httpx.ConnectError as exc:
        raise AIError("ollama_not_running", "Could not connect to Ollama.") from exc
    except httpx.HTTPError as exc:
        raise AIError("provider_error", f"Connection to Ollama failed: {exc}") from exc


async def _stream_claude(history: list[dict]) -> AsyncIterator[str]:
    if not config.ANTHROPIC_API_KEY:
        raise AIError("missing_api_key", "ANTHROPIC_API_KEY is not set on the server.")
    import anthropic

    client = anthropic.AsyncAnthropic(api_key=config.ANTHROPIC_API_KEY)
    try:
        async with client.beta.messages.stream(
            model=config.CLAUDE_MODEL,
            max_tokens=16000,
            system=SYSTEM_PROMPT,
            messages=history,
            output_config={"effort": "medium"},
            betas=["server-side-fallback-2026-07-01"],
            fallbacks="default",
        ) as stream:
            async for text in stream.text_stream:
                yield text
            final = await stream.get_final_message()
            if final.stop_reason == "refusal":
                raise AIError("refused", "The model declined to answer this request.")
    except anthropic.AuthenticationError as exc:
        raise AIError("invalid_api_key", "The Anthropic API key was rejected.") from exc
    except anthropic.RateLimitError as exc:
        raise AIError("rate_limited", "Rate limit reached. Try again shortly.") from exc
    except anthropic.APIStatusError as exc:
        raise AIError("provider_error", f"Claude API error {exc.status_code}: {exc.message}") from exc
    except anthropic.APIConnectionError as exc:
        raise AIError("provider_error", "Could not reach the Claude API.") from exc
