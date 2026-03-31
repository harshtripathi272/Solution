from __future__ import annotations

import asyncio
from datetime import datetime, timezone, timedelta
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BACKEND = ROOT / "backend"
if str(BACKEND) not in sys.path:
    sys.path.insert(0, str(BACKEND))

from pipeline.core.schemas import IngestionLocation, NeedTemporality, UnifiedIngestionEvent  # type: ignore[import-not-found]
from severity_engine.acute_calculator import calculate_acute_severity  # type: ignore[import-not-found]
from severity_engine.chronic_calculator import calculate_chronic_severity  # type: ignore[import-not-found]
from severity_engine.composite_aggregator import aggregate_composite_urgency, volunteer_gap_penalty  # type: ignore[import-not-found]
from severity_engine.constants import CHRONIC_DECAY_LAMBDA  # type: ignore[import-not-found]
from severity_engine.engine import SeverityEngine  # type: ignore[import-not-found]
from severity_engine.reliability import reliability_score  # type: ignore[import-not-found]


def _make_event(**overrides) -> UnifiedIngestionEvent:
    base = UnifiedIngestionEvent(
        id="evt-1",
        location=IngestionLocation(latitude=25.0, longitude=85.0),
        need_type="water_sanitation",
        severity="high",
        timestamp=datetime.now(timezone.utc),
        source="GDACS",
        need_temporality=NeedTemporality.ACUTE,
        confidence_score=0.9,
        description="Water access degraded after flooding.",
        metadata={
            "affected_area_km2": 120,
            "district_area_km2": 1000,
            "district_population": 500000,
            "infrastructure_damage_score": 0.6,
            "water_access_severity": 4,
            "food_security_severity": 3,
            "health_service_severity": 4,
            "road_accessibility_risk": 0.5,
            "security_constraint_risk": 0.2,
            "weather_interference_risk": 0.7,
            "geocode_confidence": 0.9,
            "required_volunteers": 20,
            "lineage": "event",
        },
        population_affected=25000,
        source_tier=1,
        geohash="tsm0q",
        admin_level="district",
        needs_geocoding=False,
    )
    return base.model_copy(update=overrides)


def test_acute_score_within_bounds() -> None:
    event = _make_event()
    score = calculate_acute_severity(event)
    assert 0.0 <= score <= 1.0
    assert score > 0.45


def test_population_fallback_fix() -> None:
    # Event with NO district_population in metadata
    event = _make_event(
        population_affected=1000,
        metadata={"affected_area_km2": 0, "infrastructure_damage_score": 0}
    )
    # Remove district_population from metadata
    event.metadata.pop("district_population", None)
    
    score = calculate_acute_severity(event)
    # Impact score should be (0 + (1000/500000) + 0) / 3 = 0.00066
    # Total score should be low, NOT 1.0 (which happened before the fix)
    assert score < 0.3


def test_chronic_decay_reduces_old_reports() -> None:
    older_ts = datetime.now(timezone.utc) - timedelta(days=120)
    recent_ts = datetime.now(timezone.utc) - timedelta(days=2)

    old_event = _make_event(
        need_temporality=NeedTemporality.CHRONIC,
        timestamp=older_ts,
        metadata={
            "infrastructure_gaps": [{"status": "no handpump"}],
            "vulnerable_groups": ["children", "elderly"],
            "historical_crisis_frequency": 8,
        },
    )
    new_event = _make_event(
        need_temporality=NeedTemporality.CHRONIC,
        timestamp=recent_ts,
        metadata={
            "infrastructure_gaps": [{"status": "no handpump"}],
            "vulnerable_groups": ["children", "elderly"],
            "historical_crisis_frequency": 8,
        },
    )

    old_score = calculate_chronic_severity(old_event)
    new_score = calculate_chronic_severity(new_event)

    assert CHRONIC_DECAY_LAMBDA == 0.01
    assert 0.0 <= old_score <= 1.0
    assert 0.0 <= new_score <= 1.0
    assert old_score < new_score


def test_composite_formula_and_gap_penalty() -> None:
    event = _make_event(metadata={"required_volunteers": 20})
    penalty = volunteer_gap_penalty(event, nearby_volunteer_count=2)
    score = aggregate_composite_urgency(acute=0.6, chronic=0.5, trend_bonus=0.15, gap_penalty=penalty)

    assert penalty == 0.15
    assert 0.0 <= score <= 1.0
    assert score >= 0.75


def test_reliability_uses_source_and_detection_confidence() -> None:
    event = _make_event(source="TWITTER_STREAM", confidence_score=0.8, metadata={"geocode_confidence": 0.5})
    rel, source_rel, detect = reliability_score(event)

    assert source_rel == 0.60
    assert round(detect, 4) == 0.4
    assert round(rel, 4) == 0.24


def test_engine_classification_output() -> None:
    event = _make_event(
        source="OXFAM_REPORT",
        need_temporality=NeedTemporality.CHRONIC,
        metadata={
            "infrastructure_gaps": [{"status": "no handpump"}],
            "vulnerable_groups": ["children", "disabled", "elderly"],
            "historical_crisis_frequency": 10,
            "required_volunteers": 10,
            "geocode_confidence": 0.9,
            "lineage": "document",
        },
    )

    result = asyncio.run(SeverityEngine().calculate(event, nearby_volunteer_count=1))

    assert 0.0 <= result.composite_urgency <= 1.0
    assert result.classification in {"Minimal", "Stressed", "Moderate", "Severe", "Extreme"}
    assert isinstance(result.recommended_response_time, str)
    assert result.explanation
