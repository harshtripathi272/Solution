# Real-Time Community Crisis Ingestion Architecture

## Overview

This document describes the free, real-time crisis monitoring system added to GTSHD. Instead of relying on expensive paid APIs, the system uses three complementary free sources to achieve 24/7 automated crisis detection:

1. **GlobalRSSMonitor** — Google News RSS feeds filtered for community-specific keywords
2. **MastodonIngestor** — Decentralized social network for real-time humanitarian signals
3. **NGOReportsIngestor** — Existing Scrapy-based periodic web scraper (kept as is)

## Architecture

### Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                   FREE REAL-TIME SOURCES                        │
├────────────────────┬──────────────────────┬────────────────────┤
│ GlobalRSSMonitor   │ MastodonIngestor     │ NGOReportsIngestor │
│ (Google News RSS)  │ (Social Network)     │ (Web Scraper)      │
│ Interval: 30min    │ Interval: 10min      │ Interval: 6hours   │
└────────┬───────────┴──────────┬───────────┴────────┬────────────┘
         │ Normalized Events    │                    │
         │ (UnifiedIngestionEvent)                   │
         └────────────┬─────────────────────────────┘
                      │
          ┌───────────▼──────────────┐
          │  Ingestion Manager       │
          │  - Deduplication         │
          │  - Event enrichment      │
          └───────────┬──────────────┘
                      │
          ┌───────────▼──────────────────────────┐
          │   Unified Data Pipeline              │
          │  ┌─────────────────────────────────┐ │
          │  │ 1. Extraction Strategy Router   │ │
          │  │    (NER vs Pattern Matching)    │ │
          │  ├─────────────────────────────────┤ │
          │  │ 2. Geocoding Service            │ │
          │  │    (Place names → coords)       │ │
          │  ├─────────────────────────────────┤ │
          │  │ 3. Geohash Encoding             │ │
          │  │    (Spatial region keys)        │ │
          │  ├─────────────────────────────────┤ │
          │  │ 4. Aggregation Layer            │ │
          │  │    (Dedup + score merge)        │ │
          │  └─────────────────────────────────┘ │
          └───────────┬──────────────────────────┘
                      │
          ┌───────────▼──────────────┐
          │    Storage Fan-Out       │
          ├──────────┬─────────┬─────┤
          │Firestore │BigQuery│Redis│
          └──────────┴─────────┴─────┘
