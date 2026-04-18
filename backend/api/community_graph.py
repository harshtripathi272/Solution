from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query

from auth import RoleChecker
from models import UserProfile, UserRole
from pipeline.processing.community_resolver import community_resolver
from pipeline.storage import firestore_store

router = APIRouter(prefix="/api/v1/community-graph", tags=["community-graph"])


def _as_iso(value: Any) -> str | None:
    if isinstance(value, datetime):
        return value.astimezone(timezone.utc).isoformat()
    if isinstance(value, str) and value:
        return value
    return None


def _fallback_profile(community: dict[str, Any]) -> dict[str, Any]:
    baseline = community.get("default_chronic_baseline", {}) or {}
    return {
        "community": {
            "id": community.get("id"),
            "name": community.get("name"),
            "region": community.get("region"),
            "district": community.get("district"),
            "block": community.get("block"),
            "latitude": community.get("latitude"),
            "longitude": community.get("longitude"),
            "keywords": community.get("keywords", []),
            "target_ngos": community.get("target_ngos", []),
            "baseline": baseline,
            "freshness_weight": 1.0,
            "admin_level": "village",
            "resolution_confidence": 0.0,
        },
        "report": {},
        "ngo": {},
        "needs": [],
        "resources": [],
        "similarity": [],
        "coverage_gaps": [],
        "coordination_opportunities": [],
        "matrix": [],
        "provenance": {
            "source": "canonical_registry",
            "updated_at": None,
        },
    }


def _normalize_profile(payload: dict[str, Any]) -> dict[str, Any]:
    report = payload.get("report") or {}
    return {
        "community": payload.get("community") or {},
        "report": report,
        "ngo": payload.get("ngo") or {},
        "needs": payload.get("needs") or [],
        "resources": payload.get("resources") or [],
        "similarity": payload.get("similarity") or [],
        "coverage_gaps": payload.get("coverage_gaps") or [],
        "coordination_opportunities": payload.get("coordination_opportunities") or [],
        "matrix": payload.get("matrix") or [],
        "provenance": payload.get("provenance") or {},
        "updated_at": _as_iso(payload.get("updated_at")),
        "last_verified_at": _as_iso(report.get("timestamp")),
    }


@router.get("/overview")
async def community_graph_overview(
    limit: int = Query(default=12, ge=1, le=50),
    current_user: UserProfile = Depends(RoleChecker([UserRole.coordinator, UserRole.ngo_worker, UserRole.volunteer])),
):
    docs = await firestore_store.list_community_projections(limit=limit)
    if not docs:
        docs = [_fallback_profile(community) for community in community_resolver.communities[:limit]]

    profiles = [_normalize_profile(doc) for doc in docs]
    matrix = [
        {
            "community_id": profile.get("community", {}).get("id"),
            "community_name": profile.get("community", {}).get("name"),
            "needs": profile.get("matrix", []),
        }
        for profile in profiles
    ]
    coverage_gaps = [gap for profile in profiles for gap in profile.get("coverage_gaps", [])]
    coordination_opportunities = [item for profile in profiles for item in profile.get("coordination_opportunities", [])]

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "profiles": profiles,
        "matrix": matrix,
        "coverage_gaps": coverage_gaps,
        "coordination_opportunities": coordination_opportunities,
        "requested_by": current_user.uid,
    }


@router.get("/{community_id}")
async def community_graph_profile(
    community_id: str,
    current_user: UserProfile = Depends(RoleChecker([UserRole.coordinator, UserRole.ngo_worker, UserRole.volunteer])),
):
    payload = await firestore_store.get_community_projection(community_id)
    if payload is None:
        community = next((item for item in community_resolver.communities if item.get("id") == community_id), None)
        if community is None:
            raise HTTPException(status_code=404, detail="Community not found")
        payload = _fallback_profile(community)

    profile = _normalize_profile(payload)
    profile["requested_by"] = current_user.uid
    return profile
