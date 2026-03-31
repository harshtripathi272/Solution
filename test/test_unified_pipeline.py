"""
Unit tests for the SevaSetu Data Unification + Storage Pipeline.

Tests the following without requiring live API keys:
  - Geohash encoding/decoding
  - Event deduplication (AggregationLayer)
  - Score merging logic
  - Data class model validators (auto-flagging for geocoding)
  - UnifiedPipeline orchestrator flow (via mocks)

Run from backend/ directory:
  python -m pytest test/test_unified_pipeline.py -v
"""

import asyncio
from datetime import datetime, timezone
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from pipeline.core.schemas import UnifiedIngestionEvent, IngestionLocation, FALLBACK_INDIA_LAT, FALLBACK_INDIA_LON
from pipeline.processing.aggregation import AggregationLayer
from pipeline.processing.geohash import encode as geohash_encode, decode as geohash_decode
from pipeline.orchestrators.unified import UnifiedPipeline


# ---------------------------------------------------------------------------
# 1. Geohash Utilities Test
# ---------------------------------------------------------------------------
def test_geohash_utilities():
    with patch("pipeline.processing.geohash._GEOHASH_AVAILABLE", True), \
         patch("pipeline.processing.geohash._geohash.encode", return_value="ttnfv"), \
         patch("pipeline.processing.geohash._geohash.decode", return_value=(28.6, 77.2)):
        
        lat, lon = 28.6139, 77.2090  # Delhi
        gh = geohash_encode(lat, lon, precision=5)
        
        # Check deterministic output
        assert gh == "ttnfv"
        
        # Check decoding back to proximate centre
        d_lat, d_lon = geohash_decode(gh)
        assert d_lat == 28.6
        assert d_lon == 77.2


# ---------------------------------------------------------------------------
# 2. Schema / Model Validator Test
# ---------------------------------------------------------------------------
def test_schema_auto_flag_geocoding():
    # Case A: Real coordinates should NOT flag for geocoding
    event = UnifiedIngestionEvent(
        id="EV-REAL",
        source="GDACS",
        timestamp=datetime.now(timezone.utc),
        location=IngestionLocation(latitude=28.6, longitude=77.2), # Delhi
        need_type="flood",
        severity="high",
        confidence_score=0.9
    )
    assert event.needs_geocoding is False

    # Case B: Fallback coordinates SHOULD flag for geocoding automatically
    event_fb = UnifiedIngestionEvent(
        id="EV-FB",
        source="NEWS_API",
        timestamp=datetime.now(timezone.utc),
        location=IngestionLocation(latitude=FALLBACK_INDIA_LAT, longitude=FALLBACK_INDIA_LON),
        need_type="medical",
        severity="moderate",
        confidence_score=0.6
    )
    assert event_fb.needs_geocoding is True


# ---------------------------------------------------------------------------
# 3. Aggregation/Dedup Test
# ---------------------------------------------------------------------------
@pytest.mark.asyncio
async def test_aggregation_dedup_and_merge():
    # Create a fresh layer instance with a mocked redis client
    mock_redis = MagicMock()
    mock_redis.exists.return_value = False # First check returns not found
    mock_redis.get.return_value = "0.5"    # Initial regional score is 0.5
    
    # Mock the entire location_store object and its redis attribute
    mock_location_store = MagicMock()
    mock_location_store.redis = mock_redis
    
    with patch("pipeline.storage.location.location_store", mock_location_store):
        agg = AggregationLayer()
        ts = datetime(2026, 3, 28, 10, 0, tzinfo=timezone.utc)
        
        # Iteration 1: Process a new event
        is_dup, merged = agg.process(
            event_id="EV1", source="SRC1", geohash="ttnfv", 
            need_type="flood", timestamp=ts, severity="high", confidence=0.8
        )
        
        assert is_dup is False
        # Severity 'high' (0.7) * confidence (0.8) = 0.56 incoming
        # merged = alpha * 0.56 + (1-alpha) * 0.5
        assert merged > 0.0
        
        # Verify dedup set was updated
        from unittest.mock import ANY
        mock_redis.set.assert_any_call(ANY, "1", ex=86400)


# 4. Orchestrator Integration Test
@pytest.mark.asyncio
async def test_unified_pipeline_flow():
    # Mock all the heavyweight services
    pipeline = UnifiedPipeline()
    
    event = UnifiedIngestionEvent(
        id="EV-TEST",
        source="NEWS_API",
        timestamp=datetime.now(timezone.utc),
        location=IngestionLocation(latitude=FALLBACK_INDIA_LAT, longitude=FALLBACK_INDIA_LON),
        need_type="medical",
        severity="moderate",
        confidence_score=0.6,
        description="Outbreak in Delhi"
    )

    # Note: event.needs_geocoding is True because of India centroid
    
    # Mock NER to return 'Delhi'
    mock_ner = AsyncMock()
    mock_ner.extract.return_value = MagicMock(places=["Delhi"], need_type="medical", severity="high", confidence=0.8)
    
    # Mock Geocoder to return Delhi coords
    mock_geo = AsyncMock()
    mock_geo.geocode.return_value = MagicMock(lat=28.6, lon=77.2, admin_level="district", confidence=0.9, resolved_name="New Delhi, India")
    
    with patch("pipeline.orchestrators.unified.ner_extractor", mock_ner), \
         patch("pipeline.orchestrators.unified.geocoding_service", mock_geo), \
         patch("pipeline.orchestrators.unified.geohash_encode", return_value="ttnfc"), \
         patch("pipeline.orchestrators.unified.aggregation_layer.process", return_value=(False, 0.75)), \
         patch("pipeline.orchestrators.unified.firestore_store.upsert_region", new_callable=AsyncMock) as mock_fs_up, \
         patch("pipeline.orchestrators.unified.firestore_store.append_event", new_callable=AsyncMock) as mock_fs_ap, \
         patch("pipeline.orchestrators.unified.bigquery_store.append", new_callable=AsyncMock) as mock_bq, \
         patch("pipeline.orchestrators.unified.redis_need_cache.set", return_value=None) as mock_redis, \
         patch("pipeline.orchestrators.unified.broker.publish", new_callable=AsyncMock) as mock_pub:
        
        await pipeline._process(event)
        
        # Assertions
        mock_ner.extract.assert_called_once()
        mock_geo.geocode.assert_called_with(["Delhi"])
        
        # Verify storage fan-out happened
        mock_fs_up.assert_called_once()
        mock_fs_ap.assert_called_once()
        mock_bq.assert_called_once()
        mock_redis.assert_called_once()

        # Verify re-publishing for downstream dispatch
        mock_pub.assert_called_once()
        args, _ = mock_pub.call_args
        assert args[0] in ["official-alerts", "social-media-raw", "citizen-reports"]
        
        # The re-published event should have been enriched with geohash and new coords
        enriched_event = args[1]
        assert enriched_event.location.latitude == 28.6
        assert enriched_event.location.geohash == "ttnfc"
