# VIML Specification v1.0

## Video Identification Markup Language

### Overview

VIML (Video Identification Markup Language) is a standard markup language designed to identify and track speakers, persons, and their appearances in video content. It extends the WebVTT (Web Video Text Tracks) format to embed rich metadata about people detected through computer vision, machine learning, and closed captioning analysis.

### Purpose

VIML addresses the need for:
- **Searchable Video Content**: Make video inherently searchable by person identity
- **Speaker Tracking**: Link speakers across time using voice, face, and text identification
- **Timeline Navigation**: Enable users to jump to specific moments when a person appears
- **Accessibility Enhancement**: Extend closed captioning with identity information
- **Broadcast Integration**: Provide a standard for broadcasters to adopt

### Format

VIML uses WebVTT as its base format and extends it with custom tags embedded in caption text.

#### Basic Structure

```
WEBVTT

1
00:00:15.250 --> 00:00:17.250
[OCR] Jane Doe detected. <id person_id="1" name="Jane Doe" conf="95" method="ocr">

2
00:00:18.100 --> 00:00:20.100
[FACE] John Smith detected. <id person_id="2" name="John Smith" conf="92" method="face">

3
00:00:21.500 --> 00:00:24.500
[VOICE] Jane Doe detected. <id person_id="1" name="Jane Doe" conf="87" method="voice">
```

### Tag Specification

#### `<id>` Tag

The core VIML tag for person identification.

**Attributes:**

- `person_id` (required): Unique identifier for the person within the video scope
  - Type: Integer
  - Example: `person_id="1"`

- `name` (required): Human-readable name of the identified person
  - Type: String
  - Example: `name="Jane Doe"`

- `conf` (required): Confidence score of the identification
  - Type: Integer (0-100)
  - Example: `conf="95"`

- `method` (required): Detection method used
  - Type: Enum
  - Values: `"ocr"`, `"face"`, `"voice"`
  - Example: `method="ocr"`

**Example:**
```
<id person_id="1" name="Jane Doe" conf="95" method="ocr">
```

### Detection Methods

#### 1. OCR (Optical Character Recognition)

Identifies speakers by detecting on-screen text (chyrons, lower thirds, name plates).

**Typical Confidence Range:** 85-98%

**Use Cases:**
- News broadcasts with lower third graphics
- Interview shows with name overlays
- Conference presentations with speaker names

**Implementation Notes:**
- Scans predefined regions (e.g., lower third of screen)
- Extracts text and correlates with visual appearance timing
- Primary method for initial speaker identification

#### 2. Face Recognition

Identifies speakers through facial biometric matching.

**Typical Confidence Range:** 80-95%

**Use Cases:**
- Tracking known individuals throughout video
- Cross-referencing with initial OCR identifications
- Continuous speaker presence monitoring

**Implementation Notes:**
- Generates face encodings (128-dimensional embeddings)
- Compares against known face database
- Processes at regular intervals (e.g., 1 frame per second)

#### 3. Voice Recognition / Speaker Diarization

Identifies speakers through voice pattern analysis.

**Typical Confidence Range:** 75-90%

**Use Cases:**
- Audio-only segments
- Multiple speakers in conversation
- Voice confirmation of visual identifications

**Implementation Notes:**
- Uses speaker diarization to segment audio by speaker
- Links speaker segments to known identities
- Correlates with visual identifications for initial labeling

### Database Schema

VIML implementations should maintain three core tables:

#### persons
Stores unique individuals per video.

| Column      | Type    | Description                    |
|-------------|---------|--------------------------------|
| person_id   | INTEGER | Primary key                    |
| video_path  | TEXT    | Video file reference           |
| name        | TEXT    | Person's name                  |

**Constraint:** UNIQUE(video_path, name)

#### identifiers
Stores biometric data for person recognition.

| Column          | Type    | Description                      |
|-----------------|---------|----------------------------------|
| identifier_id   | INTEGER | Primary key                      |
| person_id       | INTEGER | Foreign key to persons           |
| method          | TEXT    | 'face' or 'voice'                |
| biometric_data  | BLOB    | Serialized encoding data         |

#### occurrences
Event log of all person detections.

