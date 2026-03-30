"""
BigQuery append-only analytics sink.

Each normalized event is streamed as a row into a BigQuery table.
This enables large-scale SQL queries for trend analysis, regional
comparisons, and future ML feature extraction.

Schema (auto-created on first run if table does not exist):
  event_id             STRING   REQUIRED
  region_id            STRING   REQUIRED  ← geohash (5 chars)
  lat                  FLOAT64  REQUIRED
  lon                  FLOAT64  REQUIRED
  need_type            STRING   REQUIRED
  severity             STRING   NULLABLE
  severity_score       FLOAT64  NULLABLE
  confidence_score     FLOAT64  NULLABLE
  timestamp            TIMESTAMP REQUIRED
  source               STRING   REQUIRED
  source_tier          INT64    NULLABLE
  admin_level          STRING   NULLABLE
  population_affected  INT64    NULLABLE
  description          STRING   NULLABLE

Graceful no-op behaviour
------------------------
When BIGQUERY_PROJECT is not set, every call logs one info message and returns
immediately. Install `google-cloud-bigquery` to enable live writes.
"""

from __future__ import annotations

import logging
import os
from datetime import datetime, timezone
from typing import TYPE_CHECKING, List

if TYPE_CHECKING:
    from pipeline.core.schemas import UnifiedIngestionEvent

logger = logging.getLogger(__name__)

# Optional dependency guard
try:
    from google.cloud import bigquery  # type: ignore
    _BQ_AVAILABLE = True
except ImportError:
    _BQ_AVAILABLE = False

# BigQuery table schema definition
_SCHEMA = [
    {"name": "event_id",            "type": "STRING",    "mode": "REQUIRED"},
    {"name": "region_id",           "type": "STRING",    "mode": "REQUIRED"},
    {"name": "lat",                  "type": "FLOAT64",   "mode": "REQUIRED"},
    {"name": "lon",                  "type": "FLOAT64",   "mode": "REQUIRED"},
    {"name": "need_type",           "type": "STRING",    "mode": "REQUIRED"},
    {"name": "severity",            "type": "STRING",    "mode": "NULLABLE"},
    {"name": "severity_score",      "type": "FLOAT64",   "mode": "NULLABLE"},
    {"name": "confidence_score",    "type": "FLOAT64",   "mode": "NULLABLE"},
    {"name": "timestamp",           "type": "TIMESTAMP", "mode": "REQUIRED"},
    {"name": "source",              "type": "STRING",    "mode": "REQUIRED"},
    {"name": "source_tier",         "type": "INT64",     "mode": "NULLABLE"},
    {"name": "admin_level",         "type": "STRING",    "mode": "NULLABLE"},
    {"name": "population_affected", "type": "INT64",     "mode": "NULLABLE"},
    {"name": "description",         "type": "STRING",    "mode": "NULLABLE"},
]

_DOCUMENT_SCHEMA = [
    {"name": "event_id",              "type": "STRING",    "mode": "REQUIRED"},
    {"name": "region_id",             "type": "STRING",    "mode": "REQUIRED"},
    {"name": "lat",                   "type": "FLOAT64",   "mode": "REQUIRED"},
    {"name": "lon",                   "type": "FLOAT64",   "mode": "REQUIRED"},
    {"name": "need_type",             "type": "STRING",    "mode": "REQUIRED"},
    {"name": "severity",              "type": "STRING",    "mode": "NULLABLE"},
    {"name": "severity_score",        "type": "FLOAT64",   "mode": "NULLABLE"},
    {"name": "confidence_score",      "type": "FLOAT64",   "mode": "NULLABLE"},
    {"name": "event_timestamp",       "type": "TIMESTAMP", "mode": "REQUIRED"},
    {"name": "extraction_timestamp",  "type": "TIMESTAMP", "mode": "REQUIRED"},
    {"name": "source",                "type": "STRING",    "mode": "REQUIRED"},
    {"name": "source_tier",           "type": "INT64",     "mode": "NULLABLE"},
    {"name": "admin_level",           "type": "STRING",    "mode": "NULLABLE"},
    {"name": "population_affected",   "type": "INT64",     "mode": "NULLABLE"},
    {"name": "description",           "type": "STRING",    "mode": "NULLABLE"},
    {"name": "source_ngo",            "type": "STRING",    "mode": "NULLABLE"},
    {"name": "pdf_url",               "type": "STRING",    "mode": "NULLABLE"},
    {"name": "publication_date",      "type": "TIMESTAMP", "mode": "NULLABLE"},
    {"name": "document_sha256",       "type": "STRING",    "mode": "NULLABLE"},
    {"name": "need_temporality",      "type": "STRING",    "mode": "NULLABLE"},
]


