# app.py
import os
import uuid
import threading
from flask import Flask, request, jsonify, send_file
from werkzeug.utils import secure_filename

from database import init_db, get_db_connection
from processing import process_video
from viml_generator import generate_vtt_from_db

# --- Flask App Setup ---
app = Flask(__name__)
app.config['UPLOAD_FOLDER'] = 'uploads'
app.config['GENERATED_FOLDER'] = 'generated'
os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)
os.makedirs(app.config['GENERATED_FOLDER'], exist_ok=True)

# In-memory job tracking for simplicity
job_statuses = {}

@app.route('/v1/process', methods=['POST'])
def process_video_endpoint():
    if 'video' not in request.files:
        return jsonify({"error": "No video file provided"}), 400
    
    file = request.files['video']
    if file.filename == '':
        return jsonify({"error": "No selected file"}), 400
        
    filename = secure_filename(file.filename)
    video_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
    file.save(video_path)
    
    job_id = str(uuid.uuid4())
    job_statuses[job_id] = "processing"
    
    # Run the long process in a background thread
    thread = threading.Thread(target=run_processing_job, args=(job_id, video_path))
    thread.start()
    
    return jsonify({
        "job_id": job_id,
        "status": "processing",
        "status_url": f"/v1/jobs/{job_id}"
    }), 202

def run_processing_job(job_id, video_path):
    """Wrapper to run the processing and update job status."""
    try:
        process_video(video_path)
        job_statuses[job_id] = "completed"
    except Exception as e:
        print(f"Job {job_id} failed: {e}")
        job_statuses[job_id] = "failed"

@app.route('/v1/jobs/<job_id>', methods=['GET'])
def get_job_status(job_id):
    status = job_statuses.get(job_id, "not_found")
    return jsonify({"job_id": job_id, "status": status})

@app.route('/v1/search', methods=['GET'])
def search_metadata():
    video_filename = request.args.get('video_filename')
    name = request.args.get('name')
    if not video_filename or not name:
        return jsonify({"error": "Missing 'video_filename' or 'name' query parameters"}), 400
        
    conn = get_db_connection()
    results = conn.execute("""
        SELECT o.timestamp_seconds, o.method_used, o.confidence, o.details
        FROM occurrences o
        JOIN persons p ON o.person_id = p.person_id
        WHERE p.video_path = ? AND p.name = ?
    """, (video_filename, name)).fetchall()
    conn.close()
    
    return jsonify({
        "query": {"video_filename": video_filename, "name": name},
        "results": [dict(row) for row in results]
    })

@app.route('/v1/videos/<video_filename>/download', methods=['GET'])
def download_video_with_viml(video_filename):
    original_path = os.path.join(app.config['UPLOAD_FOLDER'], video_filename)
    if not os.path.exists(original_path):
        return jsonify({"error": "Video file not found"}), 404

    # 1. Generate VTT file with VIML markup
    vtt_content = generate_vtt_from_db(video_filename)
    vtt_path = os.path.join(app.config['GENERATED_FOLDER'], f"{video_filename}.vtt")
    with open(vtt_path, 'w') as f:
        f.write(vtt_content)

    # 2. Use FFmpeg to create a copy with embedded subtitles
    output_path = os.path.join(app.config['GENERATED_FOLDER'], f"viml_{video_filename}")
    command = [
        'ffmpeg', '-i', original_path, '-i', vtt_path,
        '-c', 'copy', '-c:s', 'mov_text', # Embed as text-based subtitle
        '-metadata:s:s:0', 'language=eng',
        '-y', output_path
    ]
    subprocess.run(command, capture_output=True)

    # 3. Send the file and schedule cleanup
    @after_this_request
    def cleanup(response):
        try:
            os.remove(vtt_path)
            os.remove(output_path)
        except Exception as e:
            print(f"Error during cleanup: {e}")
        return response

    return send_file(output_path, as_attachment=True)

if __name__ == '__main__':
    init_db() # Initialize the database on startup
    app.run(debug=True, port=5000)