from fastapi import FastAPI, File, UploadFile, BackgroundTasks, Form, HTTPException, Request, Query
from fastapi.responses import JSONResponse, FileResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional
import shutil
import os
import uuid
import json
import sqlite3
import subprocess

# Local imports
from database import get_db_connection, init_db
import tasks
from tasks import process_video_task
from processing import _run_ocr, _run_facial_recognition, _run_speaker_diarization
from tasks import process_video_task
from viml_generator import generate_vtt_from_db
# Import processing logic for ephemeral extraction
# Note: In a real microservice, extraction logic might be in a shared lib or separate service
from processing import _run_ocr, _run_facial_recognition, _run_speaker_diarization

app = FastAPI(title="VIML API", version="0.2.0")

# helper to ensure directories exist
UPLOAD_FOLDER = 'uploads'
GENERATED_FOLDER = 'generated'
os.makedirs(UPLOAD_FOLDER, exist_ok=True)
os.makedirs(GENERATED_FOLDER, exist_ok=True)

# --- FRONTEND SETUP ---
app.mount("/static", StaticFiles(directory="viml_ui/static"), name="static")
# Serve uploads for the video player. In production, use Nginx/S3 signed URLs.
app.mount("/files", StaticFiles(directory=UPLOAD_FOLDER), name="files") 
templates = Jinja2Templates(directory="viml_ui/templates")
os.makedirs(UPLOAD_FOLDER, exist_ok=True)
os.makedirs(GENERATED_FOLDER, exist_ok=True)

# --- FRONTEND SETUP ---
app.mount("/static", StaticFiles(directory="viml_ui/static"), name="static")
templates = Jinja2Templates(directory="viml_ui/templates")

# CORS (Open by default for prototype)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- Pydantic Models ---
class JobStatus(BaseModel):
    job_id: str
    status: str
    result: Optional[str] = None

# --- HTML ROUTES ---
@app.get("/", response_class=HTMLResponse)
async def read_dashboard(request: Request):
    return templates.TemplateResponse("index.html", {"request": request, "page": "dashboard"})

@app.get("/analytics", response_class=HTMLResponse)
async def read_analytics(request: Request):
    return templates.TemplateResponse("analytics.html", {"request": request, "page": "analytics"})

@app.get("/upload", response_class=HTMLResponse)
async def read_upload(request: Request):
    return templates.TemplateResponse("upload.html", {"request": request, "page": "upload"})

@app.get("/review", response_class=HTMLResponse)
async def read_review(request: Request):
    return templates.TemplateResponse("review.html", {"request": request, "page": "review"})

@app.get("/search", response_class=HTMLResponse)
async def read_search(request: Request):
    return templates.TemplateResponse("search.html", {"request": request, "page": "search"})
    created_at: Optional[str] = None

class SearchResultItem(BaseModel):
    timestamp_seconds: float
    method_used: str
    confidence: float
    details: Optional[str]
    name: Optional[str] = None
    video_path: Optional[str] = None

class SearchResponse(BaseModel):
    query: dict
    results: List[SearchResultItem]

# --- Endpoints ---

@app.on_event("startup")
def startup_event():
    init_db()

@app.post("/v1/process")
async def process_video(
    video: UploadFile = File(...),
    config: Optional[str] = Form(None) # JSON string for configuration (crops, etc.)
):
    """
    Ingest a single video.
    Optional 'config' form field can contain JSON-encoded settings.
    Example config: {"auto_approve": true, "steps": ["ocr", "face"]}
    """
    job_id = str(uuid.uuid4())
    video_path = os.path.join(UPLOAD_FOLDER, f"{job_id}_{video.filename}")
    
    with open(video_path, "wb") as buffer:
        shutil.copyfileobj(video.file, buffer)
    
    # Check config for auto_approve
    auto_approve = False
    if config:
        try:
            config_json = json.loads(config)
            auto_approve = config_json.get("auto_approve", False)
        except:
            pass

    # Store initial job status
    conn = get_db_connection()
    conn.execute(
        "INSERT INTO jobs (job_id, status, config, auto_approve) VALUES (?, ?, ?, ?)",
        (job_id, "queued", config, auto_approve)
    )
    conn.commit()
    conn.close()

    # Trigger Celery Task
    process_video_task.apply_async(args=[video_path, job_id])
    
    return JSONResponse(
        status_code=202,
        content={
            "job_id": job_id,
            "status": "queued",
            "status_url": f"/v1/jobs/{job_id}"
        }
    )

