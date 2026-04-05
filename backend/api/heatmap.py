from __future__ import annotations

import asyncio
import hashlib
import json
import logging
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any

from fastapi import APIRouter, Depends, Query, Response

from auth import RoleChecker, db
from models import UserRole
from pipeline.processing.geohash import decode, encode
from pipeline.storage import bigquery_store

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1", tags=["heatmap"])


REGION_CENTRES: dict[str, tuple[float, float]] = {
    "assam": (26.2006, 92.9376),
    "bihar": (25.0961, 85.3131),
    "bundelkhand": (25.5, 79.5),
    "chhattisgarh": (21.2514, 81.6296),
    "jharkhand": (23.6102, 85.2799),
    "marathwada": (19.7515, 75.7139),
}

REGION_BOUNDARY_FEATURES: list[dict[str, Any]] = [
    {
        "type": "Feature",
        "properties": {
            "region_id": "bihar",
            "name": "Bihar",
        },
        "geometry": {
            "type": "Polygon",
            "coordinates": [
                [
                    [83.40, 24.00],
                    [84.55, 24.15],
                    [86.20, 24.10],
                    [87.60, 25.15],
                    [88.20, 26.35],
                    [87.30, 27.30],
                    [85.95, 27.45],
                    [84.30, 26.65],
                    [83.55, 25.55],
                    [83.40, 24.00],
                ]
            ],
        },
    },
    {
        "type": "Feature",
        "properties": {
            "region_id": "jharkhand",
            "name": "Jharkhand",
        },
        "geometry": {
            "type": "Polygon",
            "coordinates": [
                [
                    [83.20, 21.90],
                    [84.85, 22.00],
                    [86.55, 22.20],
                    [87.90, 23.35],
                    [87.80, 24.80],
                    [86.80, 25.40],
                    [85.00, 25.30],
                    [83.70, 24.60],
                    [83.30, 23.10],
                    [83.20, 21.90],
                ]
            ],
        },
    },
    {
        "type": "Feature",
        "properties": {
            "region_id": "assam",
            "name": "Assam",
        },
        "geometry": {
            "type": "Polygon",
            "coordinates": [
                [
                    [89.80, 24.10],
                    [91.00, 24.30],
                    [92.60, 24.60],
                    [94.10, 25.00],
                    [95.60, 26.00],
                    [96.10, 27.20],
                    [95.00, 27.80],
                    [93.40, 27.50],
                    [91.60, 27.20],
                    [90.20, 26.30],
                    [89.80, 25.00],
                    [89.80, 24.10],
                ]
            ],
        },
    },
    {
        "type": "Feature",
        "properties": {
            "region_id": "bundelkhand",
            "name": "Bundelkhand",
        },
        "geometry": {
            "type": "Polygon",
            "coordinates": [
                [
                    [78.10, 23.30],
                    [79.50, 23.40],
                    [80.80, 23.80],
                    [81.80, 24.60],
                    [81.90, 25.80],
                    [81.20, 26.50],
                    [79.80, 26.40],
                    [78.60, 25.80],
                    [78.10, 24.80],
                    [78.10, 23.30],
                ]
            ],
        },
    },
    {
        "type": "Feature",
        "properties": {
            "region_id": "marathwada",
            "name": "Marathwada",
        },
        "geometry": {
            "type": "Polygon",
            "coordinates": [
                [
                    [74.90, 17.20],
                    [75.90, 17.00],
                    [77.20, 17.20],
                    [78.40, 18.00],
                    [78.60, 19.20],
                    [78.00, 20.10],
                    [76.80, 20.50],
                    [75.40, 20.20],
                    [74.90, 19.00],
                    [74.90, 17.20],
                ]
            ],
        },
    },
]

SEVERITY_CLASSES = (
    (0.8, "Extreme"),
    (0.6, "Severe"),
    (0.4, "Moderate"),
    (0.2, "Stressed"),
    (0.0, "Minimal"),
)


@dataclass
class HeatPoint:
    lat: float
    lon: float
    severity: float
    need_type: str
    population_affected: int
    confidence: float
    timestamp: datetime
    source: str


def _parse_time_range(value: str) -> timedelta:
    normalized = value.strip().lower()
    mapping = {
        "24h": timedelta(hours=24),
        "7d": timedelta(days=7),
        "30d": timedelta(days=30),
        "1y": timedelta(days=365),
    }
    return mapping.get(normalized, timedelta(days=30))


