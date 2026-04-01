"""Compatibility wrapper for callers expecting unified_pipeline.py."""

from pipeline.orchestrators.unified import UnifiedPipeline, unified_pipeline

__all__ = ["UnifiedPipeline", "unified_pipeline"]
