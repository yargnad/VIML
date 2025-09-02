# processing.py
import os
import subprocess
import re
import cv2
import face_recognition
import numpy as np
import pickle
from pyannote.audio import Pipeline
from database import get_db_connection

# --- CONFIGURATION ---
# IMPORTANT: Replace with your actual Hugging Face token
HUGGING_FACE_TOKEN = "YOUR_HUGGING_FACE_TOKEN_HERE"
# Assumes a hypothetical FFmpeg v8 with an integrated 'ocr' filter
OCR_CROP_AREA = "1920:200:0:880" # w:h:x:y for a 1080p video's lower third

# Initialize speaker diarization pipeline
try:
    diarization_pipeline = Pipeline.from_pretrained(
        "pyannote/speaker-diarization-3.1",
        use_auth_token=HUGGING_FACE_TOKEN
    )
except Exception as e:
    print(f"Could not load pyannote pipeline. Please check your token. Error: {e}")
    diarization_pipeline = None


def process_video(video_path: str):
    """Orchestrator for the entire video analysis pipeline."""
    print(f"Starting processing for {video_path}...")
    
    base_filename = os.path.basename(video_path)
    
    # --- 1. Asset Extraction ---
    print("Step 1: Extracting audio and frames...")
    audio_path = os.path.join("generated", f"{base_filename}.wav")
    subprocess.run(['ffmpeg', '-i', video_path, '-vn', '-ar', '16000', '-ac', '1', '-y', audio_path], capture_output=True)
    
    # --- 2. Run Recognition Tasks ---
    print("Step 2: Running OCR, Facial, and Speaker Recognition...")
    ocr_results = _run_ocr(video_path)
    face_results = _run_facial_recognition(video_path)
    speaker_results = _run_speaker_diarization(audio_path)
    
    # --- 3. Correlate and Store Data ---
    print("Step 3: Correlating data and storing in database...")
    _correlate_and_store(base_filename, ocr_results, face_results, speaker_results)
    
    # --- 4. Cleanup ---
    print("Step 4: Cleaning up temporary files...")
    os.remove(audio_path)
    print(f"Processing for {video_path} completed.")

def _run_ocr(video_path: str) -> list:
    command = ['ffmpeg', '-i', video_path, '-vf', f'crop={OCR_CROP_AREA},ocr', '-f', 'null', '-']
    proc = subprocess.run(command, capture_output=True, text=True)
    ocr_pattern = re.compile(r"t:\s*([\d.]+)\s*s\s*->\s*text:\s*'(.*?)'")
    matches = ocr_pattern.findall(proc.stderr)
    return [(float(ts), text) for ts, text in matches if text.strip()]

def _run_facial_recognition(video_path: str) -> dict:
    results = {}
    cap = cv2.VideoCapture(video_path)
    fps = cap.get(cv2.CAP_PROP_FPS)
    frame_count = 0
    
    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break
        
        # Process every Nth frame to speed things up
        if frame_count % int(fps) == 0:
            timestamp = frame_count / fps
            rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            
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

def _correlate_and_store(video_filename, ocr_data, face_data, speaker_data):
    """The core logic to link names to faces and voices."""
    conn = get_db_connection()
    cursor = conn.cursor()
    
    known_faces = {} # {person_id: [encodings]}
    speaker_to_person = {} # {speaker_label: person_id}

    # First pass: Use OCR to establish initial identities
    for timestamp, text in ocr_data:
        # Simplistic name extraction; a real app would use NLP
        name = text.strip().title() 
        
        # Find face appearing at the same time
        closest_face_ts = min(face_data.keys(), key=lambda t: abs(t - timestamp))
        if abs(closest_face_ts - timestamp) < 1.0: # 1-second tolerance
            faces_at_time = face_data[closest_face_ts]
            if faces_at_time:
                # Assume the first/largest face is the one named
                face_encoding = faces_at_time[0]['encoding']
                
                # Check if this person already exists for this video
                cursor.execute("SELECT person_id FROM persons WHERE video_path = ? AND name = ?", (video_filename, name))
                person = cursor.fetchone()
                if not person:
                    cursor.execute("INSERT INTO persons (video_path, name) VALUES (?, ?)", (video_filename, name))
                    person_id = cursor.lastrowid
                else:
                    person_id = person['person_id']

                # Store the occurrence
                cursor.execute(
                    "INSERT INTO occurrences (video_path, person_id, timestamp_seconds, method_used, confidence, details) VALUES (?, ?, ?, ?, ?, ?)",
                    (video_filename, person_id, timestamp, 'ocr', 95.0, text)
                )
                
                # Store the identifier
                cursor.execute(
                    "INSERT INTO identifiers (person_id, method, biometric_data) VALUES (?, ?, ?)",
                    (person_id, 'face', pickle.dumps(face_encoding))
                )
                
                if person_id not in known_faces:
                    known_faces[person_id] = []
                known_faces[person_id].append(face_encoding)
                
                # Link speaker label at this time
                for start, end, label in speaker_data:
                    if start <= timestamp <= end and label not in speaker_to_person:
                        speaker_to_person[label] = person_id
                        break
    conn.commit()
    
    # Second pass: Identify known faces throughout the video
    for timestamp, faces in face_data.items():
        for face_info in faces:
            encoding = face_info['encoding']
            
            for person_id, encodings in known_faces.items():
                matches = face_recognition.compare_faces(encodings, encoding)
                if True in matches:
                    cursor.execute(
                        "INSERT INTO occurrences (video_path, person_id, timestamp_seconds, method_used, confidence, details) VALUES (?, ?, ?, ?, ?, ?)",
                        (video_filename, person_id, timestamp, 'face', 90.0, str(face_info['location']))
                    )
                    break # Found a match, move to next face
    conn.commit()
    
    # Third pass: Log all speaker occurrences
    for start, end, label in speaker_data:
        if label in speaker_to_person:
            person_id = speaker_to_person[label]
            # Log an occurrence at the start of their speech segment
            cursor.execute(
                "INSERT INTO occurrences (video_path, person_id, timestamp_seconds, method_used, confidence, details) VALUES (?, ?, ?, ?, ?, ?)",
                (video_filename, person_id, start, 'voice', 85.0, f"Speaks until {end:.2f}s")
            )
    conn.commit()
    conn.close()