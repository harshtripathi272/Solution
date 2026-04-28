# Quick Start Guide: Real-Time Community Crisis Monitoring

## TL;DR - Get It Running in 5 Minutes

### 1. Setup

```bash
# Navigate to backend
cd backend

# Copy environment configuration
cp .env.example .env

# Install project dependencies
pip install -r requirements.txt

# Verify Python syntax
python -m py_compile pipeline/ingestors/*.py
```

### 2. Run Integration Tests (Optional)

```bash
python test_integration_ingestors.py
```

Expected output:
```
[✓] Got 8 events from GlobalRSSMonitor
  Event 1: flood, orange severity, 0.68 confidence
  ...
[✓] Got 0 events from MastodonIngestor
  (May be 0 if no crisis posts in recent feed - that's OK!)
```

### 3. Start the System

```bash
# Start the FastAPI backend
python main.py
```

You should see logs like:
```
[IngestionManager] Started 3 ingestion workers
[GlobalRSSMonitor] normalized 12 events from 6 regions
[Mastodon] normalized 2 events from 1 instance
[UnifiedPipeline] Processing event RSS-abc123 from GLOBAL_RSS
```

### 4. Verify Data is Flowing

Check Firebase or Redis:
```bash
# If using Redis, check events are being published:
redis-cli
> SUBSCRIBE ingestion-normalized
# You should see events flowing in

# Or check Firestore console for new documents in:
# /crises/{event_id}
```

## Configuration

### Enable/Disable Sources

Edit `.env`:

```env
# Turn on real-time RSS monitoring
INGEST_RSS_ENABLED=true
INGEST_RSS_INTERVAL=1800    # Every 30 min

# Turn on social media monitoring  
INGEST_MASTODON_ENABLED=true
INGEST_MASTODON_INTERVAL=600   # Every 10 min

# Keep periodic NGO scraper
INGEST_NGO_ENABLED=true
INGEST_NGO_INTERVAL=21600   # Every 6 hours
```

### Adjust Poll Intervals

For **more frequent updates** (more data, higher bandwidth):
```env
INGEST_RSS_INTERVAL=600          # Every 10 min instead of 30
INGEST_MASTODON_INTERVAL=300     # Every 5 min instead of 10
```

For **less frequent updates** (save bandwidth):
```env
INGEST_RSS_INTERVAL=3600         # Every hour
INGEST_MASTODON_INTERVAL=1200    # Every 20 min
```

## What Each Source Does

### GlobalRSSMonitor
- Queries Google News RSS for specific regions + crisis keywords
- Deep-scrapes article content using `newspaper3k`
- Runs every 30 minutes
- Community-focused keywords: `"Gram Panchayat"`, `"PDS shortage"`, `"bund breach"`

### MastodonIngestor
- Monitors Mastodon public timeline for crisis hashtags
- Hashtags: `#DisasterAlert`, `#IndiaFloods`, `#CrisisResponse`
- Runs every 10 minutes
- No authentication needed (public API)

### NGOReportsIngestor (Existing)
- Scrapes 7 major NGO websites
- Runs every 6 hours
- Extracts PDFs and structured data

## Monitoring & Debugging

### Check If Ingestors Are Running

Look for these log lines:
```
[GlobalRSSMonitor] worker started (interval=1800s)
[Mastodon] worker started (interval=600s)
[NGOReports] worker started (interval=21600s)
```

If you don't see them, check:
1. Environment variables are set correctly: `cat .env | grep INGEST`
2. Python imports work: `python -c "from pipeline.ingestors.global_rss_monitor import GlobalRSSMonitor"`

### Check Events Are Being Processed

Look for these log lines:
```
[GlobalRSSMonitor] normalized 14 events from 6 regions
[Mastodon] normalized 3 events from 1 instance
[UnifiedPipeline] Processing event RSS-abc123 from GLOBAL_RSS
```

### Check Event Quality

Use the test script to fetch a sample:
```bash
python test_integration_ingestors.py
```

This will show you the actual events, their classifications, and confidence scores.

### Troubleshooting

**Problem: 0 events from RSS**
- Check network: `curl -s "https://news.google.com/rss/search?q=flood" | head -20`
- Verify keywords exist: Try Googling the query manually
- Increase max articles in `.env`: `INGEST_RSS_MAX_ARTICLES=50`

**Problem: 0 events from Mastodon**
- This may be normal if no crisis posts in recent feed
- Try searching Mastodon manually: mastodon.social search for `#DisasterAlert`
- Check different instances: Add `"fosstodon.org"` to `MASTODON_INSTANCES`

**Problem: Events in logs but not in Firestore**
- Check unified pipeline is running: Look for `[UnifiedPipeline]` logs
- Verify NER service is accessible (if enabled)
- Check Redis is running: `redis-cli ping` → should return `PONG`

## Architecture Review

```
Real-Time Sources (Free)
    ↓ (Every 30min / 10min / 6hr)
UnifiedIngestionEvent objects
    ↓
IngestionManager (dedup check)
    ↓
Pub/Sub: ingestion-normalized
    ↓
Unified Pipeline:
  - Extract (NER vs Pattern)
  - Geocode (Place → coords)
  - Hash (Dedup key)
  - Aggregate (Score merge)
    ↓
Multi-Sink:
  ├→ Firestore (real-time DB)
  ├→ BigQuery (analytics)
  └→ Redis (cache)
```

## Next Steps for Your Team

1. **Regional Expansion:** Add more regions to `COMMUNITY_KEYWORDS` in `global_rss_monitor.py`
2. **Social Listening:** Add trusted Mastodon accounts to auto-follow in `mastodon_ingestor.py`
3. **Reliability Tuning:** Adjust confidence thresholds in `extraction_strategy.py`
4. **Alert Integration:** Hook up Firestore changes to send SMS/emails to volunteers
5. **Dashboard:** Build a web UI to visualize real-time events from Redis cache

## Production Checklist

- [ ] Set `LOG_LEVEL=INFO` in `.env` (remove DEBUG logs)
- [ ] Configure Redis with persistence: `appendonly yes` in `redis.conf`
- [ ] Set up log rotation for backend logs
- [ ] Monitor error rates: Set up alerts if `[ERROR]` logs spike
- [ ] Test failover: Verify system recovers if one source goes down
- [ ] Backup historical data: Set up BigQuery snapshots daily

## Questions?

Refer to:
- `REAL_TIME_INGESTION.md` — Detailed architectural documentation
- `test_integration_ingestors.py` — Example of how ingestors work
- `.env.example` — All configuration options with comments
