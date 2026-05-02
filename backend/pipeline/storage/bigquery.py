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

import asyncio
import logging
import os
from datetime import datetime, timezone
from typing import TYPE_CHECKING, List
from concurrent.futures import ThreadPoolExecutor

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

_SEVERITY_SCHEMA = [
    {"name": "event_id", "type": "STRING", "mode": "REQUIRED"},
    {"name": "region_id", "type": "STRING", "mode": "REQUIRED"},
    {"name": "need_type", "type": "STRING", "mode": "REQUIRED"},
    {"name": "timestamp", "type": "TIMESTAMP", "mode": "REQUIRED"},
    {"name": "source", "type": "STRING", "mode": "REQUIRED"},
    {"name": "lineage", "type": "STRING", "mode": "NULLABLE"},
    {"name": "severity_acute", "type": "FLOAT64", "mode": "NULLABLE"},
    {"name": "severity_chronic", "type": "FLOAT64", "mode": "NULLABLE"},
    {"name": "composite_urgency", "type": "FLOAT64", "mode": "NULLABLE"},
    {"name": "reliability_score", "type": "FLOAT64", "mode": "NULLABLE"},
    {"name": "source_reliability", "type": "FLOAT64", "mode": "NULLABLE"},
    {"name": "detection_confidence", "type": "FLOAT64", "mode": "NULLABLE"},
    {"name": "trend_bonus", "type": "FLOAT64", "mode": "NULLABLE"},
    {"name": "gap_penalty", "type": "FLOAT64", "mode": "NULLABLE"},
    {"name": "classification", "type": "STRING", "mode": "NULLABLE"},
    {"name": "recommended_response_time", "type": "STRING", "mode": "NULLABLE"},
]

_SEVERITY_TIMESERIES_SCHEMA = [
    {"name": "region_id", "type": "STRING", "mode": "REQUIRED"},
    {"name": "need_type", "type": "STRING", "mode": "REQUIRED"},
    {"name": "event_id", "type": "STRING", "mode": "REQUIRED"},
    {"name": "timestamp", "type": "TIMESTAMP", "mode": "REQUIRED"},
    {"name": "severity_value", "type": "FLOAT64", "mode": "NULLABLE"},
    {"name": "classification", "type": "STRING", "mode": "NULLABLE"},
    {"name": "feedback", "type": "STRING", "mode": "NULLABLE"},
]