def _parse_need_types(raw: str | None) -> set[str]:
    if not raw:
        return set()
    values = [part.strip().lower() for part in raw.split(",") if part.strip()]
    return set(values)


def _coerce_timestamp(value: Any) -> datetime:
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    if isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
            return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
        except ValueError:
            pass
    return datetime.now(timezone.utc)


def _classification(score: float) -> str:
    for threshold, label in SEVERITY_CLASSES:
        if score >= threshold:
            return label
    return "Minimal"


def _region_filter_match(region: str, payload: dict[str, Any]) -> bool:
    region_token = region.lower().strip()
    if not region_token:
        return True

    metadata = payload.get("metadata") or {}
    text_parts = [
        str(metadata.get("state", "")),
        str(metadata.get("district", "")),
        str(metadata.get("region", "")),
        str(metadata.get("resolved_name", "")),
        str(payload.get("latest_text_preview", "")),
        str(payload.get("latest_event_source", "")),
    ]
    combined = " ".join(text_parts).lower()
    if region_token in combined:
        return True

    if region_token in REGION_CENTRES and payload.get("centroid_lat") is not None and payload.get("centroid_lon") is not None:
        centre_lat, centre_lon = REGION_CENTRES[region_token]
        lat = float(payload["centroid_lat"])
        lon = float(payload["centroid_lon"])
        # Loose bounding-box heuristic for coarse filtering without ward polygons.
        return abs(lat - centre_lat) <= 4.5 and abs(lon - centre_lon) <= 4.5

    return False


async def _get_latest_event_payload(geohash: str, event_id: str | None) -> dict[str, Any] | None:
    if not event_id:
        return None

    def _fetch() -> dict[str, Any] | None:
        snapshot = (
            db.collection("need_regions")
            .document(geohash)
            .collection("events")
            .document(event_id)
            .get()
        )
        return snapshot.to_dict() if snapshot.exists else None

    return await asyncio.get_event_loop().run_in_executor(None, _fetch)


async def _fetch_firestore_points(
    since_ts: datetime,
    region: str | None,
    need_types: set[str],
    min_severity: float,
) -> list[HeatPoint]:
    query = (
        db.collection("need_regions")
        .where("last_updated", ">=", since_ts)
    )

    def _stream_docs() -> list[Any]:
        return list(query.stream())

    region_docs = await asyncio.get_event_loop().run_in_executor(None, _stream_docs)
    points: list[HeatPoint] = []

    for doc in region_docs:
        payload = doc.to_dict() or {}
        if region and not _region_filter_match(region, payload):
            continue

        lat = payload.get("centroid_lat")
        lon = payload.get("centroid_lon")
        if lat is None or lon is None:
            continue

        latest_event = await _get_latest_event_payload(doc.id, payload.get("latest_event_id"))
        latest_population = int((latest_event or {}).get("population_affected") or payload.get("event_count") or 0)
        latest_confidence = float((latest_event or {}).get("confidence_score") or 0.5)
        latest_source = str((latest_event or {}).get("source") or payload.get("latest_event_source") or "firestore")
        latest_timestamp = _coerce_timestamp((latest_event or {}).get("timestamp") or payload.get("last_updated"))

        # Support two schemas:
        # 1. New schema: single composite_urgency score + dominant_need (current Firestore structure)
        # 2. Old schema: need_scores map with individual need types
        need_scores = payload.get("need_scores") or {}
        
        if isinstance(need_scores, dict) and need_scores:
            # Old schema: iterate over need_scores map
            for need_type, raw_score in need_scores.items():
                need_type_norm = str(need_type).strip().lower()
                if need_types and need_type_norm not in need_types:
                    continue

                score = float(raw_score or 0.0)
                if score <= min_severity:
                    continue

                points.append(
                    HeatPoint(
                        lat=float(lat),
                        lon=float(lon),
                        severity=max(0.0, min(1.0, score)),
                        need_type=need_type_norm,
                        population_affected=max(0, latest_population),
                        confidence=max(0.0, min(1.0, latest_confidence)),
                        timestamp=latest_timestamp,
                        source=latest_source,
                    )
                )
        else:
            # New schema: use composite_urgency as single severity score
            composite_urgency = float(payload.get("composite_urgency") or 0.0)
            if composite_urgency <= min_severity:
                continue

            # Extract dominant need type or use field from payload
            dominant_need = payload.get("dominant_need", "general_need")
            if isinstance(dominant_need, str):
                # Handle comma-separated need types, extract first one
                need_type_norm = dominant_need.split(",")[0].strip().lower()
            else:
                need_type_norm = "general_need"

            if need_types and need_type_norm not in need_types:
                continue

            points.append(
                HeatPoint(
                    lat=float(lat),
                    lon=float(lon),
                    severity=max(0.0, min(1.0, composite_urgency)),
                    need_type=need_type_norm,
                    population_affected=max(0, latest_population),
                    confidence=max(0.0, min(1.0, latest_confidence)),
                    timestamp=latest_timestamp,
                    source=latest_source,
                )
            )

    return points


