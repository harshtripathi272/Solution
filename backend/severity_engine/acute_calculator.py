from __future__ import annotations

from severity_engine.constants import ACUTE_COMPLEXITY_WEIGHT, ACUTE_CONDITIONS_WEIGHT, ACUTE_IMPACT_WEIGHT
from severity_engine.utils import clamp01, safe_float


def _impact_score(event) -> float:
    metadata = getattr(event, "metadata", {}) or {}
    mm_analysis = metadata.get("multimodal_analysis") or {}

    affected_area_km2 = safe_float(metadata.get("affected_area_km2"), 0.0)
    district_area_km2 = safe_float(metadata.get("district_area_km2"), 1500.0) # Conservative default
    geographical_scope = clamp01(affected_area_km2 / district_area_km2) if district_area_km2 > 0 else 0.0

    population_affected = safe_float(getattr(event, "population_affected", 0), 0.0)
    # BUG FIX: Defaulting to max(pop, 1) was causing 100% impact when district_population was missing.
    # We now use a more realistic district-level population fallback (e.g. 500k for average Indian district)
    district_population = safe_float(metadata.get("district_population"), 500_000.0) 
    human_impact = clamp01(population_affected / district_population) if district_population > 0 else 0.0

    # LLM-extracted primary indicator
    extracted_damage = safe_float(metadata.get("infrastructure_damage_score"), 0.0)
    # Multimodal validation/boost
    visual_evidence = 0.0
    if mm_analysis.get("destruction_detected"):
        visual_evidence = 0.5
    
    physical_damage = clamp01(max(extracted_damage, visual_evidence))

    return clamp01((geographical_scope + human_impact + physical_damage) / 3.0)


def _conditions_score(event) -> float:
    metadata = getattr(event, "metadata", {}) or {}
    mm_analysis = metadata.get("multimodal_analysis") or {}

    # WHO-style 1-5 scale, then normalize to 0-1.
    water = safe_float(metadata.get("water_access_severity", 3.0), 3.0)
    food = safe_float(metadata.get("food_security_severity", 3.0), 3.0)
    health = safe_float(metadata.get("health_service_severity", 3.0), 3.0)

    distress = safe_float(mm_analysis.get("distress_level"), 0.0)

    def _norm_1_to_5(v: float) -> float:
        return clamp01((v - 1.0) / 4.0)

    base_conditions = (_norm_1_to_5(water) + _norm_1_to_5(food) + _norm_1_to_5(health)) / 3.0
    # Auditory/Visual distress can push the conditions score higher
    return clamp01(base_conditions + (distress * 0.2))


def _complexity_score(event) -> float:
    metadata = getattr(event, "metadata", {}) or {}
    mm_analysis = metadata.get("multimodal_analysis") or {}

    road = safe_float(metadata.get("road_accessibility_risk", 0.3), 0.3)
    security = safe_float(metadata.get("security_constraint_risk", 0.2), 0.2)
    weather = safe_float(metadata.get("weather_interference_risk", 0.2), 0.2)

    crowd_estimate = safe_float(mm_analysis.get("crowd_size_estimate"), 0.0)
    if crowd_estimate > 100:
        security = max(security, 0.6)  # High crowd = high constraint

    season = str(metadata.get("season", "")).lower()
    if "monsoon" in season:
        weather = weather + 0.15

    return clamp01((clamp01(road) + clamp01(security) + clamp01(weather)) / 3.0)


def calculate_acute_severity(event) -> float:
    impact = _impact_score(event)
    conditions = _conditions_score(event)
    complexity = _complexity_score(event)

    return clamp01(
        impact * ACUTE_IMPACT_WEIGHT
        + conditions * ACUTE_CONDITIONS_WEIGHT
        + complexity * ACUTE_COMPLEXITY_WEIGHT
    )
