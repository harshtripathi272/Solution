from pydantic import BaseModel, EmailStr, Field
from typing import Optional
from enum import Enum
from datetime import datetime

class UserRole(str, Enum):
    platform_admin = "platform_admin"
    coordinator = "coordinator"
    ngo_admin = "ngo_admin"
    ngo_worker = "ngo_worker"
    volunteer = "volunteer"

class UserProfile(BaseModel):
    uid: str
    name: Optional[str] = None
    email: Optional[EmailStr] = None
    role: UserRole
    organization_id: Optional[str] = None
    phone: Optional[str] = None
    location: Optional[str] = None
    skills: list[str] = Field(default_factory=list)
    is_available: bool = True
    is_verified: bool = False
    is_independent: bool = False
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

class OrganizationProfile(BaseModel):
    id: str  # Site-issued 8-digit organization code (share with volunteers at sign-up)
    name: str
    mission: Optional[str] = None
    region: Optional[str] = None
    regions: list[str] = Field(default_factory=list)
    admin_uids: list[str] = Field(default_factory=list)
    is_active: bool = True
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
