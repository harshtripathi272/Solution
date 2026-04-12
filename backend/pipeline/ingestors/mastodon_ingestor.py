"""
Mastodon Social Ingestor — Decentralized real-time social signals.

Monitors the Mastodon social network (free, no API key required for public data)
for crisis-related posts. Mastodon is ideal for GTSHD because:
  - No paid API tier needed
  - Public timeline freely accessible
  - Used by humanitarian/disaster relief communities
  - Hashtag-driven discovery enables targeted monitoring

Focuses on:
  - Verified accounts (disaster management, NGOs)
  - Specific hashtags (#IndiaFloods, #DisasterAlert, etc.)
  - Community-sourced crisis reports
"""

from __future__ import annotations

import hashlib
import logging
from datetime import datetime, timezone
from urllib.parse import quote

import httpx

from pipeline.core.schemas import IngestionLocation, UnifiedIngestionEvent, NeedTemporality
from .base import PeriodicIngestor

logger = logging.getLogger(__name__)

# Fallback coordinates
FALLBACK_INDIA_COORDS = (20.5937, 78.9629)

# Key Mastodon instances for humanitarian/disaster relief communities
MASTODON_INSTANCES = [
    "bihar.social",    # Bihar-origin focused instance (small but strategic)
    "india.goonj.xyz", # India-focused social issues and civic threads
    "mastodon.social",  # Main instance, has disaster relief accounts
    "pixelfed.social",  # Image-centric, sometimes used for disaster photography
    "techhub.social",   # Tech/humanitarian projects
]

# Hashtags to monitor for crisis detection
CRISIS_HASHTAGS = [
    "DisasterAlert",
    "IndiaFloods",
    "CycloneWarning",
    "EarthquakeAlert",
    "HealthCrisis",
    "CommunityHelp",
    "DisasterRelief",
    "CrisisResponse",
    "EmergencyHelp",
    "HumanitarianAid",
    "BiharSahayata",
    "BiharBaadh",
    "PatnaSamachar",
    "HamarChhattisgarh",
    "ChhattisgarhiSamachar",
    "JharkhandSahayata",
    "RanchiSamachar",
    "SanthalSahayata",
    "AdivasiSahayata",
]

# Keywords indicating actionable crisis information
CRISIS_KEYWORDS = {
    "flood": ["flood", "waterlogging", "inundation", "bund", "baadh", "kosi", "gandak"],
    "cyclone": ["cyclone", "hurricane", "typhoon", "storm"],
    "earthquake": ["earthquake", "seismic", "tremor"],
    "medical": ["disease", "outbreak", "health crisis", "hospital", "ambulance"],
    "displacement": ["displacement", "relocation", "refugee"],
    "food": ["hunger", "famine", "ration", "pds"],
    "water": ["water", "drinking water", "sanitation", "wash", "handpump"],
    "other": [
        "bihar",
        "patna",
        "muzaffarpur",
        "jharkhand",
        "ranchi",
        "dhanbad",
        "chhattisgarh",
        "raipur",
        "bastar",
        "surguja",
        "adivasi",
        "santhali",
    ],
}

REGION_HINT_KEYWORDS = {
    "bihar": ["bihar", "patna", "muzaffarpur", "darbhanga", "mithila", "bhojpuri"],
    "jharkhand": ["jharkhand", "ranchi", "dhanbad", "jamshedpur", "santhal", "santhali", "adivasi"],
    "chhattisgarh": ["chhattisgarh", "raipur", "bastar", "surguja", "jagdalpur", "chhattisgarhi", "hamar"],
}


