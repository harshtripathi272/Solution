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


from pipeline.processing.unified_extractor import gemini_extractor

async def generate_explanation(event, payload: dict) -> str:
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

    try:
        text = await gemini_extractor.generate_simple_text(
            prompt=prompt,
            system_instruction="You are an expert humanitarian dispatcher generating brief operational sit-reps."
        )
        return text or fallback_explanation(event, payload)
    except Exception as exc:
        logger.warning("[Explainer] Hub call failed: %s", exc)
        return fallback_explanation(event, payload)
