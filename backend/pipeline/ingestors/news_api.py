import hashlib
import logging
from datetime import datetime, timezone

from pipeline.core.schemas import IngestionLocation, UnifiedIngestionEvent
from pipeline.processing.community_resolver import community_resolver
from .base import PeriodicIngestor

logger = logging.getLogger(__name__)


KEYWORDS = ["flood", "earthquake", "health", "shortage", "cyclone", "fire"]

for comm in community_resolver.communities:
    KEYWORDS.extend(comm.get("keywords", []))

FALLBACK_INDIA_COORDS = (20.5937, 78.9629)


class IndiaNewsIngestor(PeriodicIngestor):
    NEWSAPI_URL = "https://newsapi.org/v2/everything"
    NEWSDATA_URL = "https://newsdata.io/api/1/news"

    def __init__(self, news_api_key: str, newsdata_api_key: str, interval_seconds: int = 420):
        super().__init__(name="IndiaNews", interval_seconds=interval_seconds)
        self.news_api_key = news_api_key
        self.newsdata_api_key = newsdata_api_key
        self.limit=5

    async def fetch_events(self) -> list[UnifiedIngestionEvent]:
        if not self.news_api_key and not self.newsdata_api_key:
            logger.warning("[IndiaNews] No API key configured. Skipping worker iteration.")
            return []

        events: list[UnifiedIngestionEvent] = []
        if self.news_api_key:
            events.extend(await self._fetch_newsapi())
        if self.newsdata_api_key:
            events.extend(await self._fetch_newsdata())

        logger.info("[IndiaNews] normalized %d events", len(events))
        return events

    async def _fetch_newsapi(self) -> list[UnifiedIngestionEvent]:
        query = " OR ".join(KEYWORDS)
        data = await self.request_json(
            self.NEWSAPI_URL,
            params={
                "q": query,
                "language": "en",
                "sortBy": "publishedAt",
                "pageSize": self.limit,
            },
            headers={"X-Api-Key": self.news_api_key},
        )

        events: list[UnifiedIngestionEvent] = []
        for article in data.get("articles", []):
            title = str(article.get("title", ""))
            description = str(article.get("description", ""))
            text = f"{title} {description}".lower()
            if not any(k in text for k in KEYWORDS):
                continue

            timestamp = self._parse_timestamp(article.get("publishedAt"))
            
            community_match = community_resolver.resolve(text)
            community_id = None
            if community_match:
                lat, lon = community_match["latitude"], community_match["longitude"]
                community_id = community_match["id"]
            else:
                lat, lon = FALLBACK_INDIA_COORDS
                
            need_type = self._need_type(text)
            severity = "high" if any(x in text for x in ["severe", "critical", "deaths"]) else "moderate"
            source_name = (article.get("source") or {}).get("name", "NewsAPI")

            raw_id = f"newsapi:{source_name}:{title}:{int(timestamp.timestamp())}"
            event_id = hashlib.sha256(raw_id.encode()).hexdigest()[:24]
            events.append(
                UnifiedIngestionEvent(
                    id=f"NEWS-{event_id}",
                    source="NEWS_API",
                    timestamp=timestamp,
                    location=IngestionLocation(latitude=lat, longitude=lon),
                    need_type=need_type,
                    severity=severity,
                    confidence_score=0.6,
                    description=title,
                    metadata={
                        "description": description,
                        "url": article.get("url"),
                        "region": "india",
                        "publisher": source_name,
                    },
                )
            )
            if community_id:
                events[-1].metadata["community_id"] = community_id
                
        return events

    async def _fetch_newsdata(self) -> list[UnifiedIngestionEvent]:
        query = " OR ".join(KEYWORDS)
        data = await self.request_json(
            self.NEWSDATA_URL,
            params={
                "apikey": self.newsdata_api_key,
                "country": "in",
                "language": "en",
                "q": query,
            },
        )

        events: list[UnifiedIngestionEvent] = []
        for article in data.get("results", []):
            title = str(article.get("title", ""))
            description = str(article.get("description", ""))
            text = f"{title} {description}".lower()
            if not any(k in text for k in KEYWORDS):
                continue

            timestamp = self._parse_timestamp(article.get("pubDate"))
            
            community_match = community_resolver.resolve(text)
            community_id = None
            if community_match:
                lat, lon = community_match["latitude"], community_match["longitude"]
                community_id = community_match["id"]
            else:
                lat, lon = FALLBACK_INDIA_COORDS
                
            need_type = self._need_type(text)
            severity = "high" if any(x in text for x in ["severe", "critical", "deaths"]) else "moderate"

            raw_id = f"newsdata:{title}:{int(timestamp.timestamp())}"
            event_id = hashlib.sha256(raw_id.encode()).hexdigest()[:24]
            events.append(
                UnifiedIngestionEvent(
                    id=f"NEWSDATA-{event_id}",
                    source="NEWSDATA_IO",
                    timestamp=timestamp,
                    location=IngestionLocation(latitude=lat, longitude=lon),
                    need_type=need_type,
                    severity=severity,
                    confidence_score=0.6,
                    description=title,
                    metadata={
                        "description": description,
                        "url": article.get("link"),
                        "region": "india",
                    },
                )
            )
            if community_id:
                events[-1].metadata["community_id"] = community_id
                
        return events

    def _need_type(self, text: str) -> str:
        if "earthquake" in text:
            return "earthquake"
        if "flood" in text or "rain" in text:
            return "flood"
        if "cyclone" in text or "storm" in text:
            return "cyclone"
        if "health" in text or "outbreak" in text or "medical" in text:
            return "medical"
        if "fire" in text or "wildfire" in text:
            return "fire"
        return "other"

    def _parse_timestamp(self, raw: str | None) -> datetime:
        if raw:
            try:
                value = raw.replace("Z", "+00:00")
                dt = datetime.fromisoformat(value)
                if dt.tzinfo is None:
                    dt = dt.replace(tzinfo=timezone.utc)
                return dt.astimezone(timezone.utc)
            except Exception:
                pass
        return self.now_utc()
