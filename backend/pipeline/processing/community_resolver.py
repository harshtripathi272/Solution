from __future__ import annotations

import json
import logging
import os
import re
from dataclasses import dataclass, field
from difflib import SequenceMatcher
from pathlib import Path
from typing import Any, Optional

logger = logging.getLogger(__name__)

try:
    import spacy  # type: ignore
except ImportError:  # pragma: no cover - optional dependency
    spacy = None


_DEFAULT_SPACY_MODEL = "en_core_web_sm"
_MIN_SCORE = 0.42
_ALLOW_KEYWORD_FALLBACK = os.getenv("COMMUNITY_ALLOW_KEYWORD_FALLBACK", "false").strip().lower() == "true"


@dataclass(slots=True)
class CommunityMatch:
    community: dict[str, Any]
    confidence: float
    match_source: str
    matched_text: str
    matched_terms: list[str] = field(default_factory=list)
    entity_labels: list[str] = field(default_factory=list)
    proximity_hint: str = "village"


class CommunityResolver:
    """Resolve raw text against the canonical target-community registry."""

    def __init__(self, data_file: Optional[Path] = None):
        if data_file is None:
            data_file = Path(__file__).resolve().parents[2] / "data" / "communities.json"

        self.communities: list[dict[str, Any]] = []
        self._nlp = None
        self._spacy_ready = False
        self._load_communities(data_file)
        self._load_spacy()

    def _load_communities(self, data_file: Path) -> None:
        try:
            if data_file.exists():
                with open(data_file, "r", encoding="utf-8") as handle:
                    payload = json.load(handle)
                self.communities = [self._normalize_community(item) for item in payload]
                logger.info("[CommunityResolver] Loaded %d target communities.", len(self.communities))
            else:
                logger.warning("[CommunityResolver] Data file not found at %s", data_file)
        except Exception as exc:
            logger.error("[CommunityResolver] Failed to load communities.json: %s", exc)

    def _load_spacy(self) -> None:
        if spacy is None:
            logger.info("[CommunityResolver] spaCy not installed; using fuzzy matching only.")
            return

        requested_model = os.getenv("COMMUNITY_SPACY_MODEL", _DEFAULT_SPACY_MODEL).strip() or _DEFAULT_SPACY_MODEL
        try:
            self._nlp = spacy.load(requested_model)
            self._spacy_ready = True
            logger.info("[CommunityResolver] spaCy model ready: %s", requested_model)
        except Exception:
            try:
                self._nlp = spacy.blank("en")
                self._spacy_ready = True
                logger.info("[CommunityResolver] Using blank spaCy pipeline for token support.")
            except Exception as exc:  # pragma: no cover - optional dependency failure
                self._nlp = None
                self._spacy_ready = False
                logger.warning("[CommunityResolver] spaCy unavailable: %s", exc)

    @staticmethod
    def _normalize_community(item: dict[str, Any]) -> dict[str, Any]:
        aliases = set()
        # Keep aliases geo-first so resolution is tied to actual community locations.
        aliases.update(CommunityResolver._split_aliases(item.get("name")))
        aliases.update(CommunityResolver._split_aliases(item.get("district")))
        aliases.update(CommunityResolver._split_aliases(item.get("block")))
        aliases.update(CommunityResolver._split_aliases(item.get("region")))
        for extra in item.get("aliases", []) or []:
            aliases.update(CommunityResolver._split_aliases(extra))

        item = dict(item)
        baseline = dict(item.get("default_chronic_baseline") or {})
        baseline.setdefault("malnutrition_rate", 0.0)
        baseline.setdefault("infrastructure_gaps", [])
        baseline.setdefault("vulnerable_groups", [])
        item["default_chronic_baseline"] = baseline
        item.setdefault("keywords", [])
        item.setdefault("target_ngos", [])
        item["aliases"] = sorted({alias for alias in aliases if alias})
        item.setdefault("admin_level", "village")
        return item

    @staticmethod
    def _split_aliases(value: Any) -> set[str]:
        aliases: set[str] = set()
        if isinstance(value, str):
            aliases.add(value.strip())
        elif isinstance(value, list):
            for entry in value:
                aliases.update(CommunityResolver._split_aliases(entry))
        return aliases

    @staticmethod
    def _normalize_text(value: str) -> str:
        return re.sub(r"\s+", " ", value.lower().strip())

    def _extract_entities(self, text: str) -> list[str]:
        if not self._spacy_ready or self._nlp is None:
            return []

        try:
            doc = self._nlp(text[:1500])
        except Exception:
            return []

        entities: list[str] = []
        for ent in getattr(doc, "ents", []):
            if ent.label_ in {"GPE", "LOC", "FAC", "ORG"}:
                cleaned = ent.text.strip()
                if cleaned:
                    entities.append(cleaned)
        return entities

    def _score_community(self, community: dict[str, Any], text: str, entities: list[str]) -> CommunityMatch | None:
        text_lower = self._normalize_text(text)
        aliases = community.get("aliases", []) or []
        matched_terms: list[str] = []
        entity_labels: list[str] = []
        score = 0.0
        match_source = "fuzzy"

        for alias in aliases:
            alias_norm = self._normalize_text(str(alias))
            if not alias_norm:
                continue
            if alias_norm in text_lower:
                matched_terms.append(alias)
                score = max(score, 1.0)
                match_source = "exact"
                continue

            ratio = SequenceMatcher(None, alias_norm, text_lower).ratio()
            if ratio >= 0.72:
                candidate_score = 0.55 + (ratio * 0.35)
                if candidate_score > score:
                    score = candidate_score
                    matched_terms = [alias]
                    match_source = "fuzzy"

        for entity in entities:
            entity_norm = self._normalize_text(entity)
            for alias in aliases:
                alias_norm = self._normalize_text(str(alias))
                if not alias_norm:
                    continue
                if alias_norm in entity_norm or entity_norm in alias_norm:
                    score = max(score, 0.88)
                    entity_labels.append(entity)
                    matched_terms.append(alias)
                    match_source = "ner"

        if _ALLOW_KEYWORD_FALLBACK and not matched_terms and community.get("keywords"):
            keywords = community.get("keywords", []) or []
            for keyword in keywords:
                keyword_norm = self._normalize_text(str(keyword))
                if keyword_norm and keyword_norm in text_lower:
                    matched_terms.append(str(keyword))
                    score = max(score, 0.9)
                    match_source = "keyword"

        if score < _MIN_SCORE:
            return None

        community_result = dict(community)
        if score >= 0.84:
            community_result["admin_level"] = "village"
        elif score >= 0.68:
            community_result["admin_level"] = "block"

        return CommunityMatch(
            community=community_result,
            confidence=round(min(score, 0.99), 3),
            match_source=match_source,
            matched_text=matched_terms[0] if matched_terms else community_result.get("name", ""),
            matched_terms=matched_terms,
            entity_labels=entity_labels,
            proximity_hint=str(community_result.get("admin_level", "village")),
        )

    def resolve_details(self, text: str) -> Optional[CommunityMatch]:
        if not text:
            return None

        entities = self._extract_entities(text)
        best: CommunityMatch | None = None

        for community in self.communities:
            candidate = self._score_community(community, text, entities)
            if candidate is None:
                continue
            if best is None or candidate.confidence > best.confidence:
                best = candidate

        return best

    def resolve(self, text: str) -> Optional[dict[str, Any]]:
        """Return the matching community dict plus resolution metadata."""
        match = self.resolve_details(text)
        if match is None:
            return None

        payload = dict(match.community)
        payload.update(
            {
                "resolution_confidence": match.confidence,
                "resolution_method": match.match_source,
                "matched_text": match.matched_text,
                "matched_terms": match.matched_terms,
                "ner_entities": match.entity_labels,
                "proximity_hint": match.proximity_hint,
            }
        )
        return payload


# Singleton instance for easy import
community_resolver = CommunityResolver()
