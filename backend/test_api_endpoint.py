#!/usr/bin/env python3
"""Test the heatmap API endpoint directly."""

import asyncio
import sys
sys.path.insert(0, '.')

from api.heatmap import get_heatmap_data
from fastapi import Response

async def test_api():
    """Test the complete API endpoint."""
    response = Response()
    
    # Mock the dependency injection for RoleChecker
    result = await get_heatmap_data(
        response=response,
        region=None,
        need_type=None,
        min_severity=0.1,
        time_range='30d',
        _={'uid': 'test_user'}  # Mock dependency
    )
    
    print("=" * 60)
    print("API Response Test")
    print("=" * 60)
    
    print(f'\nHTTP Headers:')
    print(f'  Cache-Control: {response.headers.get("Cache-Control")}')
    print(f'  ETag: {response.headers.get("ETag", "<not set>")}')
    
    print(f'\nGeoJSON Top-Level:')
    print(f'  type: {result.get("type")}')
    print(f'  feature_count: {len(result.get("features", []))}')
    
    metadata = result.get("metadata", {})
    print(f'\nMetadata:')
    print(f'  raw_point_count: {metadata.get("raw_point_count")}')
    print(f'  feature_count: {metadata.get("feature_count")}')
    print(f'  source: {metadata.get("source")}')
    print(f'  generated_at: {metadata.get("generated_at")}')
    
    features = result.get("features", [])
    print(f'\nFeature Details (showing first 4):')
    for i, feat in enumerate(features[:4]):
        props = feat.get("properties", {})
        coords = feat.get("geometry", {}).get("coordinates", [0, 0])
        print(f'\n  Feature {i+1}:')
        print(f'    coordinates: [lon={coords[0]:.4f}, lat={coords[1]:.4f}]')
        print(f'    geohash: {props.get("geohash")}')
        print(f'    severity: {props.get("severity"):.3f} ({props.get("severity_label")})')
        print(f'    need_type: {props.get("need_type")}')
        print(f'    population: {props.get("population_affected")}')
        print(f'    confidence: {props.get("confidence"):.2f}')

if __name__ == '__main__':
    asyncio.run(test_api())
