#!/usr/bin/env python3
"""
Integration test for new free real-time ingestors.

Run this to verify GlobalRSSMonitor and MastodonIngestor are working.
"""

import asyncio
import sys
from pathlib import Path

# Add backend to path
backend_root = Path(__file__).parent
sys.path.insert(0, str(backend_root))

from pipeline.ingestors.global_rss_monitor import GlobalRSSMonitor
from pipeline.ingestors.mastodon_ingestor import MastodonIngestor


async def test_rss_monitor():
    """Test GlobalRSSMonitor with limited scope."""
    print("\n" + "="*70)
    print("Testing GlobalRSSMonitor")
    print("="*70)
    
    monitor = GlobalRSSMonitor(
        interval_seconds=1800,
        regions=["assam", "odisha"],  # Just 2 regions for quick test
        max_articles=5
    )
    
    try:
        print("[*] Fetching articles from Google News RSS...")
        events = await monitor.fetch_events()
        
        print(f"[✓] Got {len(events)} events")
        for i, event in enumerate(events, 1):
            print(f"\n  Event {i}:")
            print(f"    ID: {event.id}")
            print(f"    Type: {event.need_type}")
            print(f"    Severity: {event.severity}")
            print(f"    Confidence: {event.confidence_score}")
            print(f"    Description: {event.description[:60]}...")
            if "url" in event.metadata:
                print(f"    Source URL: {event.metadata['url'][:50]}...")
        
        # Zero events can happen during low-news windows; treat successful fetch as pass.
        return True
    except Exception as e:
        print(f"[✗] Error: {e}")
        import traceback
        traceback.print_exc()
        return False


async def test_mastodon_ingestor():
    """Test MastodonIngestor."""
    print("\n" + "="*70)
    print("Testing MastodonIngestor")
    print("="*70)
    
    ingestor = MastodonIngestor(
        interval_seconds=600,
        instances=["mastodon.social"]
    )
    
    try:
        print("[*] Fetching posts from Mastodon...")
        events = await ingestor.fetch_events()
        
        print(f"[✓] Got {len(events)} events")
        for i, event in enumerate(events, 1):
            print(f"\n  Event {i}:")
            print(f"    ID: {event.id}")
            print(f"    Type: {event.need_type}")
            print(f"    Severity: {event.severity}")
            print(f"    Confidence: {event.confidence_score}")
            print(f"    Description: {event.description[:60]}...")
            if "account" in event.metadata:
                print(f"    Account: @{event.metadata['account']}")
        
        # Note: May return 0 events if no crisis posts in recent feed
        # This is not necessarily a failure
        print(f"[*] Note: 0 events may be normal if no crisis posts in feed")
        return True
    except Exception as e:
        print(f"[✗] Error: {e}")
        import traceback
        traceback.print_exc()
        return False


async def main():
    """Run all tests."""
    print("\n" + "#"*70)
    print("# Real-Time Ingestor Integration Tests")
    print("#"*70)
    
    results = []
    
    # Test RSS Monitor
    rss_ok = await test_rss_monitor()
    results.append(("GlobalRSSMonitor", rss_ok))
    
    # Test Mastodon
    mastodon_ok = await test_mastodon_ingestor()
    results.append(("MastodonIngestor", mastodon_ok))
    
    # Summary
    print("\n" + "="*70)
    print("Test Summary")
    print("="*70)
    for name, passed in results:
        status = "✓ PASS" if passed else "✗ FAIL"
        print(f"{status}: {name}")
    
    all_passed = all(result[1] for result in results)
    if all_passed:
        print("\n[✓] All tests passed!")
        return 0
    else:
        print("\n[✗] Some tests failed")
        return 1


if __name__ == "__main__":
    exit_code = asyncio.run(main())
    sys.exit(exit_code)
