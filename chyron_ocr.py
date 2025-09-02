import sqlite3
import subprocess
import re
import os
from typing import Tuple

# --- Configuration ---
DATABASE_NAME = "video_metadata.db"

def setup_database():
    """
    Initializes the SQLite database and creates the 'chyrons' table
    if it does not already exist.
    """
    try:
        conn = sqlite3.connect(DATABASE_NAME)
        cursor = conn.cursor()
        
        # Create table to store OCR results
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS chyrons (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                video_path TEXT NOT NULL,
                timestamp_seconds REAL NOT NULL,
                detected_text TEXT NOT NULL,
                crop_area TEXT NOT NULL
            )
        ''')
        conn.commit()
    except sqlite3.Error as e:
        print(f"Database error: {e}")
    finally:
        if conn:
            conn.close()
    print(f"Database '{DATABASE_NAME}' is ready.")

def process_video_for_chyrons(video_path: str, crop_area: Tuple[int, int, int, int]):
    """
    Uses FFmpeg with an integrated Tesseract filter to perform OCR on a
    specified region of a video and stores the results in SQLite.

    Args:
        video_path (str): The full path to the video file.
        crop_area (Tuple[int, int, int, int]): A tuple defining the scan area
                                               as (width, height, x_offset, y_offset).
    """
    if not os.path.exists(video_path):
        print(f"Error: Video file not found at '{video_path}'")
        return

    w, h, x, y = crop_area
    print(f"Processing '{video_path}' with crop area: W={w}, H={h}, X={x}, Y={y}")

    # This command assumes a hypothetical FFmpeg v8 with a built-in 'ocr' filter.
    # The 'crop' filter first isolates the chyron region.
    # The 'ocr' filter then processes this cropped video stream.
    # Output is sent to stderr, which we capture.
    command = [
        'ffmpeg',
        '-i', video_path,
        '-vf', f'crop={w}:{h}:{x}:{y},ocr',
        '-f', 'null',  # Process but do not output a video file
        '-'
    ]

    try:
        # Execute the FFmpeg command, capturing stderr
        proc = subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=False # Don't raise error on non-zero exit, just capture output
        )

        # FFmpeg's filter output is typically sent to stderr
        ffmpeg_output = proc.stderr

        # Regex to parse the OCR filter's output format, e.g.:
        # [Parsed_ocr_1 @ ...] t: 15.250 s -> text: 'JANE DOE' conf: 95.87
        ocr_pattern = re.compile(r"t:\s*([\d.]+)\s*s\s*->\s*text:\s*'(.*?)'")
        
        matches = ocr_pattern.findall(ffmpeg_output)
        
        if not matches:
            print("No chyrons detected in the specified area.")
            return

        # --- Store results in the database ---
        conn = sqlite3.connect(DATABASE_NAME)
        cursor = conn.cursor()
        
        for timestamp_str, text in matches:
            if text.strip(): # Only insert if text is not empty
                timestamp = float(timestamp_str)
                cursor.execute(
                    "INSERT INTO chyrons (video_path, timestamp_seconds, detected_text, crop_area) VALUES (?, ?, ?, ?)",
                    (video_path, timestamp, text.strip(), str(crop_area))
                )
        
        conn.commit()
        conn.close()
        
        print(f"✅ Success! Found and stored {len(matches)} chyron instances.")

    except FileNotFoundError:
        print("Error: 'ffmpeg' command not found. Please ensure FFmpeg is installed and in your system's PATH.")
    except Exception as e:
        print(f"An unexpected error occurred: {e}")

def query_chyrons_by_video(video_path: str):
    """Queries and prints all stored chyrons for a specific video."""
    try:
        conn = sqlite3.connect(DATABASE_NAME)
        cursor = conn.cursor()
        cursor.execute(
            "SELECT timestamp_seconds, detected_text FROM chyrons WHERE video_path = ? ORDER BY timestamp_seconds",
            (video_path,)
        )
        results = cursor.fetchall()
        conn.close()
        
        if results:
            print(f"\n--- Stored Chyrons for '{video_path}' ---")
            for ts, text in results:
                print(f"  [{ts:>7.3f}s] {text}")
            print("--------------------------------------------------")
        else:
            print(f"No results found for '{video_path}' in the database.")
            
    except sqlite3.Error as e:
        print(f"Database query error: {e}")


if __name__ == "__main__":
    # --- Example Usage ---
    
    # 1. Setup the database
    setup_database()

    # 2. Define video path and the screen area to scan for chyrons
    # This example assumes a 1920x1080 video and targets the "lower third".
    video_file = "sample-news-broadcast.mp4" # Make sure this file exists
    
    # Create a dummy video file if it doesn't exist for testing purposes
    if not os.path.exists(video_file):
        print(f"'{video_file}' not found. You should replace this with a real video file.")
        # NOTE: Without a real video containing text, FFmpeg will find nothing.
        # To make the script runnable, one could create a dummy file:
        # subprocess.run(['ffmpeg', '-f', 'lavfi', '-i', 'testsrc=size=1920x1080:rate=30', '-t', '5', '-y', video_file])
    
    # Crop Area: (width, height, x_start, y_start)
    # This targets a 200px high banner at the bottom of a 1080p screen.
    lower_third_area = (1920, 200, 0, 880)

    # 3. Process the video
    process_video_for_chyrons(video_file, lower_third_area)
    
    # 4. Query and display the results from the database
    query_chyrons_by_video(video_file)