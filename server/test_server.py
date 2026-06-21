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

def test_import():
    print("\nTesting /api/v1/import endpoint...")
    payload = {
        "content": "1450 zoom subscription renewal @work\n45.90 dinner @night #food",
        "format": "text",
    }

    try:
        before_response = httpx.get(f"{BASE_URL}/api/v1/sync/status", timeout=10.0)
        before_count = len(before_response.json()) if before_response.status_code == 200 else 0

        response = httpx.post(f"{BASE_URL}/api/v1/import", json=payload, timeout=15.0)
        print(f"Import status code: {response.status_code}")
        print(f"Response body: {response.json()}")

        if response.status_code != 202:
            return False

        data = response.json()
        if data.get("status") != "accepted":
            return False

        print("Import accepted; polling sync/status for background results...")
        for attempt in range(1, 31):
            print(f"Attempt {attempt}: Checking for imported transactions...")
            status_response = httpx.get(f"{BASE_URL}/api/v1/sync/status", timeout=10.0)
            if status_response.status_code == 200:
                rows = status_response.json()
                if len(rows) > before_count:
                    imported = rows[before_count:]
                    print(f"Found {len(imported)} new transaction(s) from import.")
                    for row in imported:
                        print(
                            f"  - {row.get('display_label') or row.get('description')} "
                            f"({row.get('amount')}) status={row.get('sync_status')}"
                        )
                    if all(row.get("sync_status") in ("completed", "failed") for row in imported):
                        return True
            time.sleep(5)

        print("Timed out waiting for imported transactions to appear.")
        return False
    except Exception as e:
        print(f"Error testing import: {e}")
        return False

if __name__ == "__main__":
    print("Expense Tracker Server Integration Test")
    print("=======================================")
    if test_health():
        test_sync()
        test_import()
    else:
        print("Server is not running. Please start the FastAPI server first.")
