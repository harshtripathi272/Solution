import asyncio
import logging
from abc import ABC, abstractmethod
from datetime import datetime, timezone
from typing import List

import httpx

from pipeline.core.pubsub import broker
from pipeline.core.schemas import UnifiedIngestionEvent, to_crisis_event

logger = logging.getLogger(__name__)


class PeriodicIngestor(ABC):
    def __init__(self, name: str, interval_seconds: int):
        self.name = name
        self.interval_seconds = interval_seconds
        self._seen_ids: set[str] = set()

    async def run_forever(self):
        logger.info("[%s] worker started (interval=%ss)", self.name, self.interval_seconds)
        while True:
            try:
                events = await self.fetch_events()
                await self.publish_events(events)
            except Exception as exc:
                logger.exception("[%s] worker loop failed: %s", self.name, exc)
            await asyncio.sleep(self.interval_seconds)

    async def publish_events(self, events: List[UnifiedIngestionEvent]):
        for event in events:
            if event.id in self._seen_ids:
                continue
            self._seen_ids.add(event.id)

            # All ingestion events now route through the Unified Data Pipeline.
            # The pipeline handles NER, Geocoding, Aggregation, and re-publishing
            # to downstream topics (official-alerts, social-media-raw, etc.)
            await broker.publish("ingestion-normalized", event)

    async def request_json(
        self,
        url: str,
        params: dict | None = None,
        headers: dict | None = None,
        timeout: float = 20.0,
        retries: int = 2,
    ) -> dict:
        for attempt in range(retries + 1):
            try:
                async with httpx.AsyncClient(timeout=timeout) as client:
                    resp = await client.get(url, params=params, headers=headers)
                    resp.raise_for_status()
                    return resp.json()
            except httpx.HTTPStatusError as exc:
                status_code = exc.response.status_code
                # Invalid or missing credentials should not crash worker loops.
                if status_code in {401, 403}:
                    logger.error("[%s] auth failed for %s (status=%s). Skipping this cycle.", self.name, url, status_code)
                    return {}
                # Most 4xx are non-retriable for this cycle (bad params, forbidden endpoints, etc.).
                if 400 <= status_code < 500 and status_code != 429:
                    logger.error("[%s] non-retriable client error for %s (status=%s). Skipping this cycle.", self.name, url, status_code)
                    return {}
                if attempt == retries:
                    raise
                backoff = 1.5 * (attempt + 1)
                logger.warning("[%s] request failed (status=%s), retrying in %.1fs", self.name, status_code, backoff)
                await asyncio.sleep(backoff)
            except Exception as exc:
                if attempt == retries:
                    raise
                backoff = 1.5 * (attempt + 1)
                logger.warning("[%s] request failed (%s), retrying in %.1fs", self.name, exc, backoff)
                await asyncio.sleep(backoff)
        return {}

    @staticmethod
    def now_utc() -> datetime:
        return datetime.now(timezone.utc)

    @abstractmethod
    async def fetch_events(self) -> List[UnifiedIngestionEvent]:
        raise NotImplementedError
