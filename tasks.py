# tasks.py
import os
import sqlite3
import traceback
from celery import Celery
from database import get_db_connection
from processing import process_video as core_process_video

# --- Celery Configuration ---
celery_app = Celery(
    'viml_tasks',
    broker='redis://localhost:6379/0',
    backend='redis://localhost:6379/0'
)

@celery_app.task(bind=True)
def process_video_task(self, video_path: str, job_id: str):
    """
    Celery task wrapper for the processing.py logic.
    Updates the SQLite 'jobs' table with status.
    """
    _update_job_status(job_id, "processing")
    
    try:
        # Run the core logic
        core_process_video(video_path, job_id)
        
        _update_job_status(job_id, "completed")
        return "success"
        
    except Exception as e:
        error_msg = f"{str(e)}\n{traceback.format_exc()}"
        print(f"Task failed for job {job_id}: {error_msg}")
        _update_job_status(job_id, "failed", result=str(e))
        # Re-raise so Celery knows it failed
        raise e

def _update_job_status(job_id, status, result=None):
    """Helper to update the job status in SQLite."""
    try:
        conn = get_db_connection()
        conn.execute(
            "UPDATE jobs SET status = ?, result = ?, updated_at = CURRENT_TIMESTAMP WHERE job_id = ?",
            (status, result, job_id)
        )
        conn.commit()
    except sqlite3.Error as e:
        print(f"Failed to update job status for {job_id}: {e}")
    finally:
        if conn:
            conn.close()
