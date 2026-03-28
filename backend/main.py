from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from typing import Dict
from datetime import datetime, timezone, timedelta
import logging
from contextlib import asynccontextmanager
import asyncio
import os

from auth import get_current_user, get_current_user_token, RoleChecker, db, firestore
from models import UserProfile, UserRole
from pydantic import BaseModel, Field

# Pipeline Imports
from pipeline.orchestrators.validation import validation_service
from pipeline.orchestrators.allocation import allocation_engine
from pipeline.ingestors.manager import ingestion_manager
from pipeline.storage.location import location_store
from pipeline.orchestrators.unified import unified_pipeline

class RegisterRequest(BaseModel):
    requested_role: str = "volunteer"

class LocationUpdate(BaseModel):
    latitude: float
    longitude: float
    timestamp: datetime | None = None
    skills: list[str] = Field(default_factory=list)
    consent: bool = True  # Must be True for backend to store location

class ProfileUpdate(BaseModel):
    name: str | None = None
    phone: str | None = None
    location: str | None = None
    skills: list[str] | None = None
    organization_id: str | None = None
    is_available: bool | None = None


class SurveyIngestRequest(BaseModel):
    file_path: str

# Configure basic logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("---| Booting SevaSetu Crisis Intelligence Pipeline |---")
    validation_service.start()
    allocation_engine.start()
    unified_pipeline.start()        # data unification + persistent storage
    ingestion_manager.start()
    yield
    await ingestion_manager.stop()
    logger.info("---| Shutting down Crisis Pipeline |---")

app = FastAPI(
    title="SevaSetu Backend APIs",
    description="Backend API with Firebase Authentication and Crisis Pipeline",
    version="1.0.0",
    lifespan=lifespan
)

# CORS Middleware config
_cors_origins_raw = os.getenv("CORS_ALLOWED_ORIGINS", "*").strip()
_allow_origins = [origin.strip() for origin in _cors_origins_raw.split(",") if origin.strip()] or ["*"]
_allow_credentials = not (len(_allow_origins) == 1 and _allow_origins[0] == "*")

app.add_middleware(
    CORSMiddleware,
    allow_origins=_allow_origins,
    allow_credentials=_allow_credentials,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
def health_check():
    return {"status": "ok", "message": "SevaSetu backend is running"}

@app.post("/api/v1/auth/register", response_model=UserProfile)
def register_user(req: RegisterRequest, decoded_token: dict = Depends(get_current_user_token)):
    """
    Called by the client immediately after Firebase Auth sign-up.
    Creates a new user profile in the Firestore 'users' collection with the requested role if it doesn't exist.
    """
    uid = decoded_token.get("uid")
    email = decoded_token.get("email")
    
    user_ref = db.collection("users").document(uid)
    user_doc = user_ref.get()
    
    if user_doc.exists:
        logger.info(f"User {uid} already exists.")
        return UserProfile(**user_doc.to_dict(), uid=uid)
        
    logger.info(f"Registering new user profile for UID: {uid} with requested role: {req.requested_role}")
    
    requested_role_str = req.requested_role.split('.')[-1]
    role_map = {
        "coordinator": UserRole.coordinator.value,
        "ngoWorker": UserRole.ngo_worker.value,
        "ngo_worker": UserRole.ngo_worker.value,
        "volunteer": UserRole.volunteer.value,
    }
    assigned_role = role_map.get(requested_role_str, UserRole.volunteer.value)
    
    new_user_data = {
        "email": email,
        "role": assigned_role,
        "organization_id": None,
        "is_verified": True if assigned_role == UserRole.volunteer.value else False,
        "created_at": firestore.SERVER_TIMESTAMP,
        "updated_at": firestore.SERVER_TIMESTAMP
    }
    
    try:
        user_ref.set(new_user_data)
    except Exception as e:
        logger.error(f"Failed to create user in Firestore: {str(e)}")
        raise HTTPException(status_code=500, detail="Database write failed")
        
    # Return immediately, mocked timestamps for response
    new_user_data["uid"] = uid
    new_user_data["created_at"] = datetime.now(timezone.utc)
    new_user_data["updated_at"] = datetime.now(timezone.utc)
    
    return UserProfile(**new_user_data)

@app.get("/api/v1/profile", response_model=UserProfile)
def get_profile(current_user: UserProfile = Depends(get_current_user)):
    """Fetch current user's profile verified via Firebase ID Token"""
    return current_user

@app.post("/api/v1/location/update")
def update_location(loc: LocationUpdate, decoded_token: dict = Depends(get_current_user_token)):
    """
    Ephemerally streams volunteer GPS to Redis (GEO-indexed, TTL 2 hrs).
    Data is NOT written to the permanent database – privacy by design.
    Enforces: explicit consent flag, coordinate validation, rate limiting.
    """
    # Explicit consent gate
    if not loc.consent:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Location sharing consent required. Enable tracking in the app first."
        )

    uid = decoded_token.get("uid")
    update_time = loc.timestamp or datetime.now(timezone.utc)

    stored = location_store.update_location(
        user_id=uid,
        lat=loc.latitude,
        lon=loc.longitude,
        timestamp=update_time,
        skills=loc.skills
    )

    if not stored:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Location update throttled or coordinates invalid. Try again shortly."
        )

    return {
        "status": "ok",
        "cached_until": (datetime.now(timezone.utc) + timedelta(hours=2)).isoformat(),
    }

