from __future__ import annotations

import json
import logging
import os
from typing import TYPE_CHECKING, Any

logger = logging.getLogger(__name__)

try:  # pragma: no cover - optional dependency
    from neo4j import GraphDatabase
    _NEO4J_AVAILABLE = True
except ImportError:  # pragma: no cover - optional dependency
    GraphDatabase = None
    _NEO4J_AVAILABLE = False

if TYPE_CHECKING:
    from pipeline.processing.community_graph import CommunityProjection


class Neo4jStore:
    def __init__(self) -> None:
        self._driver = None
        self._enabled = False
        self._database = os.getenv("NEO4J_DATABASE", "neo4j").strip() or "neo4j"
        self._init()

    def _init(self) -> None:
        uri = os.getenv("NEO4J_URI", "").strip()
        user = os.getenv("NEO4J_USER", "").strip()
        password = os.getenv("NEO4J_PASSWORD", "").strip()

        if not uri or not user or not password:
            logger.info("[Neo4jStore] Missing credentials — graph sink disabled.")
            return
        if not _NEO4J_AVAILABLE:
            logger.warning("[Neo4jStore] neo4j driver not installed — graph sink disabled.")
            return

        try:
            self._driver = GraphDatabase.driver(uri, auth=(user, password))
            self._enabled = True
            self._ensure_constraints()
            logger.info("[Neo4jStore] Connected to Neo4j CE at %s", uri)
        except Exception as exc:
            logger.error("[Neo4jStore] Init failed: %s", exc)
            self._driver = None
            self._enabled = False

    def _ensure_constraints(self) -> None:
        if not self._driver:
            return

        statements = [
            "CREATE CONSTRAINT community_id IF NOT EXISTS FOR (c:Community) REQUIRE c.id IS UNIQUE",
            "CREATE CONSTRAINT ngo_id IF NOT EXISTS FOR (n:NGO) REQUIRE n.id IS UNIQUE",
            "CREATE CONSTRAINT report_id IF NOT EXISTS FOR (r:Report) REQUIRE r.id IS UNIQUE",
            "CREATE CONSTRAINT need_id IF NOT EXISTS FOR (n:Need) REQUIRE n.id IS UNIQUE",
            "CREATE CONSTRAINT resource_id IF NOT EXISTS FOR (r:Resource) REQUIRE r.id IS UNIQUE",
        ]

        with self._driver.session(database=self._database) as session:
            for statement in statements:
                try:
                    session.run(statement)
                except Exception as exc:
                    logger.debug("[Neo4jStore] Constraint skipped: %s", exc)

    async def upsert_projection(self, projection: "CommunityProjection") -> None:
        if not self._enabled or not self._driver:
            return

        payload = self._projection_payload(projection)

        def _write() -> None:
            with self._driver.session(database=self._database) as session:
                session.execute_write(self._write_batch, [payload])

        import asyncio

        try:
            await asyncio.get_event_loop().run_in_executor(None, _write)
        except Exception as exc:
            logger.error("[Neo4jStore] upsert_projection failed for %s: %s", projection.community.get("id"), exc)

    def _projection_payload(self, projection: "CommunityProjection") -> dict[str, Any]:
        community = projection.community
        event = projection.event
        ngo = projection.ngo

        return {
            "community": {
                "id": community.get("id"),
                "name": community.get("name"),
                "region": community.get("region"),
                "district": community.get("district"),
                "block": community.get("block"),
                "latitude": community.get("latitude"),
                "longitude": community.get("longitude"),
                "admin_level": community.get("admin_level"),
                "resolution_confidence": community.get("resolution_confidence"),
                "freshness_weight": community.get("freshness_weight"),
                "baseline_json": json.dumps(community.get("baseline", {}), ensure_ascii=True, sort_keys=True),
                "embedding": community.get("embedding", []),
                "target_ngos": community.get("target_ngos", []),
                "keywords": community.get("keywords", []),
            },
            "event": {
                "id": event.get("id"),
                "source": event.get("source"),
                "timestamp": event.get("timestamp"),
                "description": event.get("description"),
                "url": event.get("url"),
                "text": event.get("text"),
                "confidence_score": event.get("confidence_score"),
                "severity": event.get("severity"),
                "composite_urgency": event.get("composite_urgency"),
                "severity_acute": event.get("severity_acute"),
                "severity_chronic": event.get("severity_chronic"),
                "classification": event.get("classification"),
                "recommended_response_time": event.get("recommended_response_time"),
                "provenance_json": json.dumps(event.get("provenance", {}), ensure_ascii=True, sort_keys=True),
                "community_matched_text": event.get("community_matched_text", ""),
                "community_match_source": event.get("community_match_source", ""),
                "community_matched_terms": event.get("community_matched_terms", []),
            },
            "ngo": ngo,
            "needs": projection.needs,
            "resources": projection.resources,
            "similarity": projection.similarity,
            "coverage_gaps": projection.coverage_gaps,
            "coordination_opportunities": projection.coordination_opportunities,
            "matrix": projection.matrix,
        }

    @staticmethod
    def _write_batch(tx, rows: list[dict[str, Any]]) -> None:
        cypher = """
        UNWIND $rows AS row
        MERGE (community:Community {id: row.community.id})
        SET community.name = row.community.name,
            community.region = row.community.region,
            community.district = row.community.district,
            community.block = row.community.block,
            community.latitude = row.community.latitude,
            community.longitude = row.community.longitude,
            community.admin_level = row.community.admin_level,
            community.resolution_confidence = row.community.resolution_confidence,
            community.freshness_weight = row.community.freshness_weight,
            community.baseline_json = row.community.baseline_json,
            community.embedding = row.community.embedding,
            community.target_ngos = row.community.target_ngos,
            community.keywords = row.community.keywords,
            community.updated_at = datetime()

        MERGE (ngo:NGO {id: row.ngo.id})
        SET ngo.name = row.ngo.name,
            ngo.type = row.ngo.type,
            ngo.active = row.ngo.active,
            ngo.source_count = coalesce(row.ngo.source_count, 1),
            ngo.updated_at = datetime()

        MERGE (report:Report {id: row.event.id})
        SET report.source = row.event.source,
            report.timestamp = datetime(row.event.timestamp),
            report.description = row.event.description,
            report.url = row.event.url,
            report.text = row.event.text,
            report.confidence_score = row.event.confidence_score,
            report.severity = row.event.severity,
            report.composite_urgency = row.event.composite_urgency,
            report.severity_acute = row.event.severity_acute,
            report.severity_chronic = row.event.severity_chronic,
            report.classification = row.event.classification,
            report.recommended_response_time = row.event.recommended_response_time,
            report.provenance_json = row.event.provenance_json,
            report.updated_at = datetime()

        MERGE (report)-[pub:PUBLISHED]->(ngo)
        SET pub.timestamp = datetime(row.event.timestamp),
            pub.source = row.event.source,
            pub.confidence = row.event.confidence_score

        MERGE (report)-[ment:MENTIONS]->(community)
        SET ment.confidence = row.community.resolution_confidence,
            ment.matched_text = row.event.community_matched_text,
            ment.match_source = row.event.community_match_source,
            ment.matched_terms = row.event.community_matched_terms,
            ment.freshness = row.community.freshness_weight,
            ment.updated_at = datetime()

        WITH row, report, community
        UNWIND row.needs AS need_row
        MERGE (need:Need {id: need_row.id})
        SET need.need_type = need_row.need_type,
            need.label = need_row.label,
            need.resource_id = need_row.resource_id,
            need.keywords = need_row.keywords,
            need.updated_at = datetime()
        MERGE (report)-[idn:IDENTIFIES_NEED]->(need)
        SET idn.confidence = need_row.confidence,
            idn.evidence_quotes = need_row.evidence_quotes,
            idn.acute_score = need_row.acute_score,
            idn.chronic_score = need_row.chronic_score,
            idn.temporality = need_row.temporality,
            idn.updated_at = datetime()
        MERGE (community)-[has:HAS_NEED]->(need)
        SET has.score = need_row.chronic_score,
            has.acute_score = need_row.acute_score,
            has.confidence = need_row.confidence,
            has.freshness = row.community.freshness_weight,
            has.updated_at = datetime()

        WITH row, community
        UNWIND row.resources AS resource_row
        MERGE (resource:Resource {id: resource_row.id})
        SET resource.label = resource_row.label,
            resource.resource_type = resource_row.resource_type,
            resource.updated_at = datetime()
        MERGE (community)-[rel:HAS_RESOURCE]->(resource)
        SET rel.availability = resource_row.availability,
            rel.updated_at = datetime()

        WITH row, community
        UNWIND row.similarity AS sim_row
        MERGE (peer:Community {id: sim_row.community_id})
        SET peer.name = coalesce(sim_row.name, peer.name)
        MERGE (community)-[sim:SIMILAR_TO]->(peer)
        SET sim.score = sim_row.score,
            sim.updated_at = datetime()
        """
        tx.run(cypher, rows=rows)


neo4j_store = Neo4jStore()