class BigQueryStore:
    """Append-only BigQuery sink — inserts rows via streaming insert API with batching."""

    def __init__(self) -> None:
        self._client = None
        self._table_ref: str = ""
        self._document_table_ref: str = ""
        self._severity_table_ref: str = ""
        self._severity_timeseries_table_ref: str = ""
        self._enabled = False
        
        # Batch writer configuration for non-blocking event processing
        self._batch_size = int(os.environ.get("BIGQUERY_BATCH_SIZE", "50"))
        self._batch_timeout_sec = float(os.environ.get("BIGQUERY_BATCH_TIMEOUT", "5"))
        
        # Pending batches per table
        self._pending_events: dict[str, list] = {}
        self._pending_docs: list = []
        self._pending_severity: list = []
        self._pending_timeseries: list = []
        
        # Batch flush tasks
        self._batch_tasks: dict[str, asyncio.Task] = {}
        
        # Thread pool for blocking BigQuery operations
        # Increased from default to handle multiple concurrent operations
        self._executor = ThreadPoolExecutor(
            max_workers=int(os.environ.get("BIGQUERY_EXECUTOR_WORKERS", "20")),
            thread_name_prefix="bigquery-io-"
        )
        
        self._init()


    def _init(self) -> None:
        project = os.environ.get("BIGQUERY_PROJECT", "").strip()
        if not project or project.startswith("YOUR_"):
            logger.info("[BigQuery] BIGQUERY_PROJECT not set or is a placeholder — analytics sink disabled.")
            return
        if not _BQ_AVAILABLE:
            logger.warning("[BigQuery] google-cloud-bigquery not installed — sink disabled.")
            return

        dataset = os.environ.get("BIGQUERY_DATASET", "sevasetu_events").strip()
        table = os.environ.get("BIGQUERY_TABLE", "need_events").strip()
        document_table = os.environ.get("BIGQUERY_DOCUMENT_TABLE", "document_events").strip()
        severity_table = os.environ.get("BIGQUERY_SEVERITY_TABLE", "severity_events").strip()
        severity_timeseries_table = os.environ.get("BIGQUERY_SEVERITY_TIMESERIES_TABLE", "severity_timeseries").strip()

        try:
            # --- Project B: use explicit analytics key, NOT the Firebase/Project A key ---
            cred_path = os.environ.get("GCP_ANALYTICS_CREDENTIALS_PATH", "").strip() or None
            
            # Configure larger connection pool for BigQuery client
            from google.api_core import gapic_v1
            client_options = gapic_v1.ClientOptions()
            
            if cred_path:
                from google.oauth2 import service_account as _sa
                _creds = _sa.Credentials.from_service_account_file(
                    cred_path,
                    scopes=["https://www.googleapis.com/auth/bigquery"],
                )
                # Create client with custom options for connection pooling
                self._client = bigquery.Client(
                    project=project, 
                    credentials=_creds,
                    client_options=client_options
                )
                logger.info("[BigQuery] Using explicit credentials: %s", cred_path)
            else:
                # Fall back to Application Default Credentials
                logger.warning(
                    "[BigQuery] GCP_ANALYTICS_CREDENTIALS_PATH not set — using ADC. "
                    "This may use the wrong project's credentials."
                )
                self._client = bigquery.Client(
                    project=project,
                    client_options=client_options
                )
            
            # Configure HTTP client connection pooling (at urllib3 level)
            from google.api_core.gapic_v1.client_info import ClientInfo
            from google.api_core.transport.requests import Request
            
            # Increase connection pool at urllib3 level
            import urllib3
            urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
            http_client = Request()
            # Set connection pool size via http client configuration
            if hasattr(http_client, 'session'):
                if hasattr(http_client.session, 'adapters'):
                    for adapter in http_client.session.adapters.values():
                        if hasattr(adapter, 'poolmanager'):
                            adapter.poolmanager.connection_pool_kw['maxsize'] = 100

            self._table_ref = f"{project}.{dataset}.{table}"
            self._document_table_ref = f"{project}.{dataset}.{document_table}"
            self._severity_table_ref = f"{project}.{dataset}.{severity_table}"
            self._severity_timeseries_table_ref = f"{project}.{dataset}.{severity_timeseries_table}"
            self._ensure_table(dataset, table, schema_config=_SCHEMA)
            self._ensure_table(
                dataset,
                document_table,
                schema_config=_DOCUMENT_SCHEMA,
                partition_field="extraction_timestamp",
            )
            self._ensure_table(
                dataset,
                severity_table,
                schema_config=_SEVERITY_SCHEMA,
                partition_field="timestamp",
            )
            self._ensure_table(
                dataset,
                severity_timeseries_table,
                schema_config=_SEVERITY_TIMESERIES_SCHEMA,
                partition_field="timestamp",
            )
            self._enabled = True
            logger.info("[BigQuery] Sink ready → %s", self._table_ref)
            logger.info("[BigQuery] Document sink ready → %s", self._document_table_ref)
            logger.info("[BigQuery] Severity sink ready → %s", self._severity_table_ref)
            logger.info("[BigQuery] Severity timeseries sink ready → %s", self._severity_timeseries_table_ref)
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

    # -------------------------------------------------------------------
    # Batch writing system — reduce connection pool contention
    # -------------------------------------------------------------------
    
    async def _flush_events_batch(self) -> None:
        """Flush accumulated events in a single batch insert."""
        if not self._enabled or not self._pending_events.get(self._table_ref):
            return
        
        rows_to_flush = self._pending_events.pop(self._table_ref, [])
        if not rows_to_flush:
            return
            
        try:
            errors: List[dict] = await asyncio.get_event_loop().run_in_executor(
                self._executor,
                lambda: self._client.insert_rows_json(self._table_ref, rows_to_flush, timeout=30)
            )
            if errors:
                logger.error("[BigQuery] Batch insert errors (%d rows): %s", len(rows_to_flush), errors[:3])
            else:
                logger.info("[BigQuery] Flushed %d event rows", len(rows_to_flush))
        except Exception as exc:
            logger.error("[BigQuery] Batch flush failed: %s", exc)

    async def _flush_docs_batch(self) -> None:
        """Flush accumulated document events."""
        if not self._enabled or not self._pending_docs:
            return
            
        rows_to_flush = self._pending_docs.copy()
        self._pending_docs.clear()
        
        try:
            errors: List[dict] = await asyncio.get_event_loop().run_in_executor(
                self._executor,
                lambda: self._client.insert_rows_json(self._document_table_ref, rows_to_flush, timeout=30)
            )
            if errors:
                logger.error("[BigQuery] Document batch insert errors (%d rows): %s", len(rows_to_flush), errors[:3])
            else:
                logger.info("[BigQuery] Flushed %d document rows", len(rows_to_flush))
        except Exception as exc:
            logger.error("[BigQuery] Document batch flush failed: %s", exc)

    async def _flush_severity_batch(self) -> None:
        """Flush accumulated severity events."""
        if not self._enabled or not self._pending_severity:
            return
            
        rows_to_flush = self._pending_severity.copy()
        self._pending_severity.clear()
        
        try:
            errors: List[dict] = await asyncio.get_event_loop().run_in_executor(
                self._executor,
                lambda: self._client.insert_rows_json(self._severity_table_ref, rows_to_flush, timeout=30)
            )
            if errors:
                logger.error("[BigQuery] Severity batch insert errors (%d rows): %s", len(rows_to_flush), errors[:3])
        except Exception as exc:
            logger.error("[BigQuery] Severity batch flush failed: %s", exc)

    async def _flush_timeseries_batch(self) -> None:
        """Flush accumulated timeseries events."""
        if not self._enabled or not self._pending_timeseries:
            return
            
        rows_to_flush = self._pending_timeseries.copy()
        self._pending_timeseries.clear()
        
        try:
            errors: List[dict] = await asyncio.get_event_loop().run_in_executor(
                self._executor,
                lambda: self._client.insert_rows_json(self._severity_timeseries_table_ref, rows_to_flush, timeout=30)
            )
            if errors:
                logger.error("[BigQuery] Timeseries batch insert errors (%d rows): %s", len(rows_to_flush), errors[:3])
        except Exception as exc:
            logger.error("[BigQuery] Timeseries batch flush failed: %s", exc)

    async def _schedule_flush(self, batch_key: str, flush_func) -> None:
        """Schedule a flush task or reset existing one."""
        # Cancel existing task if any
        if batch_key in self._batch_tasks:
            self._batch_tasks[batch_key].cancel()
        
        async def delayed_flush():
            await asyncio.sleep(self._batch_timeout_sec)
            await flush_func()
        
        self._batch_tasks[batch_key] = asyncio.create_task(delayed_flush())

    # Public API
    async def append(self, event: "UnifiedIngestionEvent", score: float) -> None:
        """
        Queue event for batch insertion into BigQuery (non-blocking).
        Returns immediately; flush happens periodically or when batch is full.
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
            # Add to pending batch
            if self._table_ref not in self._pending_events:
                self._pending_events[self._table_ref] = []
            
            self._pending_events[self._table_ref].append(row)
            logger.debug("[BigQuery] Queued event %s (batch size: %d)", event.id, len(self._pending_events[self._table_ref]))
            
            # Flush if batch is full
            if len(self._pending_events[self._table_ref]) >= self._batch_size:
                await self._flush_events_batch()
            else:
                # Schedule flush if not already scheduled
                await self._schedule_flush("events", self._flush_events_batch)
                
        except Exception as exc:
            logger.error("[BigQuery] Failed to queue event %s: %s", event.id, exc)

    async def append_document_event(self, event: "UnifiedIngestionEvent", score: float) -> None:
        """Queue document event for batch insertion into the partitioned document table."""
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
            self._pending_docs.append(row)
            logger.debug("[BigQuery] Queued document event %s (batch size: %d)", event.id, len(self._pending_docs))
            
            if len(self._pending_docs) >= self._batch_size:
                await self._flush_docs_batch()
            else:
                await self._schedule_flush("docs", self._flush_docs_batch)
        except Exception as exc:
            logger.error("[BigQuery] Failed to queue document event %s: %s", event.id, exc)

    async def append_severity_event(self, event: "UnifiedIngestionEvent", severity_payload: dict) -> None:
        """Queue severity event for batch insertion."""
        if not self._enabled or not self._severity_table_ref:
            return

        row = {
            "event_id": event.id,
            "region_id": event.geohash or "",
            "need_type": event.need_type,
            "timestamp": event.timestamp.isoformat(),
            "source": event.source,
            "lineage": (event.metadata or {}).get("lineage", "event"),
            "severity_acute": severity_payload.get("severity_acute"),
            "severity_chronic": severity_payload.get("severity_chronic"),
            "composite_urgency": severity_payload.get("composite_urgency"),
            "reliability_score": severity_payload.get("reliability_score"),
            "source_reliability": severity_payload.get("source_reliability"),
            "detection_confidence": severity_payload.get("detection_confidence"),
            "trend_bonus": severity_payload.get("trend_bonus"),
            "gap_penalty": severity_payload.get("gap_penalty"),
            "classification": severity_payload.get("classification"),
            "recommended_response_time": severity_payload.get("recommended_response_time"),
        }

        try:
            self._pending_severity.append(row)
            logger.debug("[BigQuery] Queued severity event %s (batch size: %d)", event.id, len(self._pending_severity))
            
            if len(self._pending_severity) >= self._batch_size:
                await self._flush_severity_batch()
            else:
                await self._schedule_flush("severity", self._flush_severity_batch)
        except Exception as exc:
            logger.error("[BigQuery] Failed to queue severity event %s: %s", event.id, exc)

    async def append_severity_timeseries(self, event: "UnifiedIngestionEvent", severity_payload: dict) -> None:
        """Queue timeseries event for batch insertion."""
        if not self._enabled or not self._severity_timeseries_table_ref:
            return

        row = {
            "region_id": event.geohash or "",
            "need_type": event.need_type,
            "event_id": event.id,
            "timestamp": event.timestamp.isoformat(),
            "severity_value": severity_payload.get("composite_urgency"),
            "classification": severity_payload.get("classification"),
            "feedback": (event.metadata or {}).get("ground_truth_feedback"),
        }

        try:
            self._pending_timeseries.append(row)
            logger.debug("[BigQuery] Queued timeseries event %s (batch size: %d)", event.id, len(self._pending_timeseries))
            
            if len(self._pending_timeseries) >= self._batch_size:
                await self._flush_timeseries_batch()
            else:
                await self._schedule_flush("timeseries", self._flush_timeseries_batch)
        except Exception as exc:
            logger.error("[BigQuery] Failed to queue timeseries event %s: %s", event.id, exc)

    async def flush_all(self) -> None:
        """Flush all pending batches (called on shutdown)."""
        logger.info("[BigQuery] Flushing all pending batches...")
        try:
            await self._flush_events_batch()
            await self._flush_docs_batch()
            await self._flush_severity_batch()
            await self._flush_timeseries_batch()
            logger.info("[BigQuery] All batches flushed")
        except Exception as exc:
            logger.error("[BigQuery] Error during flush_all: %s", exc)
    
    def shutdown(self) -> None:
        """Shutdown the executor pool."""
        if self._executor:
            self._executor.shutdown(wait=True)
            logger.info("[BigQuery] Executor pool shut down")


# Global singleton
bigquery_store = BigQueryStore()