@app.delete("/api/v1/location/revoke")
def revoke_location(decoded_token: dict = Depends(get_current_user_token)):
    """
    Allows volunteers to immediately delete their location from Redis.
    Implements the 'right to be forgotten' for real-time tracking data.
    """
    uid = decoded_token.get("uid")
    location_store.remove_user(uid)
    return {"status": "ok", "message": "Your location data has been permanently deleted."}


@app.post("/api/v1/ingestion/survey")
async def ingest_survey_data(
    payload: SurveyIngestRequest,
    current_user: UserProfile = Depends(RoleChecker([UserRole.ngo_worker, UserRole.coordinator]))
):
    """On-demand local CSV/JSON ingestion for NGO survey or field data."""
    try:
        count = await ingestion_manager.ingest_survey_file(payload.file_path)
        return {
            "status": "ok",
            "ingested": count,
            "file_path": payload.file_path,
            "requested_by": current_user.uid,
        }
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception as exc:
        logger.error("Survey ingestion failed: %s", exc)
        raise HTTPException(status_code=500, detail="Survey ingestion failed")

@app.put("/api/v1/profile/update")
def update_user_profile(profile: ProfileUpdate, decoded_token: dict = Depends(get_current_user_token)):
    """
    Update user profile information (name, phone, location, skills, organization, availability).
    Called by Flutter app when user edits their profile.
    """
    uid = decoded_token.get("uid")
    
    try:
        user_ref = db.collection("users").document(uid)
        update_data = {
            "updated_at": firestore.SERVER_TIMESTAMP,
        }

        # Add required/optional fields only when provided.
        if profile.name is not None:
            update_data["name"] = profile.name
        
        # Add optional fields if provided
        if profile.phone is not None:
            update_data["phone"] = profile.phone
        if profile.location is not None:
            update_data["location"] = profile.location
        if profile.skills is not None:
            update_data["skills"] = profile.skills
        if profile.organization_id is not None:
            update_data["organization_id"] = profile.organization_id
        if profile.is_available is not None:
            update_data["is_available"] = profile.is_available

        if len(update_data) == 1:
            raise HTTPException(status_code=400, detail="No profile fields provided for update")
            
        user_ref.update(update_data)
        
        logger.info(f"Profile updated for user {uid}")
        return {"status": "ok", "message": "Profile updated successfully"}
    except Exception as e:
        logger.error(f"Failed to update profile for user {uid}: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Failed to update profile: {str(e)}")

# --- RBAC Protected Endpoints ---
@app.get("/api/v1/alerts")
def get_global_alerts(current_user: UserProfile = Depends(RoleChecker([UserRole.coordinator]))):
    """Only Coordinators can access global alerts"""
    return {
        "message": "Global alerts accessed successfully. This implies critical information.",
        "user_role": current_user.role.value
    }

@app.post("/api/v1/reports")
def submit_report(current_user: UserProfile = Depends(RoleChecker([UserRole.ngo_worker, UserRole.coordinator]))):
    """Only NGO Workers and Coordinators can submit official reports"""
    # Requires organization check logic in practical application
    return {
        "message": "Report submitted successfully.", 
        "organization": current_user.organization_id
    }

@app.get("/api/v1/tasks")
def get_tasks(current_user: UserProfile = Depends(RoleChecker([UserRole.volunteer, UserRole.ngo_worker, UserRole.coordinator]))):
    """Volunteers can view tasks, as can everyone else above them"""
    return {
        "message": f"Tasks accessed for user ({current_user.uid})."
    }
