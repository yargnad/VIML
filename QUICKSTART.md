# VIML Quick Start Guide

## What is VIML?

VIML (Video Identification Markup Language) makes video content searchable by people. It's like adding "Find in Page" for videos, but for finding people instead of text.

## 5-Minute Tutorial

### Step 1: Installation

```bash
# Clone the repository
git clone https://github.com/yargnad/VIML.git
cd VIML

# Install dependencies (using virtual environment recommended)
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt

# Set up Hugging Face token for speaker diarization
export HUGGING_FACE_TOKEN="your_token_here"
```

### Step 2: Process Your First Video

```python
from database import init_db
from processing import process_video
from viml_generator import generate_vtt_from_db

# Initialize database
init_db()

# Process a video (example: news broadcast)
process_video("my_video.mp4")

# Generate VIML file
viml_content = generate_vtt_from_db("my_video.mp4")
with open("my_video.vtt", "w") as f:
    f.write(viml_content)

print("VIML file created: my_video.vtt")
```

### Step 3: Search for People

```python
from database import get_db_connection

# Search for a specific person
conn = get_db_connection()
results = conn.execute("""
    SELECT timestamp_seconds, method_used, confidence
    FROM occurrences o
    JOIN persons p ON o.person_id = p.person_id
    WHERE p.name = ? AND o.video_path = ?
    ORDER BY timestamp_seconds
""", ("John Smith", "my_video.mp4")).fetchall()

# Print results
for row in results:
    print(f"Found at {row['timestamp_seconds']}s via {row['method_used']} (confidence: {row['confidence']}%)")
```

### Step 4: Use the REST API (Optional)

```bash
# Start the server
python app.py

# In another terminal, upload and process a video
curl -X POST -F "video=@my_video.mp4" http://localhost:5000/v1/process

# Search for a person
curl "http://localhost:5000/v1/search?video_filename=my_video.mp4&name=John%20Smith"
```

## Understanding VIML Output

### Example VIML File (WebVTT format)

```
WEBVTT

1
00:00:15.250 --> 00:00:17.250
[OCR] Jane Doe detected. <id person_id="1" name="Jane Doe" conf="95" method="ocr">

2
00:00:18.100 --> 00:00:20.100
[FACE] Jane Doe detected. <id person_id="1" name="Jane Doe" conf="92" method="face">

3
00:00:21.500 --> 00:00:24.500
[VOICE] Jane Doe detected. <id person_id="1" name="Jane Doe" conf="87" method="voice">
```

### Understanding the Tags

- **person_id**: Unique ID for this person in this video
- **name**: Person's name (from OCR or manual labeling)
- **conf**: Confidence score (0-100%)
- **method**: How they were detected:
  - `ocr`: From on-screen text (chyrons, lower thirds)
  - `face`: Facial recognition
  - `voice`: Speaker diarization

## Common Use Cases

### 1. News Archive Search

**Problem**: "Find all videos where Senator Williams appears"

**Solution**:
```python
def find_all_appearances(person_name):
    conn = get_db_connection()
    videos = conn.execute("""
        SELECT DISTINCT video_path, COUNT(*) as appearances
        FROM occurrences o
        JOIN persons p ON o.person_id = p.person_id
        WHERE p.name LIKE ?
        GROUP BY video_path
        ORDER BY appearances DESC
    """, (f"%{person_name}%",)).fetchall()
    return videos

# Find all videos with Senator Williams
videos = find_all_appearances("Senator Williams")
for video in videos:
    print(f"{video['video_path']}: {video['appearances']} appearances")
```

### 2. Conference Navigation

**Problem**: "Jump to the part where Dr. Smith speaks in this 3-hour conference video"

**Solution**:
```python
def get_speaker_timestamps(video_file, speaker_name):
    conn = get_db_connection()
    times = conn.execute("""
        SELECT timestamp_seconds
        FROM occurrences o
        JOIN persons p ON o.person_id = p.person_id
        WHERE p.name = ? AND o.video_path = ?
        ORDER BY timestamp_seconds
    """, (speaker_name, video_file)).fetchall()
    return [row['timestamp_seconds'] for row in times]

# Get all timestamps where Dr. Smith appears
timestamps = get_speaker_timestamps("conference.mp4", "Dr. Smith")
print(f"Dr. Smith appears at: {', '.join(f'{t}s' for t in timestamps)}")
```

### 3. Meeting Attendance Tracking

**Problem**: "Who attended this meeting and when did they speak?"

**Solution**:
```python
def get_meeting_attendees(video_file):
    conn = get_db_connection()
    attendees = conn.execute("""
        SELECT 
            p.name,
            MIN(o.timestamp_seconds) as first_appearance,
            MAX(o.timestamp_seconds) as last_appearance,
            COUNT(*) as total_detections
        FROM occurrences o
        JOIN persons p ON o.person_id = p.person_id
        WHERE o.video_path = ?
        GROUP BY p.name
        ORDER BY first_appearance
    """, (video_file,)).fetchall()
    return attendees

# Get meeting attendees
attendees = get_meeting_attendees("meeting_2024_11_14.mp4")
for person in attendees:
    print(f"{person['name']}: {person['first_appearance']}s - {person['last_appearance']}s")
```

