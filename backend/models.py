from pydantic import BaseModel, EmailStr
from typing import Optional
from enum import Enum
from datetime import datetime

class UserRole(str, Enum):
    coordinator = "coordinator"
    ngo_worker = "ngo_worker"
    volunteer = "volunteer"

class UserProfile(BaseModel):
    uid: str
    email: Optional[EmailStr] = None
    role: UserRole
    organization_id: Optional[str] = None
    is_verified: bool = False
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