async def _fetch_bigquery_points(
    since_ts: datetime,
    region: str | None,
    need_types: set[str],
    min_severity: float,
) -> list[HeatPoint]:
    if not getattr(bigquery_store, "_enabled", False):
        return []

    table_ref = getattr(bigquery_store, "_table_ref", "")
    client = getattr(bigquery_store, "_client", None)
    if not table_ref or client is None:
        return []

    try:
        from google.cloud import bigquery
    except Exception:
        logger.warning("[heatmap] google-cloud-bigquery import unavailable during fallback query")
        return []

    params: list[Any] = [
        bigquery.ScalarQueryParameter("since_ts", "TIMESTAMP", since_ts),
        bigquery.ScalarQueryParameter("min_severity", "FLOAT64", min_severity),
    ]

    need_clause = ""
    if need_types:
        params.append(bigquery.ArrayQueryParameter("need_types", "STRING", sorted(need_types)))
        need_clause = "AND LOWER(need_type) IN UNNEST(@need_types)"

    region_clause = ""
    if region:
        params.append(bigquery.ScalarQueryParameter("region_like", "STRING", f"%{region.lower()}%"))
        region_clause = """
        AND (
            LOWER(source) LIKE @region_like OR
            LOWER(admin_level) LIKE @region_like OR
            LOWER(description) LIKE @region_like
        )
        """

    sql = f"""
        SELECT
            lat,
            lon,
            LOWER(need_type) AS need_type,
            COALESCE(severity_score, 0.0) AS severity,
            COALESCE(population_affected, 0) AS population_affected,
            COALESCE(confidence_score, 0.5) AS confidence,
            timestamp,
            source
        FROM `{table_ref}`
        WHERE timestamp >= @since_ts
          AND COALESCE(severity_score, 0.0) > @min_severity
          {need_clause}
          {region_clause}
    """

    query_job_config = bigquery.QueryJobConfig(query_parameters=params)

    def _run_query() -> list[Any]:
        return list(client.query(sql, job_config=query_job_config).result())

    rows = await asyncio.get_event_loop().run_in_executor(None, _run_query)

    points: list[HeatPoint] = []
    for row in rows:
        points.append(
            HeatPoint(
                lat=float(row["lat"]),
                lon=float(row["lon"]),
                severity=max(0.0, min(1.0, float(row["severity"]))),
                need_type=str(row["need_type"]),
                population_affected=max(0, int(row["population_affected"] or 0)),
                confidence=max(0.0, min(1.0, float(row["confidence"])),),
                timestamp=_coerce_timestamp(row["timestamp"]),
                source=str(row["source"] or "bigquery"),
            )
        )

    return points