```

### Source Characteristics

| Source | Interval | Rate Limit | Cost | Data Type | Confidence |
|--------|----------|-----------|------|-----------|------------|
| **GlobalRSSMonitor** | 30 min | ✓ None (RSS) | Free | News articles | Medium (0.65) |
| **MastodonIngestor** | 10 min | ✓ Limited (public API) | Free | Social posts | Low (0.50-0.60) |
| **NGOReportsIngestor** | 6 hours | ✓ Self-throttled | Free | NGO PDFs | High (0.85+) |

## How It Works

### 1. GlobalRSSMonitor (Real-Time News)

**Purpose:** Monitor for crisis articles across multiple Indian regions using free Google News RSS.

**Features:**
- Queries Google News RSS with region-specific + community keywords
- Deep-scrapes articles using `newspaper3k` to extract full text
- Community-specific keywords (e.g., "Gram Panchayat", "PDS shortage", "bund breach")
- Automatic crisis classification (flood, cyclone, medical, etc.)
- Semantic confidence scoring based on article depth

**Environment Variables:**
```env
INGEST_RSS_ENABLED=true
INGEST_RSS_INTERVAL=1800        # 30 minutes (respects free tier)
INGEST_RSS_MAX_ARTICLES=20
```

**Example Query Generated:**
```
q=assam flood waterway tea garden Assam
→ Google News RSS returns all articles matching these terms
→ GlobalRSSMonitor deep-scrapes each link
→ Extracts crisis type + severity from full article text
```

### 2. MastodonIngestor (Social Signals)

**Purpose:** Real-time social signals from the decentralized Mastodon network.

**Why Mastodon?**
- No paid API tier (unlike Twitter/X)
- Growing humanitarian and disaster relief community
- Hashtag-driven, making filtering reliable
- Public API freely accessible for 40 posts per poll cycle

**Features:**
- Monitors public timelines of configurable instances
- Filters by crisis-related hashtags (#DisasterAlert, #IndiaFloods, etc.)
- Extracts posts + metadata (account, engagement metrics)
- Real-time signal detection for emerging crises

**Environment Variables:**
```env
INGEST_MASTODON_ENABLED=true
INGEST_MASTODON_INTERVAL=600   # 10 minutes
```

**Signal Example:**
```
[Mastodon Post]
Account: @ndrf_official
Post: "NDRF team mobilized to Assam for flood relief. 50+ families affected."
Hashtags: #DisasterAlert #IndiaFloods
→ Detected as: flood (need_type), high severity
```

### 3. NGOReportsIngestor (Historical + Periodic)

**Unchanged.** This continues to scrape 7 major NGO websites every 6 hours:
- Oxfam India
- ActionAid India
- Pradan
- Sphere India
- Sewa Bharat
- NFI
- VHAI

## Integration with Unified Pipeline

All sources feed into the same **Unified Data Pipeline**, which:

1. **Intelligent Extraction:**
   - GlobalRSSMonitor articles → NER for place extraction (HYBRID)
   - Mastodon posts → Pattern matching first, NER if low confidence (HYBRID)
   - NGO reports → Skip NER (NEVER) due to high structural quality

2. **Geocoding:** Resolution of extracted place names to (lat, lon) coordinates

3. **Aggregation:** De-duplication and score merging using temporal-spatial keys

4. **Storage:** Multi-sink (Firestore, BigQuery, Redis)

## Reliability Scoring

Sources are weighted by **source tier**:

```python
SOURCE_TIER = {
    "GDACS": 1,          # Official (highest priority)
    "NDMA": 1,           # Government
    "NGO_REPORTS": 2,    # Crowd-sourced but vetted
    "MASTODON": 2,       # Social media (same tier)
    "GLOBAL_RSS": 3,     # Contextual news
}
```

**Aggregation Logic:**
- Tier 1 alerts immediately escalate (high trust)
- Tier 2-3 sources boost severity only when multiple sources align spatially-temporally
- Deduplication uses geohash + event type + day to prevent alert fatigue

## Free Service Limitations & Mitigations

| Limitation | Service | Mitigation |
|------------|---------|-----------|
| Rate limits | Google News RSS | 30-min polling interval |
| Public data only | Mastodon | Configurable instances with active communities |
| Unstructured text | All | NER extraction (NVIDIA) with pattern matching fallback |
| No authentication | All | No API key rotation needed; fully autonomous |

## Deployment

### 1. Install Dependencies

Already in `requirements.txt`:
```
feedparser==6.0.11          # RSS parsing
newspaper3k==0.2.8         # Deep article scraping
httpx==0.27.0              # Async HTTP client
beautifulsoup4==4.12.3      # HTML parsing
```

### 2. Configure Environment

Copy `.env.example` to `.env`:
```bash
cp backend/.env.example backend/.env
```

Enable the new sources (already default):
```env
INGEST_RSS_ENABLED=true
INGEST_MASTODON_ENABLED=true
INGEST_NGO_ENABLED=true
```

### 3. Run the Backend

```bash
cd backend
python main.py
```

The system automatically starts all ingestors in background tasks.

### 4. Monitor Logs

Each ingestor logs to stdout:
```
[GlobalRSSMonitor] normalized 15 events from 6 regions
[Mastodon] normalized 3 events from 2 instances
[NGOReports] normalized 8 events
[UnifiedPipeline] Processing event RSS-abc123 from GLOBAL_RSS
```

## Extending the System

### Add a New RSS Region

Edit `backend/pipeline/ingestors/global_rss_monitor.py`:

```python
COMMUNITY_KEYWORDS = {
    "assam": ["bund", "waterway", "tea garden"],
    "tamil_nadu": ["farmers", "irrigation", "tank", "drought"],  # NEW
}
```

### Add a Mastodon Instance

Edit `backend/pipeline/ingestors/mastodon_ingestor.py`:

```python
MASTODON_INSTANCES = [
    "mastodon.social",
    "techhub.social",
    "pixelfed.social",
    "fosstodon.org",  # NEW
]
```

### Add a Custom Extraction Strategy

Edit `backend/pipeline/processing/extraction_strategy.py`:

```python
"MY_SOURCE": ExtractionConfig(
    strategy=ExtractionStrategy.HYBRID,
    confidence_threshold=0.65,
    cache_results=True,
)
```

## Troubleshooting

### "No events from GlobalRSSMonitor"

1. Check network: `curl -s "https://news.google.com/rss/search?q=flood" | head`
2. Verify keywords are present in query
3. Increase `INGEST_RSS_MAX_ARTICLES` to 50 for testing

### "Low confidence scores from Mastodon"

1. Check hashtags are in posts: Search Mastodon manually for `#DisasterAlert`
2. Increase `max_articles` for more signal
3. Local instances may have less humanitarian content; use `mastodon.social`

### Events not appearing in Firestore

1. Check unified pipeline logs: Look for "Processing event..."
2. Verify geocoding isn't failing: Check if lat/lon are still fallback values
3. Ensure Redis is running for pub/sub: `redis-cli ping` → PONG

## Performance Metrics

**Current Load (Steady State):**
- GlobalRSSMonitor: 1-2 HTTP requests → 50-100 article fetches (parallel) → 15-20 events/cycle
- MastodonIngestor: 2 API calls (1 per instance) → 40-80 posts → 2-5 events/cycle
- NGOReportsIngestor: 1 scrapy run every 6 hours → 50-100 events/cycle

**Total throughput:** ~25-35 events/hour during peak hours, ~5-10 events/hour otherwise

**Expected lag:** 10-30 minutes (due to scraping time + processing)

## Future Enhancements

1. **IndiaStack RSS:** Monitor state/district-level RSS feeds (NDMA, state disaster management)
2. **Twitter API (Academic Tier):** Free tier for researchers/NGOs
3. **Reddit Community Monitoring:** r/India, r/IndiaCrisis subreddits
4. **Community Alerts:** Direct SMS/WhatsApp integration for hyperlocal reports
5. **ML-based Deduplication:** Learn cluster patterns to reduce false alerts