@app.post("/v1/analyze/ocr")
async def analyze_ocr(file: UploadFile = File(...)):
    """Modular endpoint: Run ONLY OCR on the uploaded video."""
    return await _run_modular_analysis(file, "ocr")

@app.post("/v1/analyze/face")
async def analyze_face(file: UploadFile = File(...)):
    """Modular endpoint: Run ONLY Facial Recognition."""
    return await _run_modular_analysis(file, "face")

@app.post("/v1/analyze/audio")
async def analyze_audio(file: UploadFile = File(...)):
    """Modular endpoint: Run ONLY Speaker Diarization."""
    return await _run_modular_analysis(file, "audio")

class MetadataUpdate(BaseModel):
    review_status: str
    details: Optional[str] = None # For OCR/Text updates
    title: Optional[str] = None
    organization: Optional[str] = None
    role: Optional[str] = None # host or guest

@app.patch("/v1/metadata/{occurrence_id}")
async def update_metadata(occurrence_id: int, update: MetadataUpdate):
    """
    Human Review Endpoint.
    **Refactored**: Updates Person role, title, org, name.
    """
    if update.review_status not in ['pending', 'approved', 'rejected']:
        raise HTTPException(400, "Invalid status")
        
    conn = get_db_connection()
    
    # 1. Fetch current occurrence + linked person
    row = conn.execute("""
        SELECT o.person_id, o.method_used, p.name 
        FROM occurrences o
        JOIN persons p ON o.person_id = p.person_id
        WHERE o.occurrence_id = ?
    """, (occurrence_id,)).fetchone()
    
    if not row:
        conn.close()
        raise HTTPException(404, "Occurrence not found")
    
    person_id = row['person_id']
    method = row['method_used']
    current_name = row['name']
    
    # 2. Handle Person Updates (Name, Title, Org, Role)
    # Allow updates from ANY method (OCR, Face, Voice)
    if True:
        updates = []
        values = []
        
        # Name Change / Merge Logic... (Simplified for brevity, same as before)
        if update.details and update.details != current_name:
            new_name = update.details.strip()
            existing_person = conn.execute("SELECT person_id FROM persons WHERE name = ?", (new_name,)).fetchone()
            if existing_person:
                # Merge
                target_id = existing_person['person_id']
                conn.execute("UPDATE occurrences SET person_id = ? WHERE person_id = ?", (target_id, person_id))
                conn.execute("UPDATE identifiers SET person_id = ? WHERE person_id = ?", (target_id, person_id))
                conn.execute("DELETE FROM persons WHERE person_id = ?", (person_id,))
                person_id = target_id
            else:
                updates.append("name = ?")
                values.append(new_name)
        
        if update.title:
            updates.append("title = ?")
            values.append(update.title)
        if update.organization:
            updates.append("organization = ?")
            values.append(update.organization)
        if update.role:
            updates.append("role = ?")
            values.append(update.role)
            
        if updates:
            values.append(person_id)
            conn.execute(f"UPDATE persons SET {', '.join(updates)} WHERE person_id = ?", tuple(values))

    # 3. Update Occurrence Status & Details
    # If we merged persons, the occurrence row is still valid (linked to new person_id)
    # But we still need to update status.
    
    query = "UPDATE occurrences SET review_status = ?"
    params = [update.review_status]
    
    if update.details and method == 'ocr':
        query += ", details = ?"
        params.append(update.details)
        
    query += " WHERE occurrence_id = ?"
    params.append(occurrence_id)
    
    conn.execute(query, tuple(params))
    conn.commit()
    conn.close()
    
    return {"status": "updated", "occurrence_id": occurrence_id, "person_updated": person_id}
