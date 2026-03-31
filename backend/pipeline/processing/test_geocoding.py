import asyncio
import logging
import os
import pytest
from pipeline.processing.geocoding import GeocodingService, GeoResult

# Setup logging to see what's happening
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@pytest.mark.asyncio
async def test_nominatim_fallback_real():
    """
    Test Nominatim fallback with a real request to ensure it works.
    We force use_nominatim = True for this test.
    """
    service = GeocodingService()
    # Force Nominatim for the test
    service._use_nominatim = True
    
    # Test a well-known place in India
    places = ["India", "Dharavi"]
    result = await service.geocode(places)
    print(result)
    assert result is not None
    assert isinstance(result, GeoResult)
    assert result.lat != 0.0
    assert result.lon != 0.0
    assert "India" in result.resolved_name
    assert result.admin_level in ["country","block", "district", "state"]
    
    logger.info(f"Resolved Wayanad to: {result.resolved_name} ({result.lat}, {result.lon})")

@pytest.mark.asyncio
async def test_nominatim_empty_results():
    """Test handling of non-existent places."""
    service = GeocodingService()
    service._use_nominatim = True
    
    result = await service.geocode(["ThisPlaceDoesNotExist123456789"])
    print(f"Empty results check: {result}")
    assert result is None

@pytest.mark.asyncio
async def test_nominatim_rate_limiting():
    """Test that two rapid calls take at least the rate limit time."""
    service = GeocodingService()
    service._use_nominatim = True
    
    import time
    start = time.perf_counter()
    
    # First call
    r1 = await service.geocode(["Delhi"])
    print(f"Call 1: {r1.resolved_name if r1 else 'None'}")
    # Second call (should be delayed by ~1.1s)
    r2 = await service.geocode(["Mumbai"])
    print(f"Call 2: {r2.resolved_name if r2 else 'None'}")
    
    elapsed = time.perf_counter() - start
    print(f"Rate limiting test: two calls took {elapsed:.2f}s (required > 1.1s)")
    assert elapsed >= 1.1

if __name__ == "__main__":
    # Allow running directly
    asyncio.run(test_nominatim_fallback_real())
    asyncio.run(test_nominatim_rate_limiting())
