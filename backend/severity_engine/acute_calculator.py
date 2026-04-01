from __future__ import annotations

from severity_engine.constants import ACUTE_COMPLEXITY_WEIGHT, ACUTE_CONDITIONS_WEIGHT, ACUTE_IMPACT_WEIGHT
from severity_engine.utils import clamp01, safe_float


def _impact_score(event) -> float:
    metadata = getattr(event, "metadata", {}) or {}

    affected_area_km2 = safe_float(metadata.get("affected_area_km2"), 0.0)
    district_area_km2 = safe_float(metadata.get("district_area_km2"), 1000.0)
    geographical_scope = clamp01(affected_area_km2 / district_area_km2) if district_area_km2 > 0 else 0.0

    population_affected = safe_float(getattr(event, "population_affected", 0), 0.0)
    district_population = safe_float(metadata.get("district_population"), max(population_affected, 1.0))
    human_impact = clamp01(population_affected / district_population) if district_population > 0 else 0.0

    physical_damage = clamp01(safe_float(metadata.get("infrastructure_damage_score"), 0.0))

    return clamp01((geographical_scope + human_impact + physical_damage) / 3.0)


def _conditions_score(event) -> float:
    metadata = getattr(event, "metadata", {}) or {}

    # WHO-style 1-5 scale, then normalize to 0-1.
    water = safe_float(metadata.get("water_access_severity", 3.0), 3.0)
    food = safe_float(metadata.get("food_security_severity", 3.0), 3.0)
    health = safe_float(metadata.get("health_service_severity", 3.0), 3.0)

    def _norm_1_to_5(v: float) -> float:
        return clamp01((v - 1.0) / 4.0)

    return clamp01((_norm_1_to_5(water) + _norm_1_to_5(food) + _norm_1_to_5(health)) / 3.0)


def _complexity_score(event) -> float:
    metadata = getattr(event, "metadata", {}) or {}

    road = clamp01(safe_float(metadata.get("road_accessibility_risk", 0.3), 0.3))
    security = clamp01(safe_float(metadata.get("security_constraint_risk", 0.2), 0.2))
    weather = clamp01(safe_float(metadata.get("weather_interference_risk", 0.2), 0.2))

    season = str(metadata.get("season", "")).lower()
    if "monsoon" in season:
        weather = clamp01(weather + 0.15)

    return clamp01((road + security + weather) / 3.0)


def calculate_acute_severity(event) -> float:
    impact = _impact_score(event)
    conditions = _conditions_score(event)
    complexity = _complexity_score(event)

    return clamp01(
        impact * ACUTE_IMPACT_WEIGHT
        + conditions * ACUTE_CONDITIONS_WEIGHT
        + complexity * ACUTE_COMPLEXITY_WEIGHT
    )
