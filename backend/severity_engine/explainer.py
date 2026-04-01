from __future__ import annotations

import os
from datetime import datetime, timezone

import httpx


def fallback_explanation(event, payload: dict) -> str:
    loc = ((getattr(event, "metadata", {}) or {}).get("resolved_address") or getattr(event, "geohash", "unknown"))
    source = getattr(event, "source", "Unknown source")
    families = int(max(0, getattr(event, "population_affected", 0) // 5)) if getattr(event, "population_affected", 0) else 0
    cls = payload.get("classification", "Moderate")
    score = payload.get("composite_urgency", 0.0)
    response = payload.get("recommended_response_time", "48h")

    return (
        f"Severity {score:.2f} ({cls}) for {loc}: "
        f"Based on {source} signal with confidence-adjusted reliability {payload.get('reliability_score', 0.0):.2f}. "
        f"Estimated affected families: {families}. "
        f"Recommended response window: {response}."
    )


async def generate_explanation(event, payload: dict) -> str:
    api_key = os.getenv("GEMINI_API_KEY", "").strip()
    model = os.getenv("GEMINI_FLASH_MODEL", "gemini-2.0-flash")

    if not api_key:
        return fallback_explanation(event, payload)

    prompt = (
        "Generate a short operational explanation for volunteer dispatch. "
        "Keep it under 65 words. Mention score, class, location, source evidence, and response time.\n"
        f"event_id={getattr(event, 'id', '')}\n"
        f"location={((getattr(event, 'metadata', {}) or {}).get('resolved_address') or getattr(event, 'geohash', 'unknown'))}\n"
        f"source={getattr(event, 'source', '')}\n"
        f"classification={payload.get('classification')}\n"
        f"composite_urgency={payload.get('composite_urgency')}\n"
        f"acute={payload.get('severity_acute')} chronic={payload.get('severity_chronic')}\n"
        f"response_time={payload.get('recommended_response_time')}\n"
        f"description={(getattr(event, 'description', '') or '')[:280]}\n"
        f"timestamp={datetime.now(timezone.utc).isoformat()}"
    )

    endpoint = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
    request_body = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {
            "temperature": 0.2,
            "maxOutputTokens": 150,
        },
    }

    try:
        async with httpx.AsyncClient(timeout=4.0) as client:
            response = await client.post(
                f"{endpoint}?key={api_key}",
                json=request_body,
            )
            response.raise_for_status()
            data = response.json()
            candidates = data.get("candidates", [])
            if not candidates:
                return fallback_explanation(event, payload)
            parts = (((candidates[0] or {}).get("content") or {}).get("parts") or [])
            if not parts:
                return fallback_explanation(event, payload)
            text = (parts[0] or {}).get("text", "").strip()
            return text or fallback_explanation(event, payload)
    except Exception:
        return fallback_explanation(event, payload)
