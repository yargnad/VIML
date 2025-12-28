import requests
import time
import os

BASE_URL = "http://localhost:5000"

def run_test():
    print("--- Starting End-to-End Verification ---")

    # 1. Create Mock Video File
    with open("test_video.mp4", "wb") as f:
        f.write(b"mock_video_content")

    # 2. Upload Video
    print("[1] Uploading video...")
    with open("test_video.mp4", "rb") as f:
        files = {"video": f}
        # Explicitly set auto_approve to False to test Pending queue
        data = {"config": '{"auto_approve": false, "crops": {"ocr": {"x":0, "y":0, "w":100, "h":100}}}'}
        try:
            res = requests.post(f"{BASE_URL}/v1/process", files=files, data=data)
            if res.status_code != 202:
                print(f"❌ Upload Failed: {res.text}")
                return
            job = res.json()
            job_id = job['job_id']
            print(f"✅ Job Created: {job_id}")
        except Exception as e:
            print(f"❌ Connection Error: {e}")
            return

    # 3. Poll Status
    print("[2] Polling Job Status...")
    for i in range(20):
        res = requests.get(f"{BASE_URL}/v1/jobs/{job_id}")
        status = res.json()
        s = status['status']
        print(f"   Status: {s}")
        if s == 'completed':
            print("✅ Job Completed")
            break
        if s == 'failed':
            print(f"❌ Job Failed: {status.get('result')}")
            return
        time.sleep(2)
    
    # 4. Check Queue (Pending)
    print("[3] Checking Review Queue (Pending)...")
    res = requests.get(f"{BASE_URL}/v1/review/queue?status=pending&grouped=true")
    queue = res.json()
    
    hosts = len(queue.get('hosts', []))
    guests = len(queue.get('guests', []))
    total = hosts + guests
    
    print(f"   Found {total} items ({hosts} hosts, {guests} guests)")
    
    if total > 0:
        print("✅ Review Queue Populated")
    else:
        print("❌ Review Queue Empty (Expected Mock Data)")

if __name__ == "__main__":
    run_test()
