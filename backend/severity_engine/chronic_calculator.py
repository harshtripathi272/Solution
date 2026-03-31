from __future__ import annotations

import math
from datetime import datetime, timezone

from severity_engine.constants import CHRONIC_DECAY_LAMBDA
from severity_engine.utils import clamp01, safe_float


def _infrastructure_gap_score(event) -> float:
    metadata = getattr(event, "metadata", {}) or {}
    gaps = metadata.get("infrastructure_gaps", []) or []
    text = (getattr(event, "description", "") or "").lower()

    if "no handpump" in text:
        return 0.75
    if "broken handpump" in text:
        return 0.50
    if "functional but crowded" in text:
        return 0.25

    if isinstance(gaps, list):
        scores = []
        for gap in gaps:
            if not isinstance(gap, dict):
                continue
            status = str(gap.get("status", "")).lower()
            if "no" in status:
                scores.append(0.75)
            elif "broken" in status:
                scores.append(0.5)
            elif "crowded" in status:
                scores.append(0.25)
        if scores:
            return clamp01(sum(scores) / len(scores))
    return 0.2


def _vulnerability_score(event) -> float:
    metadata = getattr(event, "metadata", {}) or {}
    groups = metadata.get("vulnerable_groups", []) or []
    text = (getattr(event, "description", "") or "").lower()

    score = 0.0
    if isinstance(groups, list):
        mapped = {str(g).lower() for g in groups}
        if {"elderly", "children", "disabled"}.intersection(mapped):
            score += 0.6
        score += min(0.4, 0.1 * len(mapped))

    for token in ("elderly", "children", "disabled", "pregnant"):
        if token in text:
            score += 0.15

    return clamp01(score)


def _historical_recurrence_score(event) -> float:
    metadata = getattr(event, "metadata", {}) or {}
    freq = safe_float(metadata.get("historical_crisis_frequency"), 0.0)
    # Allow either raw count or already normalized value.
    if freq > 1.0:
        return clamp01(freq / 12.0)
    return clamp01(freq)


def _baseline_score(event) -> float:
    infra = _infrastructure_gap_score(event)
    vuln = _vulnerability_score(event)
    recur = _historical_recurrence_score(event)
    return clamp01((0.45 * infra) + (0.35 * vuln) + (0.20 * recur))


def _days_since_report(event) -> float:
    now = datetime.now(timezone.utc)

    doc_meta = getattr(event, "document_metadata", None)
    publication_date = getattr(doc_meta, "publication_date", None)
    if publication_date is None:
        publication_date = getattr(event, "timestamp", now)

    if publication_date.tzinfo is None:
        publication_date = publication_date.replace(tzinfo=timezone.utc)

    days = (now - publication_date).total_seconds() / 86400.0
    return max(0.0, days)


def _validation_boost(event) -> float:
    metadata = getattr(event, "metadata", {}) or {}
    confirmed = bool(metadata.get("realtime_validation_confirmed", False))
    return 1.2 if confirmed else 1.0


def calculate_chronic_severity(event) -> float:
    baseline = _baseline_score(event)
    days_since_report = _days_since_report(event)
    decay = math.exp(-CHRONIC_DECAY_LAMBDA * days_since_report)
    boost = _validation_boost(event)
    return clamp01(baseline * decay * boost)
