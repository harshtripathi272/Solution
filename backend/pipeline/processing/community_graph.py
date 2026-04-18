from __future__ import annotations

import logging
import math
import re
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any

from pipeline.core.schemas import NeedTemporality, UnifiedIngestionEvent
from pipeline.processing.community_resolver import community_resolver

logger = logging.getLogger(__name__)


_SENTENCE_SPLIT_RE = re.compile(r"(?<=[.!?])\s+")


NEED_TAXONOMY: dict[str, dict[str, Any]] = {
    "severe_acute_malnutrition": {
        "aliases": ["severe acute malnutrition", "sam", "wasting", "child wasting", "underweight child", "nutrition crisis"],
        "keywords": ["nutrition", "malnutrition", "sam", "wasting", "stunting", "supplementary feeding", "icds", "anganwadi"],
        "resource": "nutrition_support",
        "severity_boost": 0.22,
    },
    "wash_deficits": {
        "aliases": ["wash deficits", "water and sanitation", "water scarcity", "sanitation gap"],
        "keywords": ["wash", "toilet", "latrine", "handpump", "drinking water", "water scarcity", "open defecation", "sanitation", "contaminated water"],
        "resource": "wash_infrastructure",
        "severity_boost": 0.18,
    },
    "maternal_health_gaps": {
        "aliases": ["maternal health", "antenatal", "postnatal", "pregnant women", "safe delivery"],
        "keywords": ["maternal", "pregnant", "delivery", "antenatal", "postnatal", "midwife", "asha", "delivery centre", "maternity"],
        "resource": "maternal_care",
        "severity_boost": 0.16,
    },
    "infrastructure_failures": {
        "aliases": ["infrastructure failures", "road access", "bridge damage", "housing damage"],
        "keywords": ["road", "bridge", "housing", "roof", "school building", "power supply", "electricity", "approach road", "collapsed", "broken", "flooded"],
        "resource": "infrastructure_repair",
        "severity_boost": 0.20,
    },
    "livelihood_threats": {
        "aliases": ["livelihood threats", "income loss", "employment loss", "crop loss"],
        "keywords": ["livelihood", "income", "work", "wage", "crop", "harvest", "employment", "migration", "fishing", "grazing", "market access"],
        "resource": "livelihood_recovery",
        "severity_boost": 0.14,
    },
}


SOURCE_STRENGTH: dict[str, float] = {
    "GDACS": 1.0,
    "NDMA": 1.0,
    "PIB": 0.95,
    "IMD": 0.92,
    "RELIEFWEB": 0.88,
    "DOC": 0.84,
    "NGO": 0.76,
    "NEWS": 0.66,
    "MASTODON": 0.54,
    "RSS": 0.60,
}


def _clamp01(value: float) -> float:
    return max(0.0, min(1.0, value))


def _freshness_weight(timestamp: datetime | None) -> float:
    if timestamp is None:
        return 0.5
    if timestamp.tzinfo is None:
        timestamp = timestamp.replace(tzinfo=timezone.utc)
    age_days = max(0.0, (datetime.now(timezone.utc) - timestamp).total_seconds() / 86400.0)
    if age_days <= 180.0:
        return 1.0
    decay_days = age_days - 180.0
    return _clamp01(math.exp(-decay_days / 120.0))


def _source_weight(event: UnifiedIngestionEvent) -> float:
    source = (event.source or "").upper().strip()
    for prefix, score in SOURCE_STRENGTH.items():
        if source.startswith(prefix):
            return score
    if "NGO" in source:
        return SOURCE_STRENGTH["NGO"]
    return 0.58


def _strip_html(text: str) -> str:
    return re.sub(r"<[^>]+>", " ", text or "")


