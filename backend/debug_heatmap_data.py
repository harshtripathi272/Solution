#!/usr/bin/env python3
"""Debug script to verify Firestore data and test heatmap API."""

import sys
from datetime import datetime, timezone, timedelta

sys.path.insert(0, '.')

from auth import db
from api.heatmap import _fetch_firestore_points, _aggregate_points

async def debug_firestore_data():
    """Query Firestore and print document structure."""
    print("=" * 60)
    print("DEBUG: Firestore need_regions Documents")
    print("=" * 60)
    
    try:
        query = db.collection('need_regions').limit(5)
        docs = list(query.stream())
        print(f'\nFound {len(docs)} documents in need_regions collection\n')
        
        for i, doc in enumerate(docs):
            data = doc.to_dict() or {}
            print(f'\n--- Document {i+1}: {doc.id} ---')
            print(f'  centroid_lat: {data.get("centroid_lat", "MISSING")}')
            print(f'  centroid_lon: {data.get("centroid_lon", "MISSING")}')
            print(f'  need_scores: {data.get("need_scores", "MISSING")}')
            print(f'  composite_urgency: {data.get("composite_urgency", "MISSING")}')
            print(f'  max_severity: {data.get("max_severity", "MISSING")}')
            print(f'  last_updated: {data.get("last_updated", "MISSING")}')
            print(f'  admin_level: {data.get("admin_level", "MISSING")}')
            
    except Exception as e:
        print(f'ERROR querying Firestore: {e}', file=sys.stderr)
        import traceback
        traceback.print_exc()

async def debug_fetch_firestore_points():
    """Test the _fetch_firestore_points function."""
    print("\n" + "=" * 60)
    print("DEBUG: Testing _fetch_firestore_points()")
    print("=" * 60)
    
    now = datetime.now(timezone.utc)
    since_ts = now - timedelta(days=30)
    
    try:
        points = await _fetch_firestore_points(
            since_ts=since_ts,
            region=None,
            need_types=set(),
            min_severity=0.1,
        )
        
        print(f'\nFetched {len(points)} HeatPoints from Firestore')
        for i, point in enumerate(points[:5]):  # Show first 5
            print(f'\n  Point {i+1}:')
            print(f'    lat={point.lat}, lon={point.lon}')
            print(f'    severity={point.severity}, need_type={point.need_type}')
            print(f'    population={point.population_affected}, confidence={point.confidence}')
            
    except Exception as e:
        print(f'ERROR in _fetch_firestore_points: {e}', file=sys.stderr)
        import traceback
        traceback.print_exc()

async def debug_aggregation():
    """Test the aggregation step."""
    print("\n" + "=" * 60)
    print("DEBUG: Testing Point Aggregation")
    print("=" * 60)
    
    now = datetime.now(timezone.utc)
    since_ts = now - timedelta(days=30)
    
    try:
        points = await _fetch_firestore_points(
            since_ts=since_ts,
            region=None,
            need_types=set(),
            min_severity=0.1,
        )
        
        print(f'\nAggregating {len(points)} points...')
        features, raw_count = _aggregate_points(points)
        print(f'Generated {len(features)} GeoJSON features from {raw_count} raw points')
        
        for i, feature in enumerate(features[:3]):  # Show first 3
            props = feature['props']
            coords = feature['geometry']['coordinates']
            print(f'\n  Feature {i+1}:')
            print(f'    coordinates: [{coords[0]:.4f}, {coords[1]:.4f}]')
            print(f'    severity: {props["severity"]:.3f}, label: {props["severity_label"]}')
            print(f'    need_type: {props["need_type"]}')
            
    except Exception as e:
        print(f'ERROR in aggregation: {e}', file=sys.stderr)
        import traceback
        traceback.print_exc()

if __name__ == '__main__':
    import asyncio
    
    asyncio.run(debug_firestore_data())
    asyncio.run(debug_fetch_firestore_points())
    asyncio.run(debug_aggregation())