@app.get("/v1/review/queue")
async def get_review_queue(job_id: Optional[str] = None, status: Optional[str] = 'pending', limit: int = 50, grouped: bool = False):
    conn = get_db_connection()
    
    # Base query for raw details
    query = """
        SELECT o.occurrence_id, o.video_path, o.timestamp_seconds, o.method_used, o.confidence, o.details, o.review_status,
               p.person_id, p.name, p.title, p.organization, p.role
        FROM occurrences o
        LEFT JOIN persons p ON o.person_id = p.person_id
    """
    conditions = []
    params = []
    
    if status and status != 'all':
        conditions.append("o.review_status = ?")
        params.append(status)
        
    if job_id:
        conditions.append("o.job_id = ?") 
        params.append(job_id)

    if conditions:
        query += " WHERE " + " AND ".join(conditions)
        
    query += " ORDER BY o.timestamp_seconds ASC LIMIT ?"
    params.append(limit)
    
    rows = conn.execute(query, tuple(params)).fetchall()
    conn.close()
    
    results = [dict(row) for row in rows]
    
    if not grouped:
        return results

    # Grouping Logic for Person-Centric View
    # Structure: { "hosts": [person...], "guests": [person...] }
    grouped_data = {"hosts": [], "guests": []}
    seen_persons = {}

    for row in results:
        pid = row['person_id']
        
        # Handle unlinked occurrences (create synthetic person)
        if not pid:
            pid = f"unlinked_{row['occurrence_id']}"
            is_unlinked = True
        else:
            is_unlinked = False
        
        if pid not in seen_persons:
            # Initialize Person Object
            person_obj = {
                "person_id": pid,
                "name": row['name'] or (row['details'] if row['method_used'] == 'ocr' else "Unknown"),
                "title": row['title'] if not is_unlinked else None,
                "organization": row['organization'] if not is_unlinked else None,
                "role": row['role'] if (not is_unlinked and row['role']) else 'guest',
                "video_path": row['video_path'],
                "first_appearance": row['timestamp_seconds'],
                "thumb": None, # Placeholder for headshot path
                "occurrences": []
            }
            seen_persons[pid] = person_obj
            
            # Add to appropriate list
            if person_obj['role'] == 'host':
                grouped_data['hosts'].append(person_obj)
            else:
                grouped_data['guests'].append(person_obj)
        
        # Add occurrence to person
        seen_persons[pid]['occurrences'].append({
            "id": row['occurrence_id'],
            "ts": row['timestamp_seconds'],
            "conf": row['confidence']
        })
        
    return grouped_data

async def _run_modular_analysis(file: UploadFile, task_type: str):
    """Helper for modular analysis endpoints."""
    temp_id = str(uuid.uuid4())
    temp_path = os.path.join(UPLOAD_FOLDER, f"temp_{task_type}_{temp_id}_{file.filename}")
    
    try:
        with open(temp_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
            
        print(f"Running modular {task_type} for {temp_path}")
        results = None
        
        if task_type == "ocr":
            results = _run_ocr(temp_path)
        elif task_type == "face":
            # For modular API, we probably want to return serializable data, not numpy arrays
            # This requires converting the internal _run_facial_recognition output
            raw_results = _run_facial_recognition(temp_path)
            # Serialize for API response
            results = {k: [
                {"location": item["location"], "encoding_preview": item["encoding"][:5].tolist()} 
                for item in v
            ] for k, v in raw_results.items()} 
        elif task_type == "audio":
            # Extract audio first? _run_speaker_diarization expects audio path
            # For simplicity in this artifact, we assume _run_speaker handles wav extraction or we do it here
            audio_path = temp_path + ".wav"
            subprocess.run(['ffmpeg', '-i', temp_path, '-vn', '-ar', '16000', '-ac', '1', '-y', audio_path], capture_output=True)
            results = _run_speaker_diarization(audio_path)
            if os.path.exists(audio_path): os.remove(audio_path)
            
        return {"task": task_type, "results": results}

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)

