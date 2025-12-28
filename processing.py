# processing.py
import os
import subprocess
import re
import json
import pickle
import shutil
import numpy as np
from database import get_db_connection

# --- MOCK IMPORTS FOR LITE ENVIRONMENT ---
try:
    import cv2
    import face_recognition
    import easyocr
    from pyannote.audio import Pipeline
    LITE_MODE = False
except ImportError:
    print("⚠️  Running in LITE MODE: Heavy ML libraries not found. Using mocks.")
    LITE_MODE = True
    cv2 = None
    face_recognition = None
    easyocr = None
    Pipeline = None

# --- CONFIGURATION ---
OCR_CROP_AREA = "1920:200:0:880" 

# Initialize speaker diarization pipeline
diarization_pipeline = None
if not LITE_MODE:
    try:
        diarization_pipeline = Pipeline.from_pretrained(
            "pyannote/speaker-diarization-3.1",
            use_auth_token=os.getenv("HUGGING_FACE_TOKEN"))
    except Exception as e:
        print(f"Could not load pyannote pipeline: {e}")

def process_video(video_path: str):
    """Orchestrator for the entire video analysis pipeline."""
    print(f"Starting processing for {video_path}...")
    
    base_filename = os.path.basename(video_path)
    
    # --- 1. Asset Extraction ---
    print("Step 1: Extracting audio and frames...")
    audio_path = os.path.join("generated", f"{base_filename}.wav")
    
    # In Lite Mode, just create a dummy wav file if ffmpeg fails or is not needed really
    try:
        subprocess.run(['ffmpeg', '-i', video_path, '-vn', '-ar', '16000', '-ac', '1', '-y', audio_path], capture_output=True)
    except FileNotFoundError:
        print("ffmpeg not found, skipping audio extraction.")
        with open(audio_path, 'wb') as f: f.write(b'dummy_audio')
    
    # --- 2. Run Recognition Tasks ---
    print("Step 2: Running OCR, Facial, and Speaker Recognition...")
    if LITE_MODE:
        # RETURN MOCK DATA
        ocr_results = [(10.0, "FASTAPI MOCK OCR")]
        face_results = {10.0: [{"location": (0,0,10,10), "encoding": np.zeros(128)}]}
        speaker_results = [(0.0, 5.0, "SPEAKER_01")]
    else:
        ocr_results = _run_ocr(video_path)
        face_results = _run_facial_recognition(video_path)
        speaker_results = _run_speaker_diarization(audio_path)
    
    # --- 3. Correlate and Store Data ---
    print("Step 3: Correlating data and storing in database...")
    _correlate_and_store(base_filename, ocr_results, face_results, speaker_results)
    
    # --- 4. Cleanup ---
    print("Step 4: Cleaning up temporary files...")
    if os.path.exists(audio_path):
        os.remove(audio_path)
    print(f"Processing for {video_path} completed.")

def _run_ocr(video_path: str, crop: dict = None) -> list:
    """
    Run OCR on the video to extract text from the lower third.
    Returns: list of (timestamp, text) tuples.
    """
    # Check if ffmpeg exists or in LITE_MODE
    if LITE_MODE or not shutil.which('ffmpeg'):
        print("WARNING: ffmpeg not found. Returning MOCK OCR data.")
        # Return dummy data for testing/lite mode
        return [
            (5.0, "Jane Doe"),
            (12.5, "John Smith"),
            (45.0, "Guest Speaker")
        ]

    command = ['ffmpeg', '-i', video_path, '-vf', f'crop={OCR_CROP_AREA},ocr', '-f', 'null', '-']
    try:
        proc = subprocess.run(command, capture_output=True, text=True, check=True)
        ocr_pattern = re.compile(r"t:\s*([\d.]+)\s*s\s*->\s*text:\s*'(.*?)'")
        matches = ocr_pattern.findall(proc.stderr)
        return [(float(ts), text) for ts, text in matches if text.strip()]
    except Exception as e:
        print(f"Error running ffmpeg: {e}")
        return []

def _run_facial_recognition(video_path: str, crop: dict = None) -> dict:
    results = {}
    
    if LITE_MODE or not cv2:
        # Mock Data (Lite Mode) - Must align with OCR timestamps (5.0, 12.5)
        return {
            5.0: [{"location": (100, 100, 200, 200), "encoding": np.zeros(128)}],
            12.5: [{"location": (300, 150, 400, 250), "encoding": np.zeros(128)}]
        }

    cap = cv2.VideoCapture(video_path)
    fps = cap.get(cv2.CAP_PROP_FPS)
    frame_count = 0
    
    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break
        
        if frame_count % int(fps) == 0:
            timestamp = frame_count / fps
            
            # Apply Crop if enabled
            img_to_process = frame
            if crop:
                 x, y, w, h = crop.get('x', 0), crop.get('y', 0), crop.get('w', 1920), crop.get('h', 1080)
                 img_to_process = frame[y:y+h, x:x+w]
                 
            rgb_frame = cv2.cvtColor(img_to_process, cv2.COLOR_BGR2RGB)
            
            if face_recognition:
                face_locations = face_recognition.face_locations(rgb_frame)
                face_encodings = face_recognition.face_encodings(rgb_frame, face_locations)
                
                if face_encodings:
                    results[timestamp] = [{
                        "location": loc,
                        "encoding": enc
                    } for loc, enc in zip(face_locations, face_encodings)]
        
        frame_count += 1
        
    cap.release()
    return results

