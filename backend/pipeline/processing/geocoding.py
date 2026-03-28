"""
Geocoding service for SevaSetu pipeline.

Resolves place name strings (extracted by NER) to precise
(latitude, longitude) coordinates using the Google Maps Geocoding API.

Fallback hierarchy when a precise match is not found:
  ward → block → district → state → country-centre

Returns None gracefully when:
  • GOOGLE_MAPS_API_KEY is not set
  • The googlemaps package is not installed
  • The API returns zero results

Admin level mapping from Google's result_type:
  locality / sublocality_level_1  → "block"
  administrative_area_level_3    → "block"
  administrative_area_level_2    → "district"
  administrative_area_level_1    → "state"
  country                        → "country"
"""

from __future__ import annotations

import asyncio
import logging
import os
from dataclasses import dataclass
from typing import List, Optional, Tuple

logger = logging.getLogger(__name__)

# Optional dependency guard
try:
    import googlemaps  # type: ignore
    _GMAPS_AVAILABLE = True
except ImportError:
    _GMAPS_AVAILABLE = False


# Result data class
@dataclass
class GeoResult:
    lat: float
    lon: float
    admin_level: str    # village | block | district | state | country
    resolved_name: str  # human-readable address returned by Maps
    confidence: float   # 1.0 = exact locality, lower for coarser levels


# Admin level mapping from Google result_type strings
_GOOGLE_TYPE_TO_ADMIN = {
    "street_address":              ("block",    1.00),
    "locality":                    ("block",    0.90),
    "sublocality":                 ("block",    0.85),
    "sublocality_level_1":         ("block",    0.85),
    "administrative_area_level_3": ("block",    0.75),
    "administrative_area_level_2": ("district", 0.65),
    "administrative_area_level_1": ("state",    0.50),
    "country":                     ("country",  0.30),
}

# Bias all queries toward India to avoid ambiguous results
_INDIA_REGION_BIAS = "IN"
_INDIA_STRICT_COMPONENT = {"country": "IN"}


# Geocoder class
class GeocodingService:
    """Wraps Google Maps Geocoding API with Indian-context bias and fallback."""

    def __init__(self) -> None:
        self._client = None
        self._enabled = False
        self._init_client()

    def _init_client(self) -> None:
        api_key = os.environ.get("GOOGLE_MAPS_API_KEY", "").strip()
        if not api_key:
            logger.info("[Geocoder] GOOGLE_MAPS_API_KEY not set — geocoding disabled.")
            return
        if not _GMAPS_AVAILABLE:
            logger.warning("[Geocoder] googlemaps package not installed — geocoding disabled.")
            return
        try:
            self._client = googlemaps.Client(key=api_key)
            self._enabled = True
            logger.info("[Geocoder] Google Maps geocoding ready.")
        except Exception as exc:
            logger.error("[Geocoder] Failed to init Maps client: %s", exc)

    # Public API
    async def geocode(
        self,
        places: List[str],
        country_hint: str = "India",
    ) -> Optional[GeoResult]:
        """
        Attempt to geocode each place name in the list (most to least specific).
        Returns the first successful result.

        Runs the synchronous googlemaps call in a thread pool to avoid
        blocking the main asyncio event loop.
        """
        if not self._enabled or not places:
            return None

        for place in places:
            query = f"{place}, {country_hint}"
            result = await asyncio.get_event_loop().run_in_executor(
                None, self._resolve_sync, query
            )
            if result:
                return result

        return None

    # Helpers
    def _resolve_sync(self, query: str) -> Optional[GeoResult]:
        """Synchronous geocoding call — run via executor, do not call directly."""
        try:
            results = self._client.geocode(
                query,
                region=_INDIA_REGION_BIAS,
            )
        except Exception as exc:
            logger.warning("[Geocoder] API call failed for '%s': %s", query, exc)
            return None

        if not results:
            logger.debug("[Geocoder] No results for '%s'", query)
            return None

        # Take the first (best-ranked) result
        result = results[0]
        geometry = result.get("geometry", {})
        loc = geometry.get("location", {})
        lat = float(loc.get("lat", 0.0))
        lon = float(loc.get("lng", 0.0))

        if lat == 0.0 and lon == 0.0:
            return None

        # Determine admin level from result_types (pick the finest grain)
        types: List[str] = result.get("types", [])
        admin_level, confidence = self._best_admin(types)

        formatted = result.get("formatted_address", query)
        logger.debug(
            "[Geocoder] Resolved '%s' → (%.5f, %.5f) [%s, conf=%.2f]",
            query, lat, lon, admin_level, confidence,
        )
        return GeoResult(
            lat=lat,
            lon=lon,
            admin_level=admin_level,
            resolved_name=formatted,
            confidence=confidence,
        )

    @staticmethod
    def _best_admin(types: List[str]) -> Tuple[str, float]:
        """Return the finest matching admin level from result types."""
        best_admin = "country"
        best_conf = 0.20
        for t in types:
            if t in _GOOGLE_TYPE_TO_ADMIN:
                admin, conf = _GOOGLE_TYPE_TO_ADMIN[t]
                if conf > best_conf:
                    best_admin = admin
                    best_conf = conf
        return best_admin, best_conf


# Global singleton
geocoding_service = GeocodingService()
