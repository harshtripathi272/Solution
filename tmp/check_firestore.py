import firebase_admin
from firebase_admin import credentials, firestore
import os
from pathlib import Path

def check_firestore():
    # Use the default credentials or path from env
    cred_path = os.getenv("FIREBASE_CREDENTIALS_PATH", "backend/firebase_service_account.json")
    if not os.path.exists(cred_path):
        # try without backend prefix if working dir is backend
        cred_path = "firebase_service_account.json"
        
    if not os.path.exists(cred_path):
        print(f"Credentials not found at {cred_path}")
        return

    cred = credentials.Certificate(cred_path)
    if not firebase_admin._apps:
        firebase_admin.initialize_app(cred)
    
    db = firestore.client()
    docs = db.collection("need_regions").limit(5).get()
    
    print(f"Found {len(docs)} documents in 'need_regions'")
    for doc in docs:
        print(f"Doc ID: {doc.id}, Data: {doc.to_dict().get('last_updated')}")

if __name__ == "__main__":
    check_firestore()
