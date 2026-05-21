import os
import json
import logging
from pathlib import Path
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from typing import List
from models import UserProfile, UserRole

from dotenv import load_dotenv
load_dotenv()  # Load environment variables from .env file if present

logger = logging.getLogger(__name__)


def _resolve_credentials_path(raw_path: str) -> Path | None:
    """Resolve service account path across common runtime working directories."""
    if not raw_path:
        return None
    candidate = Path(raw_path)
    if candidate.is_absolute() and candidate.exists():
        return candidate

    backend_dir = Path(__file__).resolve().parent
    project_root = backend_dir.parent  # one level above backend/
    candidates = [
        Path.cwd() / raw_path,
        backend_dir / raw_path,
        backend_dir / candidate.name,
        project_root / raw_path,        # handles ./backend/... relative to project root
        project_root / candidate.name,
    ]
    for path in candidates:
        if path.exists():
            return path
    return None


# ---------------------------------------------------------------------------
# Lazy Firebase initialiser
# ---------------------------------------------------------------------------
# We defer ALL heavy firebase_admin submodule imports (credentials, auth,
# firestore) to first use so that importing this module does not trigger
# the gRPC / google-auth cold-start (~4-5 s) that was hanging uvicorn.
# ---------------------------------------------------------------------------

_firebase_app_initialized = False

def _ensure_firebase_app() -> None:
    """Initialize the Firebase Admin app exactly once, lazily."""
    global _firebase_app_initialized
    if _firebase_app_initialized:
        return
    _firebase_app_initialized = True

    import firebase_admin
    from firebase_admin import credentials as _creds

    if firebase_admin._apps:
        return  # already initialized by another module

    cred_path_raw = os.getenv("FIREBASE_CREDENTIALS_PATH", "firebase_service_account.json").strip(' "\'\r\n')
    cred_path = _resolve_credentials_path(cred_path_raw)

    if cred_path is not None:
        firebase_admin.initialize_app(_creds.Certificate(str(cred_path)))
        try:
            with cred_path.open("r", encoding="utf-8") as fh:
                project_id = (json.load(fh) or {}).get("project_id", "unknown")
            logger.info("Firebase initialized with service account: %s (project=%s)", cred_path, project_id)
        except Exception:
            logger.info("Firebase initialized with service account: %s", cred_path)
    else:
        firebase_admin.initialize_app()
        logger.warning(
            "FIREBASE_CREDENTIALS_PATH not found (%s). Falling back to Application Default Credentials.",
            cred_path_raw,
        )


# Lazy Firestore db proxy — defers firestore.client() to first API request.
_db = None

def _get_db():
    global _db
    if _db is None:
        _ensure_firebase_app()
        from firebase_admin import firestore as _fs
        _db = _fs.client()
    return _db


class _LazyDb:
    """Proxy that defers firestore.client() until first attribute access."""
    def __getattr__(self, name):
        return getattr(_get_db(), name)


# `firestore` sentinel for SERVER_TIMESTAMP and other module-level constants
# used in main.py as `firestore.SERVER_TIMESTAMP`.
class _LazyFirestore:
    def __getattr__(self, name):
        _ensure_firebase_app()
        from firebase_admin import firestore as _fs
        return getattr(_fs, name)


db = _LazyDb()
firestore = _LazyFirestore()
security = HTTPBearer()


def get_current_user_token(credentials: HTTPAuthorizationCredentials = Depends(security)):
    """Verifies Firebase ID token and returns decoded token dict."""
    token = credentials.credentials
    try:
        _ensure_firebase_app()
        from firebase_admin import auth as _firebase_auth
        decoded_token = _firebase_auth.verify_id_token(token)
        return decoded_token
    except Exception as e:
        logger.warning("Firebase ID token verification failed: %s", e)
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
        # [DEVELOPMENT BYPASS] Commenting out to allow local coordinator testing
        # if not user.is_verified and user.role in [UserRole.coordinator, UserRole.ngo_worker]:
        #     raise HTTPException(
        #         status_code=status.HTTP_403_FORBIDDEN,
        #         detail="User account is pending admin verification for this role."
        #     )
        return user
