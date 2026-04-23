from __future__ import annotations

from typing import Any

__all__ = ["firestore_store", "bigquery_store", "redis_need_cache", "location_store", "neo4j_store"]


def __getattr__(name: str) -> Any:
	if name == "firestore_store":
		from .firestore import firestore_store

		return firestore_store
	if name == "bigquery_store":
		from .bigquery import bigquery_store

		return bigquery_store
	if name == "redis_need_cache":
		from .redis_cache import redis_need_cache

		return redis_need_cache
	if name == "location_store":
		from .location import location_store

		return location_store
	if name == "neo4j_store":
		from .neo4j_store import neo4j_store

		return neo4j_store
	raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
