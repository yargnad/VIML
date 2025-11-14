# VIML Examples and Use Cases

## Table of Contents

1. [Basic Examples](#basic-examples)
2. [Real-World Use Cases](#real-world-use-cases)
3. [Integration Examples](#integration-examples)
4. [Advanced Scenarios](#advanced-scenarios)

## Basic Examples

### Example 1: Simple News Broadcast

**Scenario**: A 5-minute news segment with one anchor and two guests.

**Input Video**: `news_segment.mp4`

**Processing**:
```python
from processing import process_video

process_video("news_segment.mp4")
```

**Generated VIML (news_segment.mp4.vtt)**:
```
WEBVTT

1
00:00:00.000 --> 00:00:15.000
[OCR] Sarah Johnson detected. <id person_id="1" name="Sarah Johnson" conf="96" method="ocr">

2
00:00:05.200 --> 00:01:30.500
[FACE] Sarah Johnson detected. <id person_id="1" name="Sarah Johnson" conf="93" method="face">

3
00:00:08.100 --> 00:00:45.000
[VOICE] Sarah Johnson detected. <id person_id="1" name="Sarah Johnson" conf="88" method="voice">

4
00:01:32.000 --> 00:01:34.000
[OCR] Dr. Michael Chen detected. <id person_id="2" name="Dr. Michael Chen" conf="97" method="ocr">

5
00:01:33.100 --> 00:02:45.800
[FACE] Dr. Michael Chen detected. <id person_id="2" name="Dr. Michael Chen" conf="91" method="face">

6
00:01:35.200 --> 00:02:15.300
[VOICE] Dr. Michael Chen detected. <id person_id="2" name="Dr. Michael Chen" conf="86" method="voice">

7
00:02:50.000 --> 00:02:52.000
[OCR] Emily Rodriguez detected. <id person_id="3" name="Emily Rodriguez" conf="95" method="ocr">

8
00:02:51.500 --> 00:04:30.200
[FACE] Emily Rodriguez detected. <id person_id="3" name="Emily Rodriguez" conf="92" method="face">

9
00:02:52.800 --> 00:04:25.100
[VOICE] Emily Rodriguez detected. <id person_id="3" name="Emily Rodriguez" conf="87" method="voice">
```

**Search Query**:
```python
from database import get_db_connection

conn = get_db_connection()
results = conn.execute("""
    SELECT timestamp_seconds, method_used, confidence
    FROM occurrences o
    JOIN persons p ON o.person_id = p.person_id
    WHERE p.name = 'Dr. Michael Chen' AND o.video_path = 'news_segment.mp4'
    ORDER BY timestamp_seconds
""").fetchall()

# Results:
# [(93.0, 'ocr', 96.5), (93.1, 'face', 91.2), (95.2, 'voice', 86.1), ...]
```

### Example 2: Panel Discussion

**Scenario**: 30-minute panel with 4 participants, no chyrons after initial introductions.

**Input**: `panel_discussion.mp4`

**VIML Output**:
```
WEBVTT

1
00:00:12.000 --> 00:00:14.000
[OCR] Alex Kim detected. <id person_id="1" name="Alex Kim" conf="94" method="ocr">

2
00:00:18.000 --> 00:00:20.000
[OCR] Jordan Taylor detected. <id person_id="2" name="Jordan Taylor" conf="95" method="ocr">

3
00:00:24.000 --> 00:00:26.000
[OCR] Sam Patel detected. <id person_id="3" name="Sam Patel" conf="96" method="ocr">

4
00:00:30.000 --> 00:00:32.000
[OCR] Morgan Lee detected. <id person_id="4" name="Morgan Lee" conf="93" method="ocr">

5-100
[Multiple FACE and VOICE detections throughout the video tracking all 4 participants]

250
00:28:45.100 --> 00:28:47.200
[VOICE] Sam Patel detected. <id person_id="3" name="Sam Patel" conf="84" method="voice">
```

**Key Feature**: After initial OCR identification, facial and voice tracking maintains continuous person identification without requiring repeated chyrons.

### Example 3: Sports Commentary

**Scenario**: Sports broadcast with commentators (no on-screen names).

**Challenge**: No OCR data available, relies purely on voice diarization.

**VIML Output**:
```
WEBVTT

NOTE: No OCR identifications available. Using SPEAKER_XX labels from diarization.

1
00:00:00.000 --> 00:02:45.000
[VOICE] SPEAKER_00 detected. <id person_id="1" name="SPEAKER_00" conf="82" method="voice">

2
00:02:46.000 --> 00:04:12.000
[VOICE] SPEAKER_01 detected. <id person_id="2" name="SPEAKER_01" conf="83" method="voice">

3
00:04:13.000 --> 00:06:30.000
[VOICE] SPEAKER_00 detected. <id person_id="1" name="SPEAKER_00" conf="85" method="voice">
```

**Enhancement**: Manual labeling or voice print matching can later map SPEAKER_00 → "John Anderson", etc.

## Real-World Use Cases

### Use Case 1: News Archive Search

**Organization**: Regional TV station with 20 years of news footage

**Problem**: Journalists need to find all appearances of a local politician but must manually review hours of tape.

**VIML Solution**:

1. **Batch Process Archive**:
```python
import os
from processing import process_video

archive_dir = "/media/news_archive/"
for video_file in os.listdir(archive_dir):
    if video_file.endswith(".mp4"):
        print(f"Processing {video_file}...")
        process_video(os.path.join(archive_dir, video_file))
```

2. **Search API**:
```bash
curl "http://localhost:5000/v1/search?name=Senator%20Williams&video_filename=newscast_2024_03_15.mp4"
```

**Result**:
```json
{
  "query": {
    "video_filename": "newscast_2024_03_15.mp4",
    "name": "Senator Williams"
  },
  "results": [
    {
      "timestamp_seconds": 245.5,
      "method_used": "ocr",
      "confidence": 96.0,
      "details": "Senator Williams"
    },
    {
      "timestamp_seconds": 246.2,
      "method_used": "face",
      "confidence": 93.0,
      "details": "..."
    },
    {
      "timestamp_seconds": 890.1,
      "method_used": "face",
      "confidence": 91.0,
      "details": "..."
    }
  ]
}
```

**Impact**: Reduces 8-hour manual review to 30-second search query.

### Use Case 2: Conference Video Platform

**Organization**: Academic conference with 200+ presentation videos

**Problem**: Attendees want to find talks by specific researchers or see all presentations mentioning a particular speaker.

**VIML Implementation**:

```python
# Process all conference videos
conference_videos = [
    "session1_track_a.mp4",
    "session1_track_b.mp4",
    "session2_track_a.mp4",
    # ... 200+ videos
]

for video in conference_videos:
    process_video(f"/conference2025/{video}")
```

**Search Interface**:
```python
def find_speaker_across_conference(speaker_name):
    """Find all appearances of a speaker across entire conference."""
    conn = get_db_connection()
    results = conn.execute("""
        SELECT DISTINCT o.video_path, o.timestamp_seconds
        FROM occurrences o
        JOIN persons p ON o.person_id = p.person_id
        WHERE p.name = ?
        ORDER BY o.video_path, o.timestamp_seconds
    """, (speaker_name,)).fetchall()
    
    # Group by video
    videos = {}
    for row in results:
        if row['video_path'] not in videos:
            videos[row['video_path']] = []
        videos[row['video_path']].append(row['timestamp_seconds'])
    
    return videos

# Example: Find all sessions featuring Dr. Elena Martinez
appearances = find_speaker_across_conference("Dr. Elena Martinez")
# Returns:
# {
#   'session1_track_a.mp4': [120.5, 455.2, 890.1],
#   'session5_panel.mp4': [45.0, 1200.5],
#   'keynote_day2.mp4': [2400.0]
# }
```

**Impact**: Enable "follow this speaker" feature across multi-track conferences.

### Use Case 3: Corporate Compliance

**Organization**: Financial services firm requiring documentation of client meetings

**Problem**: Must maintain searchable records of who attended which meetings for regulatory compliance.

**VIML Solution**:

```python
# Automated meeting processing pipeline
def process_meeting_recording(meeting_id, video_path):
    """Process meeting and generate compliance report."""
    
    # Process video
    process_video(video_path)
    
    # Extract attendee list
    conn = get_db_connection()
    attendees = conn.execute("""
        SELECT DISTINCT p.name, 
               MIN(o.timestamp_seconds) as first_appearance,
               MAX(o.timestamp_seconds) as last_appearance,
               COUNT(*) as detection_count
        FROM occurrences o
        JOIN persons p ON o.person_id = p.person_id
        WHERE o.video_path = ?
        GROUP BY p.name
    """, (os.path.basename(video_path),)).fetchall()
    
    # Generate compliance report
    report = {
        "meeting_id": meeting_id,
        "date": datetime.now().isoformat(),
        "attendees": [
            {
                "name": row['name'],
                "first_seen": row['first_appearance'],
                "last_seen": row['last_appearance'],
                "presence_confirmations": row['detection_count']
            }
            for row in attendees
        ]
    }
    
    return report
```

**Impact**: Automated compliance documentation with verifiable timestamps.

### Use Case 4: Educational Platform

**Organization**: Online learning platform with lecture recordings

**Problem**: Students want to navigate to specific parts where different instructors or guest speakers present.

**VIML Enhanced Player**:

```html
<!DOCTYPE html>
<html>
<head>
    <title>VIML-Enhanced Lecture Player</title>
</head>
<body>
    <video id="lecture" controls>
        <source src="lecture.mp4" type="video/mp4">
        <track src="lecture.vtt" kind="metadata" label="VIML">
    </video>
    
    <div id="speaker-index">
        <h3>Speakers in this lecture:</h3>
        <ul id="speaker-list"></ul>
    </div>
    
    <script>
        // Parse VIML track and build speaker index
        const video = document.getElementById('lecture');
        const track = video.textTracks[0];
        
        track.addEventListener('load', () => {
            const speakers = {};
            
            for (let cue of track.cues) {
                // Parse VIML tag from cue text
                const match = cue.text.match(/person_id="(\d+)" name="([^"]+)"/);
                if (match) {
                    const [, personId, name] = match;
                    if (!speakers[personId]) {
                        speakers[personId] = {
                            name: name,
                            appearances: []
                        };
                    }
                    speakers[personId].appearances.push(cue.startTime);
                }
            }
            
            // Build interactive speaker index
            const list = document.getElementById('speaker-list');
            for (let personId in speakers) {
                const speaker = speakers[personId];
                const li = document.createElement('li');
                li.innerHTML = `<strong>${speaker.name}</strong>`;
                
                const timestamps = document.createElement('ul');
                speaker.appearances.forEach((time, idx) => {
                    const ts = document.createElement('li');
                    const link = document.createElement('a');
                    link.href = '#';
                    link.textContent = `Appearance ${idx + 1} (${formatTime(time)})`;
                    link.onclick = (e) => {
                        e.preventDefault();
                        video.currentTime = time;
                        video.play();
                    };
                    ts.appendChild(link);
                    timestamps.appendChild(ts);
                });
                
                li.appendChild(timestamps);
                list.appendChild(li);
            }
        });
        
        function formatTime(seconds) {
            const mins = Math.floor(seconds / 60);
            const secs = Math.floor(seconds % 60);
            return `${mins}:${secs.toString().padStart(2, '0')}`;
        }
    </script>
</body>
</html>
```

**Impact**: Interactive navigation by speaker, improving student learning experience.

## Integration Examples

### Example 1: WordPress Plugin

```php
<?php
/**
 * Plugin Name: VIML Video Integration
 * Description: Adds VIML speaker search to WordPress video embeds
 */

add_shortcode('viml_video', 'viml_video_shortcode');

function viml_video_shortcode($atts) {
    $a = shortcode_atts([
        'src' => '',
        'viml' => ''
    ], $atts);
    
    ob_start();
    ?>
    <div class="viml-video-container">
        <video controls>
            <source src="<?php echo esc_url($a['src']); ?>" type="video/mp4">
            <track src="<?php echo esc_url($a['viml']); ?>" kind="metadata">
        </video>
        <div class="viml-search">
            <input type="text" placeholder="Search for person..." id="viml-search-input">
            <button onclick="vimlSearch()">Search</button>
        </div>
        <div id="viml-results"></div>
    </div>
    <script src="/wp-content/plugins/viml/viml-player.js"></script>
    <?php
    return ob_get_clean();
}
```

**Usage**:
```
[viml_video src="/media/conference.mp4" viml="/media/conference.vtt"]
```

### Example 2: FFmpeg Integration

**Generate VIML during video encoding**:

```bash
#!/bin/bash
# encode_with_viml.sh

INPUT_VIDEO=$1
OUTPUT_VIDEO="${INPUT_VIDEO%.mp4}_with_viml.mp4"
VIML_VTT="${INPUT_VIDEO}.vtt"

# Process video to generate VIML
python3 -c "
from processing import process_video
from viml_generator import generate_vtt_from_db
import sys

process_video('${INPUT_VIDEO}')
viml = generate_vtt_from_db('${INPUT_VIDEO}')
with open('${VIML_VTT}', 'w') as f:
    f.write(viml)
"

# Encode video with embedded VIML subtitle track
ffmpeg -i "${INPUT_VIDEO}" -i "${VIML_VTT}" \
    -c:v copy -c:a copy \
    -c:s mov_text \
    -metadata:s:s:0 language=eng \
    -metadata:s:s:0 title="VIML Speaker Identification" \
    "${OUTPUT_VIDEO}"

echo "Created: ${OUTPUT_VIDEO}"
```

### Example 3: Video.js Player Plugin

```javascript
// videojs-viml-plugin.js
videojs.registerPlugin('viml', function(options) {
    const player = this;
    
    player.ready(() => {
        const tracks = player.textTracks();
        
        // Find VIML metadata track
        for (let i = 0; i < tracks.length; i++) {
            if (tracks[i].kind === 'metadata') {
                const vimlTrack = tracks[i];
                
                vimlTrack.addEventListener('cuechange', () => {
                    const cue = vimlTrack.activeCues[0];
                    if (cue) {
                        // Parse VIML data
                        const match = cue.text.match(
                            /person_id="(\d+)" name="([^"]+)" conf="(\d+)" method="([^"]+)"/
                        );
                        
                        if (match) {
                            const [, personId, name, confidence, method] = match;
                            
                            // Display overlay
                            const overlay = document.createElement('div');
                            overlay.className = 'viml-overlay';
                            overlay.innerHTML = `
                                <div class="viml-badge">
                                    <span class="viml-name">${name}</span>
                                    <span class="viml-method">${method}</span>
                                </div>
                            `;
                            
                            player.el().appendChild(overlay);
                            
                            // Remove after cue ends
                            setTimeout(() => {
                                overlay.remove();
                            }, (cue.endTime - cue.startTime) * 1000);
                        }
                    }
                });
            }
        }
    });
});

// Usage:
// var player = videojs('my-video');
// player.viml();
```

## Advanced Scenarios

### Scenario 1: Cross-Video Person Tracking

**Goal**: Find all videos in archive featuring a specific person.

```python
def find_person_in_archive(person_name, archive_path="/media/archive/"):
    """Search entire video archive for person appearances."""
    conn = get_db_connection()
    
    results = conn.execute("""
        SELECT DISTINCT 
            o.video_path,
            p.name,
            COUNT(*) as appearance_count,
            MIN(o.timestamp_seconds) as first_appearance,
            MAX(o.timestamp_seconds) as last_appearance,
            GROUP_CONCAT(DISTINCT o.method_used) as methods
        FROM occurrences o
        JOIN persons p ON o.person_id = p.person_id
        WHERE p.name LIKE ?
        GROUP BY o.video_path, p.name
        ORDER BY appearance_count DESC
    """, (f"%{person_name}%",)).fetchall()
    
    return [dict(row) for row in results]

# Example
archive_results = find_person_in_archive("Senator Williams")
# Returns:
# [
#   {
#     'video_path': 'newscast_2024_11_05.mp4',
#     'name': 'Senator Williams',
#     'appearance_count': 45,
#     'first_appearance': 120.5,
#     'last_appearance': 1800.2,
#     'methods': 'ocr,face,voice'
#   },
#   ...
# ]
```

### Scenario 2: Multi-Language Support

**Challenge**: Names in different scripts/languages.

```python
def normalize_name(name, language='en'):
    """Normalize names for consistent matching across languages."""
    import unicodedata
    
    # Normalize unicode
    normalized = unicodedata.normalize('NFKD', name)
    
    # Language-specific handling
    if language == 'ja':
        # Japanese: Convert katakana to hiragana for matching
        pass  # Use library like pykakasi
    elif language == 'zh':
        # Chinese: Traditional to Simplified conversion
        pass  # Use library like hanziconv
    
    return normalized.lower().strip()

# Usage in correlation
def _correlate_and_store_multilingual(video_filename, ocr_data, ...):
    for timestamp, text in ocr_data:
        # Detect language
        lang = detect_language(text)
        
        # Normalize name
        normalized_name = normalize_name(text, lang)
        
        # Store both original and normalized
        cursor.execute("""
            INSERT INTO persons (video_path, name, normalized_name, language)
            VALUES (?, ?, ?, ?)
        """, (video_filename, text, normalized_name, lang))
```

### Scenario 3: Real-Time Broadcast Integration

**Challenge**: Process live broadcast with minimal latency.

```python
import threading
import queue
from datetime import datetime

class RealtimeVIMLProcessor:
    def __init__(self, stream_url):
        self.stream_url = stream_url
        self.frame_queue = queue.Queue(maxsize=100)
        self.results_queue = queue.Queue()
        
    def start(self):
        """Start processing threads."""
        threading.Thread(target=self._capture_frames, daemon=True).start()
        threading.Thread(target=self._process_ocr, daemon=True).start()
        threading.Thread(target=self._process_faces, daemon=True).start()
        
    def _capture_frames(self):
        """Capture frames from live stream."""
        cap = cv2.VideoCapture(self.stream_url)
        frame_count = 0
        
        while cap.isOpened():
            ret, frame = cap.read()
            if ret:
                timestamp = datetime.now()
                self.frame_queue.put((frame_count, timestamp, frame))
                frame_count += 1
                
    def _process_ocr(self):
        """Real-time OCR processing."""
        # Process frames for chyrons
        pass
        
    def _process_faces(self):
        """Real-time face detection."""
        # Process frames for known faces
        pass
    
    def get_current_speakers(self):
        """Get currently detected speakers."""
        # Return most recent identifications
        pass

# Usage:
# processor = RealtimeVIMLProcessor("rtmp://broadcast.example.com/live")
# processor.start()
# 
# while True:
#     speakers = processor.get_current_speakers()
#     # Update live graphics, database, etc.
```

### Scenario 4: Privacy-Preserving VIML

**Challenge**: Generate VIML without storing biometric data.

```python
def process_video_privacy_mode(video_path):
    """Process video with ephemeral identifiers."""
    
    # Process as normal
    ocr_results = _run_ocr(video_path)
    face_results = _run_facial_recognition(video_path)
    speaker_results = _run_speaker_diarization(audio_path)
    
    # Correlate in memory only
    person_map = {}  # Temporary mapping
    occurrences = []
    
    for timestamp, text in ocr_results:
        if text not in person_map:
            person_map[text] = len(person_map) + 1
        
        occurrences.append({
            'timestamp': timestamp,
            'person_id': person_map[text],
            'name': text,
            'method': 'ocr',
            'confidence': 95.0
        })
    
    # Generate VIML directly without database storage
    viml_content = generate_viml_from_memory(occurrences)
    
    # Biometric data never persisted
    return viml_content
```

## Performance Optimization

### Batch Processing Script

```python
#!/usr/bin/env python3
"""
Batch process multiple videos with progress tracking.
"""
import os
import multiprocessing
from tqdm import tqdm
from processing import process_video

def process_single_video(video_path):
    """Wrapper for multiprocessing."""
    try:
        process_video(video_path)
        return (video_path, 'success', None)
    except Exception as e:
        return (video_path, 'failed', str(e))

def batch_process_directory(directory, num_workers=4):
    """Process all videos in directory using multiprocessing."""
    
    # Find all video files
    video_files = []
    for root, dirs, files in os.walk(directory):
        for file in files:
            if file.endswith(('.mp4', '.avi', '.mov', '.mkv')):
                video_files.append(os.path.join(root, file))
    
    print(f"Found {len(video_files)} video files")
    
    # Process with progress bar
    with multiprocessing.Pool(num_workers) as pool:
        results = list(tqdm(
            pool.imap(process_single_video, video_files),
            total=len(video_files)
        ))
    
    # Summary
    successes = sum(1 for _, status, _ in results if status == 'success')
    failures = sum(1 for _, status, _ in results if status == 'failed')
    
    print(f"\nProcessing complete:")
    print(f"  Successful: {successes}")
    print(f"  Failed: {failures}")
    
    # Log failures
    for path, status, error in results:
        if status == 'failed':
            print(f"  FAILED: {path} - {error}")

if __name__ == "__main__":
    import sys
    directory = sys.argv[1] if len(sys.argv) > 1 else "."
    batch_process_directory(directory)
```

**Usage**:
```bash
python batch_process.py /media/news_archive/ 
```

---

These examples demonstrate VIML's versatility across different use cases, from simple news broadcasts to complex enterprise integrations. The key strength is the standard, searchable format that enables person-centric video navigation.