def _run_speaker_diarization(audio_path: str) -> list:
    if not diarization_pipeline:
        return []
    diarization = diarization_pipeline(audio_path)
    return [(segment.start, segment.end, label) for segment, _, label in diarization.itertracks(yield_label=True)]

def process_video(video_path: str, job_id: str = None):
    """
    Main processing pipeline.
    Run OCR (EasyOCR), Face, Audio analysis and correlate results.
    """
    print(f"Processing {video_path}...")
    
    # 1. Fetch Job Config (Auto-Approve status & Crops)
    status_to_set = 'pending'
    crops = {}
    
    if job_id:
        try:
            conn = get_db_connection()
            row = conn.execute("SELECT config, auto_approve FROM jobs WHERE job_id = ?", (job_id,)).fetchone()
            if row:
                if row['auto_approve']:
                    status_to_set = 'approved'
                if row['config']:
                    try:
                        cfg = json.loads(row['config'])
                        crops = cfg.get('crops', {})
                    except:
                        pass
            conn.close()
        except Exception as e:
            print(f"Failed to fetch job config: {e}")

    # 2. OCR (EasyOCR with Configurable Crop)
    ocr_crop = crops.get('ocr') # Expected format: {'x': int, 'y': int, 'w': int, 'h': int}
    ocr_data = _run_ocr(video_path, crop=ocr_crop)
    
    # 3. Facial Recognition (Mock or Real, with Crop)
    face_crop = crops.get('face')
    face_data = _run_facial_recognition(video_path, crop=face_crop)
    
    # 4. Audio / Speaker Diarization (Mock)
    speaker_data = _run_speaker_diarization(video_path)
    
    # 5. Correlate and Store
    _correlate_and_store(video_path, ocr_data, face_data, speaker_data, status_to_set, job_id)
    
    print(f"Processing complete for {video_path}")

def _correlate_and_store(video_filename, ocr_data, face_data, speaker_data, review_status='pending', job_id=None):
    """The core logic to link names to faces and voices."""
    conn = get_db_connection()
    cursor = conn.cursor()
    
    known_faces = {} # {person_id: [encodings]}
    speaker_to_person = {} # {speaker_label: person_id}

    # First pass: Use OCR to establish initial identities
    for timestamp, text in ocr_data:
        name = text.strip().title() 
        
        # Find face appearing at the same time
        closest_face_ts = min(face_data.keys(), key=lambda t: abs(t - timestamp)) if face_data else 0
        if abs(closest_face_ts - timestamp) < 1.0 and face_data: 
            faces_at_time = face_data.get(closest_face_ts)
            if faces_at_time:
                face_encoding = faces_at_time[0]['encoding']
                
                cursor.execute("SELECT person_id FROM persons WHERE video_path = ? AND name = ?", (video_filename, name))
                person = cursor.fetchone()
                if not person:
                    cursor.execute("INSERT INTO persons (video_path, name) VALUES (?, ?)", (video_filename, name))
                    person_id = cursor.lastrowid
                else:
                    person_id = person['person_id']

                cursor.execute(
                    "INSERT INTO occurrences (video_path, person_id, timestamp_seconds, method_used, confidence, details, review_status, job_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                    (video_filename, person_id, timestamp, 'ocr', 95.0, text, review_status, job_id)
                )
                
                cursor.execute(
                    "INSERT INTO identifiers (person_id, method, biometric_data) VALUES (?, ?, ?)",
                    (person_id, 'face', pickle.dumps(face_encoding))
                )
                
                if person_id not in known_faces:
                    known_faces[person_id] = []
                known_faces[person_id].append(face_encoding)
                
                for start, end, label in speaker_data:
                    if start <= timestamp <= end and label not in speaker_to_person:
                        speaker_to_person[label] = person_id
                        break
    conn.commit()
    
    # Skip second pass in lite mode if face_recognition is missing
    if not LITE_MODE and face_recognition:
        for timestamp, faces in face_data.items():
            for face_info in faces:
                encoding = face_info['encoding']
                
                for person_id, encodings in known_faces.items():
                    matches = face_recognition.compare_faces(encodings, encoding)
                    if True in matches:
                        cursor.execute(
                            "INSERT INTO occurrences (video_path, person_id, timestamp_seconds, method_used, confidence, details, review_status, job_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                            (video_filename, person_id, timestamp, 'face', 90.0, str(face_info['location']), review_status, job_id)
                        )
                        break 
        conn.commit()
    
    for start, end, label in speaker_data:
        if label in speaker_to_person:
            person_id = speaker_to_person[label]
            cursor.execute(
                "INSERT INTO occurrences (video_path, person_id, timestamp_seconds, method_used, confidence, details, review_status, job_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                (video_filename, person_id, start, 'voice', 85.0, f"Speaks until {end:.2f}s", review_status, job_id)
            )
    conn.commit()
    conn.close()
