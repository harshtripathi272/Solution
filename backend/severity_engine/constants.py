from __future__ import annotations

from typing import Final

# INFORM-inspired component weights for acute severity.
ACUTE_IMPACT_WEIGHT: Final[float] = 0.33
ACUTE_CONDITIONS_WEIGHT: Final[float] = 0.50
ACUTE_COMPLEXITY_WEIGHT: Final[float] = 0.17

# Chronic temporal decay: exp(-lambda * days_since_report).
CHRONIC_DECAY_LAMBDA: Final[float] = 0.01

# Composite urgency controls.
CHRONIC_COMPOSITE_VISIBILITY_FACTOR: Final[float] = 0.70
TREND_BONUS_MIN: Final[float] = 0.10
TREND_BONUS_MAX: Final[float] = 0.20
GAP_PENALTY_LOW_COVERAGE: Final[float] = 0.15
LOW_COVERAGE_THRESHOLD: Final[float] = 0.20

# Source reliability baselines.
SOURCE_RELIABILITY = {
    "OXFAM": 0.95,
    "PRADAN": 0.95,
    "GDACS": 0.90,
    "NDMA": 0.90,
    "KOBO": 0.85,
    "SURVEY": 0.85,
    "TWITTER": 0.60,
    "X": 0.60,
    "NEWS_API": 0.70,
    "NEWSDATA_IO": 0.70,
}

DEFAULT_SOURCE_RELIABILITY: Final[float] = 0.75

CLASSIFICATION_THRESHOLDS = [
    (0.2, "Minimal", "green", "No action required"),
    (0.4, "Stressed", "yellow", "Monitor monthly"),
    (0.6, "Moderate", "orange", "Activate local volunteers"),
    (0.8, "Severe", "red", "Deploy specialized teams within 24h"),
    (1.01, "Extreme", "crimson", "Emergency response within 4h"),
]

RESPONSE_TIME_BY_CLASSIFICATION = {
    "Minimal": "No dispatch required",
    "Stressed": "Monitor monthly",
    "Moderate": "48h",
    "Severe": "24h",
    "Extreme": "4h",
}

CLASSIFICATION_TO_SEVERITY_LABEL = {
    "Minimal": "low",
    "Stressed": "moderate",
    "Moderate": "moderate",
    "Severe": "high",
    "Extreme": "critical",
}
