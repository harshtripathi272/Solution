import os
import firebase_admin
from firebase_admin import credentials, auth as firebase_auth, firestore
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from typing import List
from models import UserProfile, UserRole

# Initialize Firebase Admin
cred_path = os.getenv("FIREBASE_CREDENTIALS_PATH", "firebase_service_account.json")
if os.path.exists(cred_path):
    cred = credentials.Certificate(cred_path)
    if not firebase_admin._apps:
        firebase_admin.initialize_app(cred)
else:
    # Use default credentials to allow startup without breaking if json is missing
    if not firebase_admin._apps:
        firebase_admin.initialize_app()

db = firestore.client()
security = HTTPBearer()

def get_current_user_token(credentials: HTTPAuthorizationCredentials = Depends(security)):
    """Verifies Firebase ID token and returns decoded token dict."""
    token = credentials.credentials
    try:
        decoded_token = firebase_auth.verify_id_token(token)
        return decoded_token
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )

def get_current_user(decoded_token: dict = Depends(get_current_user_token)) -> UserProfile:
    """Fetches UserProfile from Firestore based on the verified token's UID."""
    uid = decoded_token.get("uid")
    if not uid:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token: No UID found")
    
    user_doc = db.collection("users").document(uid).get()
    
    if not user_doc.exists:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, 
            detail="User profile not found in Firestore. Please register first."
        )
        
    user_data = user_doc.to_dict()
    user_data["uid"] = uid
    
    # Use token email if not exist in DB
    if "email" not in user_data and "email" in decoded_token:
        user_data["email"] = decoded_token["email"]
        
    try:
        return UserProfile(**user_data)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, 
            detail=f"Invalid user profile format in database: {str(e)}"
        )

class RoleChecker:
    """Dependency class to check user roles."""
    def __init__(self, allowed_roles: List[UserRole]):
        self.allowed_roles = allowed_roles

    def __call__(self, user: UserProfile = Depends(get_current_user)) -> UserProfile:
        if user.role not in self.allowed_roles:
            allowed_str = ", ".join([r.value for r in self.allowed_roles])
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Operation not permitted. Requires one of: [{allowed_str}]"
            )
            
        # Optional: Require explicit verification for high-level roles
        if not user.is_verified and user.role in [UserRole.coordinator, UserRole.ngo_worker]:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="User account is pending admin verification for this role."
            )
        return user
