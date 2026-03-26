from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from typing import Dict
from datetime import datetime, timezone
import logging

from auth import get_current_user, get_current_user_token, RoleChecker, db, firestore
from models import UserProfile, UserRole
from pydantic import BaseModel

class RegisterRequest(BaseModel):
    requested_role: str = "volunteer"

# Configure basic logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="SevaSetu Backend APIs",
    description="Backend API with Firebase Authentication and RBAC",
    version="1.0.0"
)

# CORS Middleware config
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
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
