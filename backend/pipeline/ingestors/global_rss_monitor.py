"""
Global RSS Monitor — Real-time community-focused article discovery.

Uses free Google News RSS feeds to monitor for crisis events in specific
geographic regions and communities, then deep-scrapes articles using
newspaper3k to extract full content for NER processing.

Incorporates community-specific keywords beyond generic crisis terms to
catch niche local issues (e.g., "bund breach", "PDS shortage", "Gram Panchayat").
"""

from __future__ import annotations

import hashlib
import logging
from datetime import datetime, timezone
from urllib.parse import urlencode

import feedparser
from newspaper import Article

from pipeline.core.schemas import IngestionLocation, UnifiedIngestionEvent
from .base import PeriodicIngestor

logger = logging.getLogger(__name__)

# Fallback coordinates (center of India)
FALLBACK_INDIA_COORDS = (20.5937, 78.9629)

# Region-specific keywords for hyper-local crisis detection
COMMUNITY_KEYWORDS = {
    "assam": ["bund", "waterway", "tea garden", "Assam"],
    "odisha": ["panchayat", "coastal", "paddy", "Odisha", "Bhubaneswar"],
    "bihar": ["mithila", "darbhanga", "muzaffarpur", "embankment", "Bihar"],
    "maharashtra": ["sugarcane", "farmer", "reservoir", "watershed", "Maharashtra"],
    "karnataka": ["irrigation", "drought", "coffee", "Karnataka"],
    "andhra_pradesh": ["agricultural", "mining", "Andhra", "Pradesh"],
    "general": ["health", "food", "water", "shelter", "livelihood", "displacement"],
}

# Crisis classification keywords
CRISIS_KEYWORDS = {
    "flood": ["flood", "waterlogging", "inundation", "deluge", "submerged", "bund", "embankment breach"],
    "cyclone": ["cyclone", "hurricane", "typhoon", "windstorm", "tropical storm"],
    "earthquake": ["earthquake", "seismic", "tremor", "aftershock", "quake"],
    "fire": ["fire", "blaze", "wildfire", "forest fire", "conflagration"],
    "drought": ["drought", "dry", "drying", "water scarcity", "shortage"],
    "landslide": ["landslide", "mudslide", "soil slip", "debris flow"],
    "medical": ["disease", "outbreak", "covid", "dengue", "malaria", "health crisis", "epidemic"],
    "food": ["hunger", "famine", "crop failure", "PDS", "ration", "food shortage"],
    "displacement": ["displacement", "relocation", "eviction", "rehabilitation", "refugee"],
    "water": ["drinking water", "sanitation", "WASH", "well", "handpump", "water supply"],
}