@app.post("/v1/process/batch")
async def process_video_batch(
    videos: List[UploadFile] = File(...),
    config: Optional[str] = Form(None)
):
    """
    [NEW] Ingest multiple videos at once.
    Returns a list of job IDs.
    """
    responses = []
    
    for video in videos:
        job_id = str(uuid.uuid4())
        video_path = os.path.join(UPLOAD_FOLDER, f"{job_id}_{video.filename}")
        
        with open(video_path, "wb") as buffer:
            shutil.copyfileobj(video.file, buffer)
            
        conn = get_db_connection()
        conn.execute("INSERT INTO jobs (job_id, status) VALUES (?, ?)", (job_id, "queued"))
        conn.commit()
        conn.close()
        
        process_video_task.apply_async(args=[video_path, job_id])
        
        responses.append({
            "filename": video.filename,
            "job_id": job_id,
            "status": "queued",
            "status_url": f"/v1/jobs/{job_id}"
        })
        
    return JSONResponse(status_code=202, content={"batch_results": responses})

@app.post("/v1/extract/{media_type}")
async def extract_ephemeral(
    media_type: str,
    file: UploadFile = File(...)
):
    """
    [NEW] Ephemeral extraction. Does NOT save to DB.
    Useful for "Wait, what's in this?" checks.
    Supports: 'video', 'audio', 'image' (logic placeholder for now)
    """
    temp_id = str(uuid.uuid4())
    temp_path = os.path.join(UPLOAD_FOLDER, f"temp_{temp_id}_{file.filename}")
    
    try:
        with open(temp_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
            
        # Run extraction synchronously for the API response (blocking, but okay for this specialized endpoint)
        # In production this might still offload to a worker and use a websocket or polling
        results = {}
        
        if media_type == "video":
            print(f"Ephemeral processing for {temp_path}")
            # Mocking the pipeline for the ephemeral response to ensure speed
            # Real implementation would call _run_ocr(temp_path), etc.
            results["ocr"] = _run_ocr(temp_path)
            # Optimization: Face recognition is slow, maybe skip or sample heavily for ephemeral
            results["faces_detected_count"] = len(_run_facial_recognition(temp_path)) 
            
        elif media_type == "audio":
            # Just extract text/diarization?
            pass
            
        return {"media_type": media_type, "raw_metadata": results}

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)

@app.get("/v1/jobs/{job_id}", response_model=JobStatus)
async def get_job_status(job_id: str):
    conn = get_db_connection()
    job = conn.execute(
        "SELECT job_id, status, result, created_at FROM jobs WHERE job_id = ?",
        (job_id,)
    ).fetchone()
    conn.close()
    
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")
        
    return dict(job)

@app.get("/v1/jobs", response_model=List[JobStatus])
async def list_jobs(limit: int = 20):
    conn = get_db_connection()
    jobs = conn.execute(
        "SELECT job_id, status, result, created_at FROM jobs ORDER BY created_at DESC LIMIT ?",
        (limit,)
    ).fetchall()
    conn.close()
    return [dict(row) for row in jobs]

@app.get("/v1/search", response_model=SearchResponse)
async def search_metadata(
    video_filename: Optional[str] = Query(None, min_length=1),
    name: str = Query(..., min_length=1)
):
    conn = get_db_connection()
    
    query = """
        SELECT o.timestamp_seconds, o.method_used, o.confidence, o.details, p.name, p.video_path
        FROM occurrences o
        JOIN persons p ON o.person_id = p.person_id
        WHERE p.name LIKE ?
    """
    params = [f"%{name}%"]
    
    if video_filename:
        query += " AND p.video_path = ?"
        params.append(video_filename)
        
    results = conn.execute(query, tuple(params)).fetchall()
    conn.close()
    
    # Transform to match SearchResponse model
    # Note: frontend expects a list directly or a 'results' key?
    # search.html does `results = await res.json(); if (results.length ...)` which implies LIST.
    # But `SearchResponse` model (from earlier view) usually has {results: []}.
    # Let's check the model definition or standard. 
    # The previous code returned `{"query": ..., "results": [...]}`.
    # The frontend code `const results = await res.json()` followed by `results.map` implies it expects an ARRAY.
    # Wait, looking at `search.html`: `results.map(item => ...)`
    # The previous backend returned a dict `{"query": ..., "results": [...]}`. 
    # So `await res.json()` would return that dict. `dict.map` fails.
    # So the Frontend was ALSO broken because it expected an array but got an object?
    # Or I misread the frontend code.
    # Frontend: `const results = await res.json(); ... results.map(...)` -> definitely expects array.
    # Backend was `response_model=SearchResponse` returning dict.
    # I will change backend to return just the list of results to match frontend expectation, 
    # OR update frontend to use `results.results`.
    # Let's update backend to be simple list for now, or respect the contract.
    # I'll stick to returning the dict but FIX the frontend in the next step.
    # actually, let's fix the query first.
    
    return {
        "query": {"video_filename": video_filename, "name": name},
        "results": [dict(row) for row in results]
    }