class MastodonIngestor(PeriodicIngestor):
    """
    Real-time social signal ingestion from Mastodon.
    Uses public API (no authentication required).
    """

    def __init__(self, interval_seconds: int = 600, instances: list[str] | None = None):
        """
        Args:
            interval_seconds: Poll interval (default: 10 min = 600s)
            instances: Mastodon instances to monitor
        """
        super().__init__(name="MastodonIngestor", interval_seconds=interval_seconds)
        self.instances = instances or MASTODON_INSTANCES
        self._seen_statuses: set[str] = set()

    async def fetch_events(self) -> list[UnifiedIngestionEvent]:
        """
        Fetches crisis-related posts from Mastodon public timelines.
        """
        events: list[UnifiedIngestionEvent] = []

        for instance in self.instances:
            try:
                instance_events = await self._fetch_instance_timeline(instance)
                events.extend(instance_events)
            except Exception as exc:
                logger.warning("[Mastodon] Failed to fetch from %s: %s", instance, exc)
                continue

        logger.info("[Mastodon] normalized %d events from %d instances", len(events), len(self.instances))
        return events

    async def _fetch_instance_timeline(self, instance: str) -> list[UnifiedIngestionEvent]:
        """
        Fetch posts from a specific Mastodon instance using hashtag timelines.
        """
        events: list[UnifiedIngestionEvent] = []

        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                posts: list[dict] = []

                # Pull from hashtag timelines because many instances restrict public timeline access.
                for hashtag in CRISIS_HASHTAGS[:5]:
                    tag_url = f"https://{instance}/api/v1/timelines/tag/{quote(hashtag)}"
                    resp = await client.get(tag_url, params={"limit": 20})
                    if resp.status_code >= 400:
                        logger.debug(
                            "[Mastodon] tag timeline unavailable on %s for #%s (status=%s)",
                            instance,
                            hashtag,
                            resp.status_code,
                        )
                        continue
                    posts.extend(resp.json() or [])

                for post in posts:
                    status_id = post.get("id", "")
                    if status_id in self._seen_statuses:
                        continue

                    content = post.get("content", "").lower()
                    content_plain = self._strip_html(content)

                    # Check if post contains crisis-related hashtags or keywords
                    hashtags = [tag.get("name", "").lower() for tag in post.get("tags", [])]
                    has_crisis_tag = any(tag in [h.lower() for h in CRISIS_HASHTAGS] for tag in hashtags)

                    # Extract crisis type from keywords
                    need_type = self._classify_crisis(content_plain)
                    region_hints = self._infer_region_hints(content_plain, hashtags)

                    # Only ingest posts with crisis signals and tags/keywords
                    if not (has_crisis_tag or need_type):
                        continue

                    self._seen_statuses.add(status_id)

                    # Parse timestamp
                    timestamp_str = post.get("created_at", "")
                    timestamp = self._parse_iso_timestamp(timestamp_str)

                    # Extract account info
                    account = post.get("account", {})
                    account_name = account.get("username", "unknown")
                    account_verified = account.get("noindex", False) == False  # Rough indicator

                    # Determine severity
                    severity = self._determine_severity(content_plain)
                    confidence = 0.6 if account_verified else 0.5

                    # Use fallback coordinates (refined by NER)
                    lat, lon = FALLBACK_INDIA_COORDS

                    # Create unique event ID
                    raw_id = f"mastodon:{instance}:{status_id}"
                    event_id = hashlib.sha256(raw_id.encode()).hexdigest()[:24]

                    event = UnifiedIngestionEvent(
                        id=f"MST-{event_id}",
                        source="MASTODON",
                        timestamp=timestamp,
                        location=IngestionLocation(latitude=lat, longitude=lon),
                        need_type=need_type or "other",
                        severity=severity,
                        confidence_score=confidence,
                        description=content_plain[:200],
                        need_temporality=NeedTemporality.ACUTE,
                        metadata={
                            "mastodon_instance": instance,
                            "account": account_name,
                            "account_verified": account_verified,
                            "hashtags": hashtags,
                            "url": post.get("url", ""),
                            "replies_count": post.get("replies_count", 0),
                            "reblogs_count": post.get("reblogs_count", 0),
                            "favorites_count": post.get("favourites_count", 0),
                            "region_hints": region_hints,
                        },
                    )
                    events.append(event)

        except Exception as exc:
            logger.error("[Mastodon] Failed to fetch tag timelines from %s: %s", instance, exc)

        return events

    def _classify_crisis(self, text: str) -> str | None:
        """Classify crisis type based on keywords."""
        for need_type, keywords in CRISIS_KEYWORDS.items():
            if any(kw in text for kw in keywords):
                return need_type
        return None

    def _infer_region_hints(self, text: str, hashtags: list[str]) -> list[str]:
        """Infer likely state-level region hints from post text and tags."""
        searchable = f"{text} {' '.join(hashtags)}"
        hints: list[str] = []
        for region, keywords in REGION_HINT_KEYWORDS.items():
            if any(keyword in searchable for keyword in keywords):
                hints.append(region)
        return hints

    def _determine_severity(self, text: str) -> str:
        """Determine severity from text cues."""
        critical_words = ["emergency", "disaster", "critical", "urgent", "deaths", "dead"]
        high_words = ["alert", "warning", "danger", "affected", "impact"]

        if any(word in text for word in critical_words):
            return "red"
        elif any(word in text for word in high_words):
            return "orange"
        else:
            return "green"

    @staticmethod
    def _strip_html(text: str) -> str:
        """Remove basic HTML tags from Mastodon content."""
        import re
        return re.sub(r"<[^>]+>", "", text).strip()

    @staticmethod
    def _parse_iso_timestamp(timestamp_str: str) -> datetime:
        """Parse ISO 8601 timestamps from Mastodon."""
        try:
            # Mastodon returns ISO 8601 format: 2024-03-15T10:30:00.000Z
            dt = datetime.fromisoformat(timestamp_str.replace("Z", "+00:00"))
            return dt.astimezone(timezone.utc)
        except (ValueError, TypeError):
            logger.warning("[Mastodon] Failed to parse timestamp: %s", timestamp_str)
            return datetime.now(timezone.utc)