class GlobalRSSMonitor(PeriodicIngestor):
    """
    Real-time RSS-based monitor for community crises across India.
    Queries Google News for specific regions/keywords and deep-scrapes results.
    """

    GOOGLE_NEWS_RSS = "https://news.google.com/rss/search"

    def __init__(self, interval_seconds: int = 1800, regions: list[str] | None = None, max_articles: int = 20):
        """
        Args:
            interval_seconds: How often to poll (default: 30 min = 1800s for free tier)
            regions: List of regions to monitor (default: all major Indian states)
            max_articles: Max articles to process per cycle
        """
        super().__init__(name="GlobalRSSMonitor", interval_seconds=interval_seconds)
        self.regions = regions or list(COMMUNITY_KEYWORDS.keys())
        self.max_articles = max_articles
        self._article_cache: set[str] = set()  # Cache article URLs to avoid re-scraping

    async def fetch_events(self) -> list[UnifiedIngestionEvent]:
        """
        Fetches articles from Google News RSS feeds for community-specific queries.
        """
        events: list[UnifiedIngestionEvent] = []

        for region in self.regions:
            try:
                region_events = await self._fetch_region_articles(region)
                events.extend(region_events)
            except Exception as exc:
                logger.warning("[GlobalRSSMonitor] Failed to fetch %s: %s", region, exc)
                continue

        logger.info("[GlobalRSSMonitor] normalized %d events from %d regions", len(events), len(self.regions))
        return events

    async def _fetch_region_articles(self, region: str) -> list[UnifiedIngestionEvent]:
        """Fetch articles for a specific region using Google News RSS."""
        events: list[UnifiedIngestionEvent] = []
        keywords = COMMUNITY_KEYWORDS.get(region, [])

        if not keywords:
            return []

        # Build search query with region name + crisis keywords
        query_parts = [region] + keywords[:3]  # Limit to 3 keywords per query to stay within URL limits
        query = " ".join(query_parts)

        params = {
            "q": query,
            "hl": "en-IN",
            "gl": "IN",
            "ceid": "IN:en",
        }

        url = f"{self.GOOGLE_NEWS_RSS}?{urlencode(params)}"

        try:
            feed_data = feedparser.parse(url)
            entries = feed_data.get("entries", [])

            for entry in entries[: self.max_articles]:
                article_url = entry.get("link", "")
                if not article_url or article_url in self._article_cache:
                    continue

                self._article_cache.add(article_url)

                try:
                    # Deep-scrape the article using newspaper3k
                    article = Article(article_url)
                    article.download()
                    article.parse()

                    text = (article.title or "") + " " + (article.text or "")
                    text_lower = text.lower()

                    # Classify crisis type
                    need_type = self._classify_crisis(text_lower)
                    if not need_type:
                        continue

                    # Parse timestamp
                    published = entry.get("published", "")
                    timestamp = self._parse_timestamp(published)

                    # Determine severity
                    severity = self._determine_severity(text_lower)
                    confidence = self._calculate_confidence(text_lower, region)

                    # Use fallback coordinates for now (refined by NER in unified pipeline)
                    lat, lon = FALLBACK_INDIA_COORDS

                    # Create unique event ID
                    raw_id = f"rss:{hashlib.md5(article_url.encode()).hexdigest()}"
                    event_id = hashlib.sha256(raw_id.encode()).hexdigest()[:24]

                    event = UnifiedIngestionEvent(
                        id=f"RSS-{event_id}",
                        source="GLOBAL_RSS",
                        timestamp=timestamp,
                        location=IngestionLocation(latitude=lat, longitude=lon),
                        need_type=need_type,
                        severity=severity,
                        confidence_score=confidence,
                        description=article.title or entry.get("title", ""),
                        metadata={
                            "url": article_url,
                            "region": region,
                            "source_name": entry.get("source", {}).get("title", "Google News"),
                            "article_text": text[:500],  # Store snippet for debugging
                        },
                    )
                    events.append(event)

                except Exception as article_exc:
                    logger.debug("[GlobalRSSMonitor] Failed to scrape %s: %s", article_url, article_exc)
                    continue

        except Exception as exc:
            logger.error("[GlobalRSSMonitor] RSS parse failed for %s: %s", region, exc)

        return events

    def _classify_crisis(self, text: str) -> str | None:
        """
        Classify crisis type based on keywords.
        Returns need_type string or None if no match.
        """
        for need_type, keywords in CRISIS_KEYWORDS.items():
            if any(kw in text for kw in keywords):
                return need_type
        return None

    def _determine_severity(self, text: str) -> str:
        """Determine severity level based on language cues."""
        critical_words = ["dead", "death", "deaths", "critical", "severe", "emergency", "disaster", "casualties"]
        high_words = ["injured", "damage", "extensive", "widespread", "alert", "warning"]

        if any(word in text for word in critical_words):
            return "red"
        elif any(word in text for word in high_words):
            return "orange"
        else:
            return "green"

    def _calculate_confidence(self, text: str, region: str) -> float:
        """
        Calculate confidence score based on:
        - Presence of specific community keywords
        - Article detail level
        - Region match
        """
        score = 0.5  # Base score

        # Check community-specific keywords
        region_keywords = COMMUNITY_KEYWORDS.get(region, [])
        community_match = sum(1 for kw in region_keywords if kw in text)
        score += min(0.2, community_match * 0.05)

        # Check detail level (longer text = more likely detailed reporting)
        if len(text) > 1000:
            score += 0.1
        elif len(text) > 500:
            score += 0.05

        return min(0.95, score)

    @staticmethod
    def _parse_timestamp(timestamp_str: str) -> datetime:
        """Parse various timestamp formats from RSS feeds."""
        try:
            from email.utils import parsedate_to_datetime
            return parsedate_to_datetime(timestamp_str).astimezone(timezone.utc)
        except (TypeError, ValueError):
            return datetime.now(timezone.utc)
