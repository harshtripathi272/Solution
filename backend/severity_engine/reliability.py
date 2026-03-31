from __future__ import annotations

from severity_engine.constants import DEFAULT_SOURCE_RELIABILITY, SOURCE_RELIABILITY
from severity_engine.utils import clamp01, safe_float


def resolve_source_reliability(source: str) -> float:
    raw = (source or "").upper().strip()
    for prefix, score in SOURCE_RELIABILITY.items():
        if raw.startswith(prefix):
            return score
    return DEFAULT_SOURCE_RELIABILITY


def detection_confidence(event) -> float:
    # NER confidence comes from event.confidence_score and geocoding precision is
    # persisted in metadata during unified geocoding stage.
    base = safe_float(getattr(event, "confidence_score", 0.5), default=0.5)
    metadata = getattr(event, "metadata", {}) or {}
    geo_precision = safe_float(metadata.get("geocode_confidence", 1.0), default=1.0)
    return clamp01(base * geo_precision)


def reliability_score(event) -> tuple[float, float, float]:
    source_rel = resolve_source_reliability(getattr(event, "source", ""))
    detect_conf = detection_confidence(event)
    return clamp01(source_rel * detect_conf), source_rel, detect_conf
