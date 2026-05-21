"""Site-issued numeric organization IDs for NGO ↔ volunteer linking."""

from __future__ import annotations

import re
import secrets

from fastapi import HTTPException, status

from auth import db

_ORG_ID_PATTERN = re.compile(r"^\d{8}$")


def normalize_organization_id(raw: str | None) -> str | None:
    """Strip formatting; return 8-digit code or legacy slug id."""
    if raw is None:
        return None
    token = str(raw).strip().upper().replace("SS-", "").replace(" ", "")
    if not token:
        return None
    if token.isdigit():
        if len(token) != 8:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Organization ID must be exactly 8 digits.",
            )
        return token
    return token.lower()


def allocate_organization_id() -> str:
    """Generate a unique 8-digit organization ID (site-issued)."""
    for _ in range(32):
        candidate = f"{secrets.randbelow(90_000_000) + 10_000_000}"
        if not db.collection("organizations").document(candidate).get().exists:
            return candidate
    raise HTTPException(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        detail="Could not allocate a unique organization ID. Please try again.",
    )


def validate_organization_exists(org_id: str | None) -> str:
    """Ensure the organization ID exists before linking a volunteer or worker."""
    normalized = normalize_organization_id(org_id)
    if not normalized:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Organization ID is required to join an NGO.",
        )
    doc = db.collection("organizations").document(normalized).get()
    if not doc.exists:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Organization ID {normalized} was not found. Check the 8-digit ID from your NGO.",
        )
    return normalized
