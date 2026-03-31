from __future__ import annotations

from severity_engine.acute_calculator import calculate_acute_severity
from severity_engine.chronic_calculator import calculate_chronic_severity
from severity_engine.composite_aggregator import aggregate_composite_urgency, volunteer_gap_penalty
from severity_engine.constants import CLASSIFICATION_THRESHOLDS, RESPONSE_TIME_BY_CLASSIFICATION
from severity_engine.explainer import generate_explanation
from severity_engine.reliability import reliability_score
from severity_engine.temporal_tracker import temporal_tracker
from severity_engine.types import SeverityResult
from severity_engine.utils import clamp01


class SeverityEngine:
    async def calculate(self, event, nearby_volunteer_count: int = 0) -> SeverityResult:
        acute = calculate_acute_severity(event)
        acute = temporal_tracker.apply_acute_inactivity_decay(getattr(event, "timestamp"), acute)

        chronic = calculate_chronic_severity(event)

        key = temporal_tracker.key_for(event)
        temporal_tracker.record(key, getattr(event, "timestamp"), max(acute, chronic))
        trend_bonus = temporal_tracker.trend_bonus(key)

        gap_penalty = volunteer_gap_penalty(event, nearby_volunteer_count)
        composite = aggregate_composite_urgency(acute, chronic, trend_bonus, gap_penalty)

        feedback = (getattr(event, "metadata", {}) or {}).get("ground_truth_feedback")
        composite = temporal_tracker.apply_feedback_adjustment(composite, feedback)

        rel_score, source_rel, detect_conf = reliability_score(event)
        adjusted = clamp01(composite * rel_score)

        classification, color, action = _classify(adjusted)
        response_time = RESPONSE_TIME_BY_CLASSIFICATION.get(classification, "48h")

        payload = {
            "severity_acute": round(acute, 4),
            "severity_chronic": round(chronic, 4),
            "composite_urgency": round(adjusted, 4),
            "reliability_score": round(rel_score, 4),
            "source_reliability": round(source_rel, 4),
            "detection_confidence": round(detect_conf, 4),
            "trend_bonus": round(trend_bonus, 4),
            "gap_penalty": round(gap_penalty, 4),
            "classification": classification,
            "color": color,
            "recommended_action": action,
            "recommended_response_time": response_time,
        }
        explanation = await generate_explanation(event, payload)

        return SeverityResult(explanation=explanation, **payload)


def _classify(score: float) -> tuple[str, str, str]:
    for upper, label, color, action in CLASSIFICATION_THRESHOLDS:
        if score < upper:
            return label, color, action
    return "Extreme", "crimson", "Emergency response within 4h"


severity_engine = SeverityEngine()
