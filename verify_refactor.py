import requests
import time
import os
import json

BASE_URL = "http://127.0.0.1:5000"
VIDEO_PATH = "video.webm"

def test_pipeline():
    print(f"Testing pipeline with {VIDEO_PATH}...")
    
    # 1. Upload Video with Config
    config = {
        "auto_approve": False,
        "steps": ["ocr", "face"]
    }
    
    with open(VIDEO_PATH, 'rb') as f:
        files = {'video': f}
        data = {'config': json.dumps(config)} 
        response = requests.post(f"{BASE_URL}/v1/process", files=files, data=data)
    
    if response.status_code != 202:
        print(f"❌ Upload failed: {response.text}")
        return
        
    job_id = response.json()['job_id']
    print(f"✅ Job submitted with config. ID: {job_id}")
    
    # 2. Poll Status
    status_url = f"{BASE_URL}/v1/jobs/{job_id}"
    _wait_for_job(status_url)

def _wait_for_job(status_url):
    for i in range(15):
        resp = requests.get(status_url)
        status = resp.json()['status']
        print(f"poll {i+1}: {status}")
        if status == 'completed':
            print("✅ Job completed successfully!")
            return
        elif status == 'failed':
            print(f"❌ Job failed")
            return
        time.sleep(2)
    print("⚠️ Timeout")

def test_modular():
    print(f"\nTesting modular API...")
    endpoints = ["ocr", "face", "audio"]
    
    for ep in endpoints:
        print(f"Testing /v1/analyze/{ep}...")
        with open(VIDEO_PATH, 'rb') as f:
            files = {'file': f}
            resp = requests.post(f"{BASE_URL}/v1/analyze/{ep}", files=files)
            if resp.status_code == 200:
                print(f"✅ {ep} success")
                # print(resp.json()) 
            else:
                 print(f"❌ {ep} failed: {resp.status_code} {resp.text}")

def test_review_workflow():
    print(f"\nTesting Review Workflow...")
    
    # 1. Get Queue
    resp = requests.get(f"{BASE_URL}/v1/review/queue")
    queue = resp.json()
    print(f"Queue size: {len(queue)}")
    
    if len(queue) > 0:
        item = queue[0]
        occ_id = item['occurrence_id']
        print(f"Approving occurrence {occ_id}...")
        
        # 2. Approve
        patch_resp = requests.patch(f"{BASE_URL}/v1/metadata/{occ_id}", json={
            "review_status": "approved",
            "details": "Human approved via test script"
        })
        
        if patch_resp.status_code == 200:
            print("✅ Approval success")
        else:
            print(f"❌ Approval failed: {patch_resp.text}")
            
    else:
        print("⚠️ Queue empty, skipping approval test (run pipeline first)")

if __name__ == "__main__":
    if not os.path.exists(VIDEO_PATH):
        with open(VIDEO_PATH, 'wb') as f: f.write(b'dummy')
        
    test_pipeline()
    test_modular()
    test_review_workflow()
