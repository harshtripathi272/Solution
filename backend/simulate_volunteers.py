import asyncio
import httpx
import logging
from datetime import datetime, timezone
import random

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

API_URL = "http://127.0.0.1:8000/api/v1/location/update"

async def simulate_volunteer(user_id: str, start_lat: float, start_lon: float, skills: list, token: str):
    logger.info(f"Starting simulation for volunteer {user_id}")
    lat, lon = start_lat, start_lon
    
    async with httpx.AsyncClient() as client:
        while True:
            # Simulate slight movement (random walk)
            lat += random.uniform(-0.01, 0.01)
            lon += random.uniform(-0.01, 0.01)
            
            payload = {
                "latitude": lat,
                "longitude": lon,
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "skills": skills
            }
            headers = {"Authorization": f"Bearer {token}"}
            
            try:
                # Assuming the token signature verification is bypassed for local dev/simulator,
                # or we just need an explicit token to test. 
                # For this simulator to work without generating real Firebase ID tokens, 
                # the backend auth setup usually needs a backdoor or mock user dependency.
                res = await client.post(API_URL, json=payload, headers=headers)
                if res.status_code == 200:
                    logger.debug(f"{user_id} successfully pinged location: {lat:.4f}, {lon:.4f}")
                else:
                    logger.error(f"{user_id} failed to ping: {res.status_code} - {res.text}")
            except Exception as e:
                logger.error(f"{user_id} connection error: {e}")
                
            # Random wait between 10 to 30 seconds
            await asyncio.sleep(random.uniform(10, 30))

async def main():
    # Because our fastapi backend strictly requires Firebase Bearer tokens,
    # running this script effectively requires REAL id tokens from the flutter app.
    # To use this simulator truly standalone, you would pass a valid token printed from the app console here.
    test_token = input("Please paste your Firebase Bearer ID Token to simulate a fleet moving: ").strip()
    
    if not test_token:
        logger.error("No token provided. Cannot simulate authenticated traffic.")
        return

    logger.info("Initializing simulated volunteer fleet...")
    
    # Spawn 3 simulated volunteers near New Delhi, India
    tasks = [
        asyncio.create_task(simulate_volunteer("sim_vol_1", 28.6139, 77.2090, ["medical", "rescue"], test_token)),
        asyncio.create_task(simulate_volunteer("sim_vol_2", 28.5355, 77.3910, ["logistics"], test_token)),
        asyncio.create_task(simulate_volunteer("sim_vol_3", 28.4595, 77.0266, ["counseling"], test_token)),
    ]
    
    await asyncio.gather(*tasks)

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Simulation terminated.")
