"""
Geohash encoding utilities for SevaSetu.

Precision guide (Geohash length → approximate cell size):
  4 → ~40 km × 20 km   (state-level)
  5 → ~5 km  ×  5 km   (block-level) ← default for need analysis
  6 → ~1 km  ×  0.6 km (village-level)

All pipeline modules use precision=5 by default so that nearby reports
from different lat/lon points roll up to the same region bucket.
"""

from __future__ import annotations

import logging
from typing import List, Tuple

try:
    import geohash as _geohash  # python-geohash package
    _GEOHASH_AVAILABLE = True
except ImportError:            # pragma: no cover
    _GEOHASH_AVAILABLE = False

logger = logging.getLogger(__name__)

# Default precision: ~5 km × 5 km cell
DEFAULT_PRECISION = 5


def encode(lat: float, lon: float, precision: int = DEFAULT_PRECISION) -> str:
    """
    Encode (lat, lon) into a geohash string of the given precision.

    Returns an empty string if the geohash library is not installed
    (pipeline degrades gracefully — no errors propagate).
    """
    if not _GEOHASH_AVAILABLE:
        logger.warning("[GeoHash] python-geohash not installed — geohash encoding skipped.")
        return ""
    try:
        return _geohash.encode(lat, lon, precision)
    except Exception as exc:
        logger.error("[GeoHash] encode failed for (%.5f, %.5f): %s", lat, lon, exc)
        return ""


def decode(hash_str: str) -> Tuple[float, float]:
    """
    Decode a geohash string back to the centre (lat, lon) of its cell.

    Returns (0.0, 0.0) on failure.
    """
    if not _GEOHASH_AVAILABLE or not hash_str:
        return (0.0, 0.0)
    try:
        lat, lon = _geohash.decode(hash_str)
        return (float(lat), float(lon))
    except Exception as exc:
        logger.error("[GeoHash] decode failed for '%s': %s", hash_str, exc)
        return (0.0, 0.0)


def decode_with_bounds(hash_str: str) -> dict:
    """
    Return centre + bounding box for a geohash cell.
    Useful for drawing polygons on the coordinator map.
    """
    if not _GEOHASH_AVAILABLE or not hash_str:
        return {}
    try:
        lat, lon, lat_err, lon_err = _geohash.decode_exactly(hash_str)
        return {
            "centre_lat": float(lat),
            "centre_lon": float(lon),
            "min_lat": float(lat - lat_err),
            "max_lat": float(lat + lat_err),
            "min_lon": float(lon - lon_err),
            "max_lon": float(lon + lon_err),
        }
    except Exception as exc:
        logger.error("[GeoHash] decode_with_bounds failed for '%s': %s", hash_str, exc)
        return {}


def neighbours(hash_str: str) -> List[str]:
    """
    Return the 8 neighbouring geohash cells (N, NE, E, SE, S, SW, W, NW).
    Used for proximity queries when searching adjacent regions.
    """
    if not _GEOHASH_AVAILABLE or not hash_str:
        return []
    try:
        return list(_geohash.neighbors(hash_str))
    except Exception as exc:
        logger.error("[GeoHash] neighbours failed for '%s': %s", hash_str, exc)
        return []
