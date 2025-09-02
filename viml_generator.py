# viml_generator.py
from database import get_db_connection

def generate_vtt_from_db(video_filename: str) -> str:
    """Creates a VIML-enhanced WebVTT file content from database occurrences."""
    conn = get_db_connection()
    cursor = conn.cursor()
    
    cursor.execute("""
        SELECT o.timestamp_seconds, o.method_used, o.confidence, p.name, p.person_id
        FROM occurrences o
        JOIN persons p ON o.person_id = p.person_id
        WHERE o.video_path = ?
        ORDER BY o.timestamp_seconds
    """, (video_filename,))
    
    records = cursor.fetchall()
    conn.close()
    
    if not records:
        return "WEBVTT\n\n"

    vtt_content = "WEBVTT\n\n"
    for i, record in enumerate(records):
        start_time = record['timestamp_seconds']
        # End time is the start of the next event, or 2s after for the last one
        end_time = records[i+1]['timestamp_seconds'] if i + 1 < len(records) else start_time + 2.0
        
        start_vtt = _format_vtt_time(start_time)
        end_vtt = _format_vtt_time(end_time)
        
        person_id = record['person_id']
        name = record['name']
        conf = record['confidence']
        method = record['method_used']
        
        viml_tag = f'<id person_id="{person_id}" name="{name}" conf="{conf:.0f}" method="{method}">'
        caption_text = f"[{method.upper()}] {name} detected."
        
        vtt_content += f"{i+1}\n"
        vtt_content += f"{start_vtt} --> {end_vtt}\n"
        vtt_content += f"{caption_text} {viml_tag}\n\n"
        
    return vtt_content

def _format_vtt_time(seconds: float) -> str:
    """Converts seconds to WebVTT timestamp format HH:MM:SS.sss"""
    millis = int((seconds - int(seconds)) * 1000)
    mins, secs = divmod(int(seconds), 60)
    hours, mins = divmod(mins, 60)
    return f"{hours:02}:{mins:02}:{secs:02}.{millis:03}"