def _normalize_space(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def _sentence_quotes(text: str) -> list[str]:
    sentences = [segment.strip() for segment in _SENTENCE_SPLIT_RE.split(text) if segment.strip()]
    if sentences:
        return sentences
    return [segment.strip() for segment in re.split(r"[\n\r]+", text) if segment.strip()]


def _build_search_text(event: UnifiedIngestionEvent) -> str:
    metadata = event.metadata or {}
    parts = [
        event.description,
        str(metadata.get("snippet", "")),
        str(metadata.get("raw_text", "")),
        str(metadata.get("article_text", "")),
        str(metadata.get("source_excerpt", "")),
        str(metadata.get("resolved_address", "")),
        str(metadata.get("region", "")),
        str(metadata.get("matched_text", "")),
    ]
    return _normalize_space(_strip_html(" ".join(part for part in parts if part)))


@dataclass(slots=True)
class NeedSignal:
    need_type: str
    label: str
    confidence: float
    evidence_quotes: list[str] = field(default_factory=list)
    chronic_score: float = 0.0
    acute_score: float = 0.0
    temporality: str = NeedTemporality.CHRONIC.value
    resource_type: str = "general_support"
    keywords: list[str] = field(default_factory=list)


@dataclass(slots=True)
class CommunityProjection:
    community: dict[str, Any]
    event: dict[str, Any]
    ngo: dict[str, Any]
    needs: list[dict[str, Any]]
    resources: list[dict[str, Any]]
    similarity: list[dict[str, Any]]
    coverage_gaps: list[dict[str, Any]]
    coordination_opportunities: list[dict[str, Any]]
    matrix: list[dict[str, Any]]
    metadata: dict[str, Any]


class CommunityTopicExtractor:
    def extract(self, event: UnifiedIngestionEvent, community: dict[str, Any] | None = None) -> list[NeedSignal]:
        text = _build_search_text(event)
        if not text:
            return []

        quotes = _sentence_quotes(text)
        signals: list[NeedSignal] = []

        for need_type, config in NEED_TAXONOMY.items():
            keyword_hits = [keyword for keyword in config["keywords"] if keyword in text.lower()]
            alias_hits = [alias for alias in config["aliases"] if alias in text.lower()]
            if not keyword_hits and not alias_hits:
                continue

            evidence_quotes = self._pick_quotes(quotes, keyword_hits + alias_hits)
            source_weight = _source_weight(event)
            freshness_weight = _freshness_weight(event.timestamp)
            community_boost = 0.08 if community else 0.0
            raw_confidence = 0.45 + (0.08 * len(keyword_hits)) + (0.06 * len(alias_hits)) + community_boost
            confidence = _clamp01(raw_confidence * source_weight * (0.75 + (0.25 * freshness_weight)))
            chronic_score = _clamp01(confidence * (0.55 + (0.45 * freshness_weight)))
            acute_score = _clamp01(confidence * (0.65 + config["severity_boost"]))

            signals.append(
                NeedSignal(
                    need_type=need_type,
                    label=need_type.replace("_", " "),
                    confidence=round(confidence, 3),
                    evidence_quotes=evidence_quotes,
                    chronic_score=round(chronic_score, 3),
                    acute_score=round(acute_score, 3),
                    temporality=event.need_temporality.value,
                    resource_type=config["resource"],
                    keywords=sorted(set(keyword_hits + alias_hits)),
                )
            )

        if not signals and community:
            baseline = community.get("default_chronic_baseline", {}) or {}
            malnutrition_rate = float(baseline.get("malnutrition_rate", 0.0) or 0.0)
            if malnutrition_rate > 0:
                signals.append(
                    NeedSignal(
                        need_type="severe_acute_malnutrition",
                        label="severe acute malnutrition",
                        confidence=0.52,
                        evidence_quotes=[community.get("name", "community baseline")],
                        chronic_score=_clamp01(malnutrition_rate),
                        acute_score=_clamp01(malnutrition_rate * 0.65),
                        temporality=NeedTemporality.CHRONIC.value,
                        resource_type="nutrition_support",
                        keywords=["baseline"],
                    )
                )

        return signals

    @staticmethod
    def _pick_quotes(sentences: list[str], terms: list[str]) -> list[str]:
        hits: list[str] = []
        lowered_terms = [term.lower() for term in terms if term]
        for sentence in sentences:
            sentence_lower = sentence.lower()
            if any(term in sentence_lower for term in lowered_terms):
                hits.append(sentence[:220])
            if len(hits) >= 3:
                break
        return hits


class CommunityGraphService:
    def __init__(self) -> None:
        self._topic_extractor = CommunityTopicExtractor()
        self._target_communities = community_resolver.communities

    def resolve_community(self, event: UnifiedIngestionEvent) -> dict[str, Any] | None:
        text = _build_search_text(event)
        match = community_resolver.resolve(text)
        if match is None:
            return None

        metadata = dict(event.metadata or {})
        baseline = match.get("default_chronic_baseline", {}) or {}
        metadata.update(
            {
                "community_id": match.get("id"),
                "community_name": match.get("name"),
                "community_confidence": match.get("resolution_confidence", 0.0),
                "community_match_source": match.get("resolution_method", "keyword"),
                "community_matched_text": match.get("matched_text", ""),
                "community_matched_terms": match.get("matched_terms", []),
                "community_village_hint": match.get("admin_level", "village"),
                "historical_crisis_frequency": baseline.get("malnutrition_rate", 0.0) * 15.0,
                "infrastructure_gaps": baseline.get("infrastructure_gaps", []),
                "vulnerable_groups": baseline.get("vulnerable_groups", []),
                "community_freshness_weight": _freshness_weight(event.timestamp),
            }
        )

        if match.get("latitude") is not None and match.get("longitude") is not None:
            event.location.latitude = float(match["latitude"])
            event.location.longitude = float(match["longitude"])
            event.admin_level = str(match.get("admin_level", event.admin_level))

        return metadata

    def build_projection(
        self,
        event: UnifiedIngestionEvent,
        severity_payload: dict[str, Any],
    ) -> CommunityProjection | None:
        community_context = self.resolve_community(event)
        if not community_context:
            return None

        community = next((community for community in self._target_communities if community.get("id") == community_context.get("community_id")), None)
        if community is None:
            return None

        event_text = _build_search_text(event)
        need_signals = self._topic_extractor.extract(event, community)
        if not need_signals:
            need_signals = []

        source_org = str((event.metadata or {}).get("source_org") or (event.metadata or {}).get("organization_id") or event.source).strip()
        source_url = str((event.metadata or {}).get("source_url") or (event.metadata or {}).get("url") or (event.document_metadata.pdf_url if event.document_metadata else "")).strip()
        report_id = event.id
        freshness_weight = _freshness_weight(event.timestamp)
        chronic_multiplier = float(severity_payload.get("severity_chronic", 0.0) or 0.0)

        needs: list[dict[str, Any]] = []
        resources: list[dict[str, Any]] = []
        matrix: list[dict[str, Any]] = []
        for signal in need_signals:
            need_id = f"{community['id']}::{signal.need_type}"
            resource_id = f"resource::{signal.resource_type}"
            needs.append(
                {
                    "id": need_id,
                    "need_type": signal.need_type,
                    "label": signal.label,
                    "confidence": signal.confidence,
                    "evidence_quotes": signal.evidence_quotes,
                    "acute_score": signal.acute_score,
                    "chronic_score": round(_clamp01(max(signal.chronic_score, chronic_multiplier) * freshness_weight), 3),
                    "temporality": signal.temporality,
                    "resource_id": resource_id,
                    "keywords": signal.keywords,
                }
            )
            resources.append(
                {
                    "id": resource_id,
                    "label": signal.resource_type.replace("_", " "),
                    "resource_type": signal.resource_type,
                    "availability": _clamp01(0.72 + (0.08 if signal.temporality == NeedTemporality.CHRONIC.value else 0.0)),
                }
            )
            matrix.append(
                {
                    "need_type": signal.need_type,
                    "severity": round(max(signal.chronic_score, signal.acute_score), 3),
                    "confidence": signal.confidence,
                }
            )

        if not needs:
            matrix.append({"need_type": "general", "severity": round(chronic_multiplier, 3), "confidence": 0.5})

        embedding = self._community_embedding(community, needs, severity_payload)
        similarity = self._similarity_snapshot(community, embedding)
        coverage_gaps = self._coverage_gaps(community, needs, event, freshness_weight)
        coordination_opportunities = self._coordination_opportunities(community, needs, event)

        community_payload = {
            "id": community["id"],
            "name": community.get("name", community["id"]),
            "region": community.get("region"),
            "district": community.get("district"),
            "block": community.get("block"),
            "latitude": community.get("latitude"),
            "longitude": community.get("longitude"),
            "keywords": community.get("keywords", []),
            "target_ngos": community.get("target_ngos", []),
            "admin_level": community_context.get("community_village_hint", community.get("admin_level", "village")),
            "resolution_confidence": community_context.get("community_confidence", 0.0),
            "freshness_weight": round(freshness_weight, 3),
            "baseline": community.get("default_chronic_baseline", {}),
            "embedding": embedding,
        }

        event_payload = {
            "id": report_id,
            "source": event.source,
            "timestamp": event.timestamp.isoformat(),
            "description": event.description,
            "url": source_url,
            "text": event_text[:1000],
            "confidence_score": event.confidence_score,
            "severity": event.severity,
            "composite_urgency": float(severity_payload.get("composite_urgency", 0.0) or 0.0),
            "severity_acute": float(severity_payload.get("severity_acute", 0.0) or 0.0),
            "severity_chronic": float(severity_payload.get("severity_chronic", 0.0) or 0.0),
            "classification": severity_payload.get("classification"),
            "recommended_response_time": severity_payload.get("recommended_response_time"),
            "provenance": {
                "community_match_source": community_context.get("community_match_source"),
                "community_matched_text": community_context.get("community_matched_text"),
                "community_matched_terms": community_context.get("community_matched_terms", []),
                "source_org": source_org,
            },
        }

        ngo_payload = {
            "id": source_org.lower().replace(" ", "_"),
            "name": source_org,
            "type": "ngo",
            "active": True,
            "source_count": 1,
        }

        return CommunityProjection(
            community=community_payload,
            event=event_payload,
            ngo=ngo_payload,
            needs=needs,
            resources=resources,
            similarity=similarity,
            coverage_gaps=coverage_gaps,
            coordination_opportunities=coordination_opportunities,
            matrix=matrix,
            metadata={
                "community_context": community_context,
                "source_org": source_org,
                "freshness_weight": round(freshness_weight, 3),
                "event_text": event_text[:1000],
            },
        )

    def _community_embedding(self, community: dict[str, Any], needs: list[dict[str, Any]], severity_payload: dict[str, Any]) -> list[float]:
        vector = [0.0] * 8
        index_map = {
            "severe_acute_malnutrition": 0,
            "wash_deficits": 1,
            "maternal_health_gaps": 2,
            "infrastructure_failures": 3,
            "livelihood_threats": 4,
        }

        for need in needs:
            idx = index_map.get(need["need_type"])
            if idx is not None:
                vector[idx] = max(vector[idx], float(need.get("chronic_score", 0.0)))

        baseline = community.get("default_chronic_baseline", {}) or {}
        vector[5] = float(baseline.get("malnutrition_rate", 0.0) or 0.0)
        vector[6] = float(severity_payload.get("severity_chronic", 0.0) or 0.0)
        vector[7] = _clamp01(len(needs) / 5.0)
        return [round(value, 4) for value in vector]

    def _similarity_snapshot(self, community: dict[str, Any], embedding: list[float]) -> list[dict[str, Any]]:
        scores: list[dict[str, Any]] = []
        for target in self._target_communities:
            target_embedding = self._community_embedding(target, [], {"severity_chronic": target.get("default_chronic_baseline", {}).get("malnutrition_rate", 0.0)})
            score = self._cosine_similarity(embedding, target_embedding)
            if target.get("id") == community.get("id"):
                score = 1.0
            scores.append(
                {
                    "community_id": target.get("id"),
                    "name": target.get("name"),
                    "score": round(score, 3),
                }
            )
        scores.sort(key=lambda item: item["score"], reverse=True)
        return scores[:5]

    def _coverage_gaps(self, community: dict[str, Any], needs: list[dict[str, Any]], event: UnifiedIngestionEvent, freshness_weight: float) -> list[dict[str, Any]]:
        if not needs:
            return []

        active_org = str((event.metadata or {}).get("organization_id") or (event.metadata or {}).get("source_org") or event.source).lower()
        target_ngos = {str(ngo).lower() for ngo in community.get("target_ngos", []) or []}
        active_ngos = {active_org}
        gap_score = max(float(need.get("chronic_score", 0.0)) for need in needs)
        if active_ngos.intersection(target_ngos):
            return []

        if gap_score < 0.55 and freshness_weight > 0.45:
            return []

        return [
            {
                "community_id": community.get("id"),
                "community_name": community.get("name"),
                "gap_score": round(gap_score, 3),
                "freshness_weight": round(freshness_weight, 3),
                "reason": "high_need_low_active_ngo",
            }
        ]

    def _coordination_opportunities(self, community: dict[str, Any], needs: list[dict[str, Any]], event: UnifiedIngestionEvent) -> list[dict[str, Any]]:
        if len(needs) < 2:
            return []

        source_org = str((event.metadata or {}).get("organization_id") or (event.metadata or {}).get("source_org") or event.source)
        target_ngos = list(community.get("target_ngos", []) or [])
        if source_org and target_ngos:
            return [
                {
                    "community_id": community.get("id"),
                    "anchor_org": source_org,
                    "peer_orgs": target_ngos[:3],
                    "shared_needs": [need["need_type"] for need in needs[:3]],
                    "reason": "complementary_program_overlap",
                }
            ]
        return []

    @staticmethod
    def _cosine_similarity(left: list[float], right: list[float]) -> float:
        if not left or not right:
            return 0.0
        denominator_left = math.sqrt(sum(value * value for value in left))
        denominator_right = math.sqrt(sum(value * value for value in right))
        if denominator_left == 0.0 or denominator_right == 0.0:
            return 0.0
        numerator = sum(lhs * rhs for lhs, rhs in zip(left, right))
        return _clamp01(numerator / (denominator_left * denominator_right))

    async def project_event(self, event: UnifiedIngestionEvent, severity_payload: dict[str, Any]) -> CommunityProjection | None:
        projection = self.build_projection(event, severity_payload)
        if projection is None:
            return None

        from pipeline.storage.neo4j_store import neo4j_store
        from pipeline.storage.firestore import firestore_store

        await neo4j_store.upsert_projection(projection)
        await firestore_store.upsert_community_projection(projection)
        return projection


community_graph_service = CommunityGraphService()