## How Detection Works

### 1. OCR (Chyron Detection)

**What it does**: Scans the bottom third of video frames for text

**When it's used**: News broadcasts, interviews, conferences with name overlays

**Example output**:
```
Frame at 15.25s: "JANE DOE, Senior Analyst"
→ Creates person_id=1, name="Jane Doe"
```

### 2. Facial Recognition

**What it does**: Matches faces to known identities

**When it's used**: After OCR establishes identity, tracks person throughout video

**Example output**:
```
Frame at 18.10s: Face detected
→ Matches face encoding to person_id=1 (Jane Doe)
→ Records occurrence with 92% confidence
```

### 3. Speaker Diarization

**What it does**: Segments audio by different speakers

**When it's used**: Identifies who's speaking when in conversations

**Example output**:
```
Audio 21.5s-24.5s: Speaker segment detected
→ Correlates timing with person_id=1 (Jane Doe)
→ Records voice occurrence
```

## Troubleshooting

### "No detections found"

**Possible causes**:
- Video doesn't have on-screen text (chyrons)
- Text is in unusual position (adjust `OCR_CROP_AREA` in processing.py)
- Face quality too poor for recognition
- Audio quality insufficient for diarization

**Solutions**:
```python
# Check what was detected
conn = get_db_connection()
count = conn.execute("SELECT COUNT(*) FROM occurrences WHERE video_path = ?", 
                     ("my_video.mp4",)).fetchone()[0]
print(f"Total detections: {count}")

# If count is 0, check individual methods
# Try adjusting crop area in processing.py:
# OCR_CROP_AREA = "1920:200:0:880"  # w:h:x:y
```

### "Low confidence scores"

**Causes**: Poor video quality, lighting, or partial occlusion

**Solutions**:
- Use higher quality source video
- Adjust confidence thresholds in viml_generator.py
- Review detected faces manually

### "Speaker diarization fails"

**Common issue**: Missing or invalid Hugging Face token

**Solution**:
```bash
# Get token from https://huggingface.co/settings/tokens
export HUGGING_FACE_TOKEN="hf_xxxxxxxxxxxxx"

# Or set in code (not recommended for production)
import os
os.environ["HUGGING_FACE_TOKEN"] = "your_token"
```

## Best Practices

### 1. Video Quality

✅ **Good**:
- 720p or higher resolution
- Clear audio (no background noise)
- Well-lit faces
- High-contrast text overlays

❌ **Problematic**:
- Low resolution (< 480p)
- Poor lighting
- Heavy compression artifacts
- Muffled audio

### 2. Processing Strategy

For large video archives:

```python
# Process in batches with error handling
import os
from tqdm import tqdm

def batch_process(video_dir):
    videos = [f for f in os.listdir(video_dir) if f.endswith('.mp4')]
    
    for video in tqdm(videos, desc="Processing videos"):
        try:
            process_video(os.path.join(video_dir, video))
        except Exception as e:
            print(f"Failed to process {video}: {e}")
            continue

batch_process("/path/to/videos/")
```

### 3. Database Maintenance

```python
# Periodically clean up old data
conn = get_db_connection()
conn.execute("DELETE FROM occurrences WHERE video_path NOT IN (SELECT DISTINCT video_path FROM persons)")
conn.commit()

# Optimize database
conn.execute("VACUUM")
```

## Next Steps

1. **Read the full specification**: [VIML_SPECIFICATION.md](VIML_SPECIFICATION.md)
2. **Explore examples**: [EXAMPLES.md](EXAMPLES.md)
3. **Understand the project vision**: [PROJECT_OPINION.md](PROJECT_OPINION.md)
4. **Customize for your use case**: Modify processing pipeline in `processing.py`

## Getting Help

- **Documentation**: Check the main [README.md](README.md)
- **Issues**: Report bugs on GitHub Issues
- **Questions**: Start a Discussion on GitHub

## Quick Reference

### Database Schema

```sql
-- Persons table
SELECT * FROM persons WHERE name = 'Jane Doe';

-- Occurrences table
SELECT * FROM occurrences WHERE video_path = 'my_video.mp4' ORDER BY timestamp_seconds;

-- Cross-video search
SELECT video_path, COUNT(*) FROM occurrences o 
JOIN persons p ON o.person_id = p.person_id 
WHERE p.name = 'Jane Doe' 
GROUP BY video_path;
```

### Processing Pipeline

```
Video → OCR + Face + Voice → Correlation → Database → VIML WebVTT
```

### File Outputs

- **Database**: `video_metadata.db` (SQLite)
- **VIML Files**: `*.vtt` (WebVTT with VIML tags)
- **Temporary**: `generated/*.wav` (extracted audio)

---

**Happy searching!** 🔍📹
