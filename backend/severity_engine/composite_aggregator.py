from __future__ import annotations

from severity_engine.constants import CHRONIC_COMPOSITE_VISIBILITY_FACTOR, GAP_PENALTY_LOW_COVERAGE, LOW_COVERAGE_THRESHOLD
from severity_engine.utils import clamp01, safe_float


def volunteer_gap_penalty(event, nearby_volunteer_count: int) -> float:
    metadata = getattr(event, "metadata", {}) or {}
    expected_need = safe_float(metadata.get("required_volunteers"), 0.0)

    if expected_need <= 0:
        population = safe_float(getattr(event, "population_affected", 0), 0.0)
        expected_need = max(5.0, population / 50.0) if population > 0 else 5.0

    coverage = nearby_volunteer_count / expected_need if expected_need > 0 else 1.0
    return GAP_PENALTY_LOW_COVERAGE if coverage < LOW_COVERAGE_THRESHOLD else 0.0


def aggregate_composite_urgency(
    acute: float,
    chronic: float,
    trend_bonus: float,
    gap_penalty: float,
) -> float:
    base = max(clamp01(acute), clamp01(chronic) * CHRONIC_COMPOSITE_VISIBILITY_FACTOR)
    return clamp01(base + clamp01(trend_bonus) + clamp01(gap_penalty))
