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
import time
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Tuple

import httpx

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

# India-context bias
_INDIA_REGION_BIAS = "IN"
_INDIA_STRICT_COMPONENT = {"country": "IN"}

# Nominatim Config
_NOMINATIM_ENDPOINT = "https://nominatim.openstreetmap.org/search"
_NOMINATIM_USER_AGENT = "SevaSetu-Crisis-Response/1.0 (contact@sevasetu.org)"
_NOMINATIM_RATE_LIMIT_S = 1.1  # Stay safe at > 1 second


# Geocoder class
class GeocodingService:
    """Wraps Google Maps Geocoding API with Indian-context bias and fallback."""

    def __init__(self) -> None:
        self._client = None
        self._use_nominatim = False
        self._last_nominatim_call = 0.0
        self._nominatim_lock = asyncio.Lock()
        self._enabled = True  # Always enabled now (falls back to Nominatim)
        self._init_client()

    def _init_client(self) -> None:
        api_key = os.environ.get("GOOGLE_MAPS_API_KEY", "").strip()
        if not api_key:
            logger.info("[Geocoder] GOOGLE_MAPS_API_KEY not set — using Nominatim fallback.")
            self._use_nominatim = True
            return
        
        if not _GMAPS_AVAILABLE:
            logger.warning("[Geocoder] googlemaps package not installed — using Nominatim fallback.")
            self._use_nominatim = True
            return

        try:
            self._client = googlemaps.Client(key=api_key)
            logger.info("[Geocoder] Google Maps geocoding ready.")
        except Exception as exc:
            logger.error("[Geocoder] Failed to init Maps client: %s. Using Nominatim.", exc)
            self._use_nominatim = True

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
            
            if self._use_nominatim:
                result = await self._resolve_nominatim_async(query)
            else:
                result = await asyncio.get_event_loop().run_in_executor(
                    None, self._resolve_sync, query
                )

            if result:
                return result

        return None

    # Resolvers
    async def _resolve_nominatim_async(self, query: str) -> Optional[GeoResult]:
        """Asynchronous geocoding via Nominatim (OSM)."""
        # Nominatim should be called serially and rate-limited to avoid 429 bursts.
        async with self._nominatim_lock:
            # Rate limiting
            now = time.time()
            elapsed = now - self._last_nominatim_call
            if elapsed < _NOMINATIM_RATE_LIMIT_S:
                await asyncio.sleep(_NOMINATIM_RATE_LIMIT_S - elapsed)

            params = {
                "q": query,
                "format": "json",
                "addressdetails": 1,
                "limit": 1,
                "countrycodes": "in", # Bias to India
            }
            headers = {"User-Agent": _NOMINATIM_USER_AGENT}

            data = None
            max_attempts = 3
            backoff = 1.2
            for attempt in range(1, max_attempts + 1):
                self._last_nominatim_call = time.time()
                try:
                    async with httpx.AsyncClient(timeout=10.0) as client:
                        response = await client.get(_NOMINATIM_ENDPOINT, params=params, headers=headers)
                        response.raise_for_status()
                        data = response.json()
                        break
                except httpx.HTTPStatusError as exc:
                    if exc.response.status_code == 429 and attempt < max_attempts:
                        await asyncio.sleep(backoff * attempt)
                        continue
                    logger.warning("[Geocoder] Nominatim HTTP error for '%s': %s", query, exc)
                    return None
                except Exception as exc:
                    logger.warning("[Geocoder] Nominatim call failed for '%s': %s", query, exc)
                    return None

            if data is None:
                return None

        if not data:
            logger.debug("[Geocoder] No Nominatim results for '%s'", query)
            return None

        result = data[0]
        lat = float(result.get("lat", 0.0))
        lon = float(result.get("lon", 0.0))
        
        if lat == 0.0 and lon == 0.0:
            return None

        # Determine admin level from Nominatim's address dict
        address = result.get("address", {})
        admin_level, confidence = self._mapping_nominatim_admin(address)

        resolved_name = result.get("display_name", query)
        logger.debug(
            "[Geocoder] Nominatim Resolved '%s' → (%.5f, %.5f) [%s, conf=%.2f]",
            query, lat, lon, admin_level, confidence,
        )
        return GeoResult(
            lat=lat,
            lon=lon,
            admin_level=admin_level,
            resolved_name=resolved_name,
            confidence=confidence,
        )

    @staticmethod
    def _mapping_nominatim_admin(address: Dict[str, Any]) -> Tuple[str, float]:
        """Maps Nominatim address components to internal admin levels."""
        # Finest to coarsest
        if any(k in address for k in ["village", "town", "hamlet", "suburb", "neighbourhood", "city_district"]):
            return "block", 0.85
        if any(k in address for k in ["city", "municipality"]):
            return "block", 0.80
        if any(k in address for k in ["county", "district", "state_district"]):
            return "district", 0.65
        if "state" in address:
            return "state", 0.50
        return "country", 0.30
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