class BigQueryStore:
    """Append-only BigQuery sink — inserts rows via streaming insert API."""

    def __init__(self) -> None:
        self._client = None
        self._table_ref: str = ""
        self._document_table_ref: str = ""
        self._enabled = False
        self._init()

    def _init(self) -> None:
        project = os.environ.get("BIGQUERY_PROJECT", "").strip()
        if not project:
            logger.info("[BigQuery] BIGQUERY_PROJECT not set — analytics sink disabled.")
            return
        if not _BQ_AVAILABLE:
            logger.warning("[BigQuery] google-cloud-bigquery not installed — sink disabled.")
            return

        dataset = os.environ.get("BIGQUERY_DATASET", "sevasetu_events").strip()
        table = os.environ.get("BIGQUERY_TABLE", "need_events").strip()
        document_table = os.environ.get("BIGQUERY_DOCUMENT_TABLE", "document_events").strip()

        try:
            self._client = bigquery.Client(project=project)
            self._table_ref = f"{project}.{dataset}.{table}"
            self._document_table_ref = f"{project}.{dataset}.{document_table}"
            self._ensure_table(dataset, table, schema_config=_SCHEMA)
            self._ensure_table(
                dataset,
                document_table,
                schema_config=_DOCUMENT_SCHEMA,
                partition_field="extraction_timestamp",
            )
            self._enabled = True
            logger.info("[BigQuery] Sink ready → %s", self._table_ref)
            logger.info("[BigQuery] Document sink ready → %s", self._document_table_ref)
        except Exception as exc:
            logger.error("[BigQuery] Init failed: %s — sink disabled.", exc)

    def _ensure_table(
        self,
        dataset_id: str,
        table_id: str,
        schema_config: list[dict],
        partition_field: str | None = None,
    ) -> None:
        """Create dataset + table if they don't already exist."""
        project = os.environ.get("BIGQUERY_PROJECT", "")
        dataset_ref = self._client.dataset(dataset_id)

        # Dataset
        try:
            self._client.get_dataset(dataset_ref)
        except Exception:
            ds = bigquery.Dataset(dataset_ref)
            ds.location = "US"
            self._client.create_dataset(ds, exists_ok=True)
            logger.info("[BigQuery] Created dataset: %s", dataset_id)

        # Table
        table_ref = dataset_ref.table(table_id)
        try:
            self._client.get_table(table_ref)
        except Exception:
            schema = [
                bigquery.SchemaField(col["name"], col["type"], mode=col["mode"])
                for col in schema_config
            ]
            table_obj = bigquery.Table(table_ref, schema=schema)
            if partition_field:
                table_obj.time_partitioning = bigquery.TimePartitioning(
                    type_=bigquery.TimePartitioningType.DAY,
                    field=partition_field,
                )
            self._client.create_table(table_obj, exists_ok=True)
            logger.info("[BigQuery] Created table: %s.%s.%s", project, dataset_id, table_id)

    # Public API
    async def append(self, event: "UnifiedIngestionEvent", score: float) -> None:
        """
        Stream-insert one event row into BigQuery.
        Non-blocking: errors are logged but never re-raised.
        """
        if not self._enabled:
            return

        row = {
            "event_id":            event.id,
            "region_id":           event.geohash or "",
            "lat":                 event.location.latitude,
            "lon":                 event.location.longitude,
            "need_type":           event.need_type,
            "severity":            event.severity,
            "severity_score":      score,
            "confidence_score":    event.confidence_score,
            "timestamp":           event.timestamp.isoformat(),
            "source":              event.source,
            "source_tier":         event.source_tier,
            "admin_level":         event.admin_level,
            "population_affected": event.population_affected,
            "description":         (event.description or "")[:500],
        }

        try:
            import asyncio
            errors: List[dict] = await asyncio.get_event_loop().run_in_executor(
                None, lambda: self._client.insert_rows_json(self._table_ref, [row])
            )
            if errors:
                logger.error("[BigQuery] Insert errors: %s", errors)
            else:
                logger.debug("[BigQuery] Appended event %s", event.id)
        except Exception as exc:
            logger.error("[BigQuery] append failed for %s: %s", event.id, exc)

    async def append_document_event(self, event: "UnifiedIngestionEvent", score: float) -> None:
        """Stream-insert one document-derived event row into the partitioned document table."""
        if not self._enabled or not self._document_table_ref:
            return

        metadata = event.document_metadata
        row = {
            "event_id": event.id,
            "region_id": event.geohash or "",
            "lat": event.location.latitude,
            "lon": event.location.longitude,
            "need_type": event.need_type,
            "severity": event.severity,
            "severity_score": score,
            "confidence_score": event.confidence_score,
            "event_timestamp": event.timestamp.isoformat(),
            "extraction_timestamp": datetime.now(timezone.utc).isoformat(),
            "source": event.source,
            "source_tier": event.source_tier,
            "admin_level": event.admin_level,
            "population_affected": event.population_affected,
            "description": (event.description or "")[:500],
            "source_ngo": metadata.source_ngo if metadata else None,
            "pdf_url": metadata.pdf_url if metadata else None,
            "publication_date": metadata.publication_date.isoformat() if metadata and metadata.publication_date else None,
            "document_sha256": metadata.sha256_hash if metadata else None,
            "need_temporality": event.need_temporality.value if hasattr(event.need_temporality, "value") else str(event.need_temporality),
        }

        try:
            import asyncio
            errors: List[dict] = await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: self._client.insert_rows_json(self._document_table_ref, [row]),
            )
            if errors:
                logger.error("[BigQuery] Document insert errors: %s", errors)
            else:
                logger.debug("[BigQuery] Appended document event %s", event.id)
        except Exception as exc:
            logger.error("[BigQuery] append_document_event failed for %s: %s", event.id, exc)


# Global singleton
bigquery_store = BigQueryStore()