@app.get("/v1/analytics/stats")
async def get_stats():
    conn = get_db_connection()
    try:
        total_videos = conn.execute("SELECT COUNT(DISTINCT video_path) as c FROM occurrences").fetchone()['c']
        total_people = conn.execute("SELECT COUNT(*) as c FROM persons").fetchone()['c']
        hosts = conn.execute("SELECT COUNT(*) as c FROM persons WHERE role='host'").fetchone()['c']
        guests = conn.execute("SELECT count(*) as c FROM persons WHERE role='guest' OR role='Unknown'").fetchone()['c']
        top_people = conn.execute("""
            SELECT name, COUNT(*) as appearances 
            FROM persons p 
            JOIN occurrences o ON p.person_id = o.person_id 
            GROUP BY p.person_id 
            ORDER BY appearances DESC 
            LIMIT 5
        """).fetchall()
        
        return {
            "total_videos": total_videos,
            "total_people": total_people,
            "hosts": hosts,
            "guests": guests,
            "top_people": [dict(row) for row in top_people]
        }
    finally:
        conn.close()

@app.get("/v1/analytics/network")
async def get_network_graph():
    """
    Returns nodes and edges for co-occurrence graph.
    Two people are linked if they appear in the same video.
    """
    conn = get_db_connection()
    try:
        # Nodes
        nodes_rows = conn.execute("SELECT person_id as id, name, role, title FROM persons").fetchall()
        nodes = [dict(r) for r in nodes_rows]
        
        # Edges (Co-occurrence)
        # Find pairs of person_ids that share a video_path
        # Use simple self-join with distinct check to avoid duplicates (A-B and B-A)
        edges_rows = conn.execute("""
            SELECT DISTINCT p1.person_id as source, p2.person_id as target
            FROM occurrences o1
            JOIN occurrences o2 ON o1.video_path = o2.video_path
            JOIN persons p1 ON o1.person_id = p1.person_id
            JOIN persons p2 ON o2.person_id = p2.person_id
            WHERE p1.person_id < p2.person_id
        """).fetchall()
        
        edges = [{"source": r['source'], "target": r['target']} for r in edges_rows]
        
        return {"nodes": nodes, "edges": edges}
    finally:
        conn.close()

@app.get("/v1/videos/{video_filename}/download")
async def download_video_with_viml(video_filename: str, background_tasks: BackgroundTasks):
    # Security note: In prod, validate video_filename prevents directory traversal
    original_path = os.path.join(UPLOAD_FOLDER, video_filename)
    if not os.path.exists(original_path):
        raise HTTPException(status_code=404, detail="Video file not found")

    # 1. Generate VTT
    try:
        vtt_content = generate_vtt_from_db(video_filename)
    except Exception as e:
        # DB lookup failed or empty?
        print(f"VIML gen error: {e}")
        vtt_content = "WEBVTT\n" # Return empty VTT on fail
        
    vtt_path = os.path.join(GENERATED_FOLDER, f"{video_filename}.vtt")
    with open(vtt_path, 'w') as f:
        f.write(vtt_content)

    # 2. Embed
    output_path = os.path.join(GENERATED_FOLDER, f"viml_{video_filename}")
    command = [
        'ffmpeg', '-i', original_path, '-i', vtt_path,
        '-c', 'copy', '-c:s', 'mov_text',
        '-metadata:s:s:0', 'language=eng',
        '-y', output_path
    ]
    subprocess.run(command, capture_output=True)

    # 3. Cleanup after response
    def cleanup():
        if os.path.exists(vtt_path): os.remove(vtt_path)
        if os.path.exists(output_path): os.remove(output_path)
    
    background_tasks.add_task(cleanup)
    
    return FileResponse(output_path, media_type="video/mp4", filename=f"viml_{video_filename}")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=5000)