| Column             | Type    | Description                        |
|--------------------|---------|------------------------------------|
| occurrence_id      | INTEGER | Primary key                        |
| video_path         | TEXT    | Video file reference               |
| person_id          | INTEGER | Foreign key to persons             |
| timestamp_seconds  | REAL    | Time of detection                  |
| method_used        | TEXT    | 'ocr', 'face', or 'voice'          |
| confidence         | REAL    | Confidence score (0-100)           |
| details            | TEXT    | Additional method-specific data    |

### Processing Pipeline

1. **Asset Extraction**
   - Extract audio (16kHz mono WAV)
   - Prepare video for frame analysis

2. **Parallel Recognition**
   - OCR: Scan predefined regions for text
   - Face: Extract face encodings from key frames
   - Voice: Run speaker diarization on audio

3. **Correlation**
   - Link OCR-detected names with faces appearing simultaneously
   - Associate speaker segments with identified persons
   - Build identity database per video

4. **Tracking**
   - Continuously identify known faces throughout video
   - Log all occurrences with timestamps and confidence

5. **VIML Generation**
   - Create WebVTT file with embedded VIML tags
   - Sort events chronologically
   - Embed metadata in subtitle format

### API Endpoints

A VIML-compliant service should provide:

#### POST /v1/process
Upload and process a video file.

**Request:** multipart/form-data with video file

**Response:**
```json
{
  "job_id": "uuid",
  "status": "processing",
  "status_url": "/v1/jobs/{job_id}"
}
```

#### GET /v1/jobs/{job_id}
Check processing status.

**Response:**
```json
{
  "job_id": "uuid",
  "status": "completed|processing|failed"
}
```

#### GET /v1/search
Search for person appearances.

**Parameters:**
- `video_filename`: Video file to search
- `name`: Person name to find

**Response:**
```json
{
  "query": {
    "video_filename": "broadcast.mp4",
    "name": "Jane Doe"
  },
  "results": [
    {
      "timestamp_seconds": 15.25,
      "method_used": "ocr",
      "confidence": 95.0,
      "details": "Jane Doe"
    }
  ]
}
```

#### GET /v1/videos/{video_filename}/download
Download video with embedded VIML subtitles.

**Response:** Video file with embedded WebVTT/VIML track

### Use Cases

#### 1. News Broadcast Archiving
Television networks can automatically tag and index news broadcasts, enabling search by:
- Guest appearances
- Reporter assignments
- Political figure mentions

#### 2. Conference & Event Video
Event organizers can make presentations searchable by speaker, allowing attendees to:
- Find specific speaker sessions
- Navigate to Q&A segments
- Review particular expert contributions

#### 3. Educational Content
Educational platforms can enhance lecture videos with:
- Instructor identification
- Guest lecturer tracking
- Student participation moments

#### 4. Legal & Compliance
Organizations can maintain searchable video records for:
- Testimony identification
- Meeting participant tracking
- Compliance documentation

### Privacy Considerations

VIML implementations must consider:

1. **Consent**: Obtain permission before storing biometric data
2. **Data Protection**: Encrypt stored face encodings and voice prints
3. **Right to Deletion**: Provide mechanisms to remove person data
4. **Public vs. Private**: Different standards for broadcast vs. private content
5. **Transparency**: Clear disclosure of identification methods used

### Licensing Model

For broadcast integration, VIML technology can be licensed to:

- **Broadcasters**: Automatic chyron processing and speaker tracking
- **Video Platforms**: Enhanced search and navigation features
- **Content Management Systems**: Archive organization and retrieval
- **Research Institutions**: Speaker diarization and analysis tools

### Future Extensions

Potential enhancements to VIML:

1. **Emotion Tagging**: Add sentiment/emotion attributes
2. **Scene Context**: Include scene type and setting information
3. **Interaction Mapping**: Track person-to-person interactions
4. **Cross-Video Linking**: Link same person across multiple videos
5. **Real-time Processing**: Live broadcast integration
6. **Multi-language Support**: Internationalization of name handling

### Compliance

VIML is designed to complement existing standards:

- **WebVTT**: Base format compatibility
- **CEA-608/708**: Closed captioning integration
- **MPEG-7**: Video metadata standards
- **Schema.org**: Structured data markup

### Version History

- **v1.0** (2025): Initial specification
  - Core `<id>` tag definition
  - Three detection methods (OCR, Face, Voice)
  - Basic database schema
  - API endpoint specification

---

© 2025 VIML Project. This specification is provided as-is for implementation and adoption.
