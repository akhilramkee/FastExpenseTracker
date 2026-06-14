import time
import httpx

BASE_URL = "http://127.0.0.1:8080"

def test_health():
    print("Testing /health endpoint...")
    try:
        response = httpx.get(f"{BASE_URL}/health")
        print(f"Health check status code: {response.status_code}")
        print(f"Response body: {response.json()}")
        return response.status_code == 200
    except Exception as e:
        print(f"Error testing health: {e}")
        return False

def test_sync():
    print("\nTesting /api/v1/sync endpoint...")
    payload = {
        "transactions": [
            {
                "id": "test-tx-uuid-12345",
                "raw_input": "1450 zoom subscription renewal @work",
                "amount": 1450.00,
                "description": "zoom subscription renewal",
                "tag": "work",
                "sync_status": "pending",
                "created_at": "2026-06-13T12:00:00Z"
            }
        ]
    }
    
    try:
        response = httpx.post(f"{BASE_URL}/api/v1/sync", json=payload)
        print(f"Sync status code: {response.status_code}")
        print(f"Response body: {response.json()}")
        
        if response.status_code != 202:
            return False
            
        # Poll the status endpoint to verify background enrichment
        tx_id = payload["transactions"][0]["id"]
        for attempt in range(1, 16):
            print(f"Attempt {attempt}: Checking sync status for transaction {tx_id}...")
            status_response = httpx.get(f"{BASE_URL}/api/v1/sync/status?ids={tx_id}")
            if status_response.status_code == 200:
                data = status_response.json()
                if data:
                    tx = data[0]
                    print(f"Current sync_status: {tx.get('sync_status')}")
                    print(f"Enriched details - Merchant: {tx.get('merchant')}, Category: {tx.get('tag')}, Confidence: {tx.get('ai_confidence')}, Recurring: {tx.get('is_recurring')}")
                    if tx.get('sync_status') in ('completed', 'failed'):
                        break
            time.sleep(2)
            
        return True
    except Exception as e:
        print(f"Error testing sync: {e}")
        return False

if __name__ == "__main__":
    print("Expense Tracker Server Integration Test")
    print("=======================================")
    if test_health():
        test_sync()
    else:
        print("Server is not running. Please start the FastAPI server first.")
