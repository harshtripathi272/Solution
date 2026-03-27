import asyncio
import logging
import os
from pathlib import Path

from pipeline.pubsub_mock import broker
from pipeline.schemas import UnifiedIngestionEvent, to_crisis_event
from .gdacs import GDACSIngestor
from .ndma_rss import NDMARSSIngestor
from .news_api import IndiaNewsIngestor
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
        self._enricher = OverpassEnricher() if self._enrich_osm else None

        self._ingestors = [
            GDACSIngestor(interval_seconds=int(os.getenv("INGEST_GDACS_INTERVAL", "600"))),
            NDMARSSIngestor(
                feed_url=os.getenv("INGEST_NDMA_RSS_URL", "https://sachet.ndma.gov.in/cap_public_website/rss/rss_india.xml"),
                interval_seconds=int(os.getenv("INGEST_NDMA_INTERVAL", "300")),
            ),
            OpenWeatherIngestor(
                api_key=os.getenv("OPENWEATHER_API_KEY", ""),
                interval_seconds=int(os.getenv("INGEST_WEATHER_INTERVAL", "420")),
            ),
            IndiaNewsIngestor(
                news_api_key=os.getenv("NEWS_API_KEY", ""),
                newsdata_api_key=os.getenv("NEWS_DATA_API_KEY", ""),
                interval_seconds=int(os.getenv("INGEST_NEWS_INTERVAL", "420")),
            ),
        ]
        self._survey_loader = SurveyDataLoader()

    def start(self):
        for ingestor in self._ingestors:
            self._tasks.append(asyncio.create_task(self._run_worker(ingestor)))
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
            if event.confidence_score >= 0.75:
                await broker.publish("official-alerts", to_crisis_event(event, tier=1, verified=True))
            else:
                await broker.publish("citizen-reports", to_crisis_event(event, tier=2, verified=False))

        logger.info("[IngestionManager] On-demand survey ingestion published %d events", len(events))
        return len(events)

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
