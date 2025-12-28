import time
import json
import os
import requests
import feedparser
import threading
import subprocess
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

API_URL = "http://127.0.0.1:5000/v1/process"
PROFILES_FILE = "profiles.json"
CHECK_INTERVAL = 30 # For polling loops if needed, though Feedparser has its own sleep

class IngestionHandler(FileSystemEventHandler):
    def __init__(self, profile):
        self.profile = profile
        self.config = json.dumps(profile.get("workflow_config", {}))

    def on_created(self, event):
        if event.is_directory:
            return
        # Basic filtering for video files
        if not event.src_path.lower().endswith(('.mp4', '.mkv', '.mov', '.webm', '.avi')):
            return
            
        print(f"[{self.profile['name']}] New file detected: {event.src_path}")
        self.upload_file(event.src_path)

    def upload_file(self, file_path):
        # Retry logic could be added here
        print(f"[{self.profile['name']}] Uploading to Core API...")
        try:
            with open(file_path, 'rb') as f:
                files = {'video': f}
                data = {'config': self.config}
                resp = requests.post(API_URL, files=files, data=data)
                
            if resp.status_code == 202:
                job_id = resp.json()['job_id']
                print(f"[{self.profile['name']}] Job initiated: {job_id}")
            else:
                print(f"[{self.profile['name']}] Upload failed: {resp.text}")
        except Exception as e:
            print(f"[{self.profile['name']}] Error: {e}")

class MRSSPoller(threading.Thread):
    def __init__(self, profile):
        super().__init__()
        self.profile = profile
        self.url = profile['url']
        self.interval = profile.get('interval_seconds', 300)
        self.seen_entries = set()
        self.config = json.dumps(profile.get("workflow_config", {}))
        self.daemon = True

    def run(self):
        print(f"[{self.profile['name']}] Starting MRSS Poller on {self.url}")
        while True:
            try:
                feed = feedparser.parse(self.url)
                for entry in feed.entries:
                    if entry.id in self.seen_entries:
                        continue
                    
                    self.seen_entries.add(entry.id)
                    # Find video link
                    video_url = None
                    # Try enclosure
                    for enclosure in entry.get('enclosures', []):
                         if enclosure.type.startswith('video/'):
                             video_url = enclosure.href
                             break
                    
                    if not video_url:
                        # Fallback logic could go here
                        print(f"[{self.profile['name']}] No video found for {entry.title}")
                        continue
                        
                    print(f"[{self.profile['name']}] Found new video: {entry.title}")
                    self.download_and_process(video_url, entry.title)
                    
            except Exception as e:
                 print(f"[{self.profile['name']}] Poll error: {e}")
                 
            time.sleep(self.interval)

    def download_and_process(self, url, title):
        # Clean title for filename
        clean_title = "".join(x for x in title if x.isalnum() or x in "._- ")
        filename = f"{clean_title}.mp4"
        temp_path = os.path.join("downloads_temp", filename)
        os.makedirs("downloads_temp", exist_ok=True)
        
        print(f"[{self.profile['name']}] Downloading {url}...")
        try:
            # simple curl or requests download
            subprocess.run(['curl', '-L', '-o', temp_path, url], check=True)
            
            # Now upload
            print(f"[{self.profile['name']}] Uploading downloaded file...")
            with open(temp_path, 'rb') as f:
                files = {'video': f}
                data = {'config': self.config}
                resp = requests.post(API_URL, files=files, data=data)
                
            if resp.status_code == 202:
                print(f"[{self.profile['name']}] Job initiated: {resp.json()['job_id']}")
            
            # Cleanup
            os.remove(temp_path)
            
        except Exception as e:
            print(f"[{self.profile['name']}] Download/Process failed: {e}")

def main():
    if not os.path.exists(PROFILES_FILE):
        print("profiles.json not found")
        return

    profiles = json.load(open(PROFILES_FILE))
    observers = []
    pollers = []

    for profile in profiles:
        if profile['type'] == 'folder':
            path = profile['path']
            if not os.path.exists(path):
                print(f"Warning: Watch folder {path} does not exist, creating it.")
                os.makedirs(path, exist_ok=True)
                
            event_handler = IngestionHandler(profile)
            observer = Observer()
            observer.schedule(event_handler, path, recursive=False)
            observer.start()
            observers.append(observer)
            print(f"[{profile['name']}] Watching {path}")
            
        elif profile['type'] == 'mrss':
            poller = MRSSPoller(profile)
            poller.start()
            pollers.append(poller)

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        for o in observers:
            o.stop()
        for o in observers:
            o.join()

if __name__ == "__main__":
    main()