def _aggregate_points(points: list[HeatPoint]) -> tuple[list[dict[str, Any]], int]:
    buckets: dict[str, dict[str, Any]] = {}

    for point in points:
        bucket_geohash = encode(point.lat, point.lon, precision=6)
        if not bucket_geohash:
            continue

        bucket = buckets.setdefault(
            bucket_geohash,
            {
                "severity_sum": 0.0,
                "count": 0,
                "population_max": 0,
                "confidence_sum": 0.0,
                "latest_ts": point.timestamp,
                "need_counts": {},
                "sources": set(),
            },
        )

        bucket["severity_sum"] += point.severity
        bucket["count"] += 1
        bucket["population_max"] = max(bucket["population_max"], point.population_affected)
        bucket["confidence_sum"] += point.confidence
        if point.timestamp > bucket["latest_ts"]:
            bucket["latest_ts"] = point.timestamp
        bucket["need_counts"][point.need_type] = bucket["need_counts"].get(point.need_type, 0) + 1
        bucket["sources"].add(point.source)

    features: list[dict[str, Any]] = []
    for geohash6, bucket in buckets.items():
        lat, lon = decode(geohash6)
        count = max(1, int(bucket["count"]))
        severity_avg = max(0.0, min(1.0, bucket["severity_sum"] / count))
        confidence_avg = max(0.0, min(1.0, bucket["confidence_sum"] / count))
        
        # Find dominant need type, default to first if no counts
        if bucket["need_counts"]:
            dominant_need = max(bucket["need_counts"], key=bucket["need_counts"].get)
        else:
            dominant_need = "general_need"

        features.append(
            {
                "type": "Feature",
                "geometry": {
                    "type": "Point",
                    "coordinates": [lon, lat],
                },
                "properties": {
                    "geohash": geohash6,
                    "latitude": lat,
                    "longitude": lon,
                    "severity": severity_avg,
                    "severity_label": _classification(severity_avg),
                    "need_type": dominant_need,
                    "need_type_breakdown": bucket["need_counts"],
                    "population_affected": bucket["population_max"],
                    "confidence": confidence_avg,
                    "last_updated": bucket["latest_ts"].isoformat(),
                    "source_count": len(bucket["sources"]),
                },
            }
        )

    return features, len(points)


def _build_etag(payload: dict[str, Any]) -> str:
    digest = hashlib.sha1(json.dumps(payload, sort_keys=True).encode("utf-8")).hexdigest()
    return f'W/"{digest}"'


@router.get("/heatmap-data")
async def get_heatmap_data(
    response: Response,
    region: str | None = Query(default=None),
    need_type: str | None = Query(default=None),
    min_severity: float = Query(default=0.1, ge=0.0, le=1.0),
    time_range: str = Query(default="30d"),
    _: Any = Depends(RoleChecker([UserRole.coordinator, UserRole.ngo_worker])),
):
    now = datetime.now(timezone.utc)
    since_ts = now - _parse_time_range(time_range)
    need_types = _parse_need_types(need_type)

    firestore_points = await _fetch_firestore_points(
        since_ts=since_ts,
        region=region,
        need_types=need_types,
        min_severity=min_severity,
    )

    data_source = "firestore"
    points = firestore_points

    if not points:
        try:
            fallback_points = await _fetch_bigquery_points(
                since_ts=since_ts,
                region=region,
                need_types=need_types,
                min_severity=min_severity,
            )
            if fallback_points:
                data_source = "bigquery"
                points = fallback_points
        except Exception as exc:
            logger.warning("[heatmap] BigQuery fallback failed (likely permissions): %s", exc)
            # Proceed with empty firestore_points (empty list)

    features, raw_count = _aggregate_points(points)

    payload = {
        "type": "FeatureCollection",
        "features": features,
        "metadata": {
            "generated_at": now.isoformat(),
            "source": data_source,
            "precision": 6,
            "raw_point_count": raw_count,
            "feature_count": len(features),
            "filters": {
                "region": region,
                "need_type": sorted(need_types),
                "min_severity": min_severity,
                "time_range": time_range,
            },
        },
    }

    response.headers["Cache-Control"] = "public, max-age=300"
    response.headers["ETag"] = _build_etag(payload)
    response.headers["Last-Modified"] = now.strftime("%a, %d %b %Y %H:%M:%S GMT")

    return payload


@router.get("/region-boundaries")
async def get_region_boundaries(
    response: Response,
    region: str | None = Query(default=None),
    _: Any = Depends(RoleChecker([UserRole.coordinator, UserRole.ngo_worker])),
):
    now = datetime.now(timezone.utc)
    requested_region = (region or "").strip().lower()

    if requested_region:
        features = [
            feature
            for feature in REGION_BOUNDARY_FEATURES
            if str(feature.get("properties", {}).get("region_id", "")).lower() == requested_region
        ]
    else:
        features = REGION_BOUNDARY_FEATURES

    payload = {
        "type": "FeatureCollection",
        "features": features,
        "metadata": {
            "generated_at": now.isoformat(),
            "feature_count": len(features),
        },
    }

    response.headers["Cache-Control"] = "public, max-age=3600"
    response.headers["ETag"] = _build_etag(payload)
    response.headers["Last-Modified"] = now.strftime("%a, %d %b %Y %H:%M:%S GMT")

    return payload
