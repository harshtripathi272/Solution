import asyncio
import logging
import os
from pathlib import Path

from pipeline.core.pubsub import broker
from pipeline.core.schemas import UnifiedIngestionEvent
from .gdacs import GDACSIngestor
from .ndma_rss import NDMARSSIngestor
from .news_api import IndiaNewsIngestor
from .document_ingestion_service import document_ingestion_service
from .ngo_reports import NGOReportsIngestor
from .openweather import OpenWeatherIngestor
from .osm_overpass import OverpassEnricher
from .survey_loader import SurveyDataLoader
from dotenv import load_dotenv

load_dotenv()
logger = logging.getLogger(__name__)


class IngestionManager:
    def __init__(self):
        self._tasks: list[asyncio.Task] = []
        self._enrich_osm = os.getenv("INGEST_ENRICH_OSM", "false").lower() == "true"
        self._enable_ngo = os.getenv("INGEST_NGO_ENABLED", "true").lower() == "true"
        self._enable_document_stream = os.getenv("INGEST_DOCUMENT_STREAM_ENABLED", "false").lower() == "true"
        self._document_interval = int(os.getenv("INGEST_DOCUMENT_INTERVAL", "21600"))
        self._document_jsonl_path = os.getenv("INGEST_DOCUMENT_JSONL_PATH", "")
        self._document_max_per_cycle = int(os.getenv("INGEST_DOCUMENT_MAX_PER_CYCLE", "40"))
        self._enricher = OverpassEnricher() if self._enrich_osm else None
        self._ngo_ingestor = NGOReportsIngestor(
            interval_seconds=int(os.getenv("INGEST_NGO_INTERVAL", "21600")),  # 6 hours (prototype-safe)
            max_reports=int(os.getenv("INGEST_NGO_MAX_REPORTS", "80")),
        )

        self._ingestors = [
            GDACSIngestor(interval_seconds=int(os.getenv("INGEST_GDACS_INTERVAL", "60"))),
            # NDMARSSIngestor(
            #     feed_url=os.getenv("INGEST_NDMA_RSS_URL", "https://sachet.ndma.gov.in/cap_public_website/rss/rss_india.xml"),
            #     interval_seconds=int(os.getenv("INGEST_NDMA_INTERVAL", "300")),
            # ),
            # OpenWeatherIngestor(
            #     api_key=os.getenv("OPENWEATHER_API_KEY", ""),
            #     interval_seconds=int(os.getenv("INGEST_WEATHER_INTERVAL", "420")),
            # ),
            # IndiaNewsIngestor(
            #     news_api_key=os.getenv("NEWS_API_KEY", ""),
            #     newsdata_api_key=os.getenv("NEWS_DATA_API_KEY", ""),
            #     interval_seconds=int(os.getenv("INGEST_NEWS_INTERVAL", "420")),
            # ),
        ]
        if self._enable_ngo:
            self._ingestors.append(self._ngo_ingestor)

        self._survey_loader = SurveyDataLoader()

    def start(self):
        for ingestor in self._ingestors:
            self._tasks.append(asyncio.create_task(self._run_worker(ingestor)))

        if self._enable_document_stream and self._document_jsonl_path:
            self._tasks.append(asyncio.create_task(self._run_document_worker()))

        logger.info("[IngestionManager] Started %d ingestion workers", len(self._tasks))

    async def stop(self):
        for task in self._tasks:
            task.cancel()
        self._tasks.clear()

    async def _run_worker(self, ingestor):
        while True:
            try:
                events = await ingestor.fetch_events()
                if self._enricher:
                    events = await self._enrich_events(events)
                await ingestor.publish_events(events)
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                logger.exception("[%s] worker iteration failed: %s", ingestor.name, exc)
            await asyncio.sleep(ingestor.interval_seconds)

    async def ingest_survey_file(self, file_path: str) -> int:
        path = Path(file_path)
        if not path.exists():
            raise FileNotFoundError(f"File not found: {file_path}")

        events = self._survey_loader.load_file(str(path))
        if self._enricher:
            events = await self._enrich_events(events)

        for event in events:
            await broker.publish("ingestion-normalized", event)

        logger.info("[IngestionManager] On-demand survey ingestion published %d events", len(events))
        return len(events)

    async def ingest_ngo_reports_once(self, max_reports: int | None = None) -> int:
        events = await self._ngo_ingestor.fetch_events(max_reports=max_reports)
        if self._enricher:
            events = await self._enrich_events(events)

        for event in events:
            await broker.publish("ingestion-normalized", event)

        logger.info("[IngestionManager] On-demand NGO reports ingestion published %d events", len(events))
        return len(events)

    async def ingest_document_jsonl_once(self, file_path: str, max_documents: int | None = None) -> int:
        if max_documents is not None and max_documents <= 0:
            raise ValueError("max_documents must be positive when provided")

        return await document_ingestion_service.ingest_jsonl(
            file_path=file_path,
            max_documents=max_documents,
        )

    async def _run_document_worker(self):
        while True:
            try:
                await self.ingest_document_jsonl_once(
                    file_path=self._document_jsonl_path,
                    max_documents=self._document_max_per_cycle,
                )
            except FileNotFoundError:
                logger.warning("[DocumentWorker] JSONL path not found: %s", self._document_jsonl_path)
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                logger.exception("[DocumentWorker] iteration failed: %s", exc)

            await asyncio.sleep(self._document_interval)

    async def _enrich_events(self, events: list[UnifiedIngestionEvent]) -> list[UnifiedIngestionEvent]:
        if not self._enricher:
            return events

        enriched: list[UnifiedIngestionEvent] = []
        for event in events:
            infra = await self._enricher.enrich(event.location.latitude, event.location.longitude)
            enriched.append(
                event.model_copy(update={"metadata": {**event.metadata, **infra}})
            )
        return enriched


ingestion_manager = IngestionManager()
