# VIML: Video Identification Markup Language

**Making video content inherently searchable for people.**

VIML is a standard markup language for identifying and tracking speakers in video content using computer vision, machine learning, and closed captioning data. It extends WebVTT to enable timeline-precise search for person appearances in video.

## Vision

Traditional closed captioning has been underutilized as a data channel. VIML leverages this existing infrastructure, combining it with modern CV/ML techniques to transform video from opaque media into searchable, navigable content organized by people.

### Core Capabilities

- 🔍 **Searchable Video**: Find every moment a person appears in video
- 👤 **Multi-Modal Tracking**: Identify people via OCR (chyrons), facial recognition, and voice
- 🎯 **Timeline Navigation**: Jump directly to specific person appearances
- 📊 **Rich Metadata**: Confidence scores, detection methods, biometric correlation
- 🌐 **Standards-Based**: Built on WebVTT for broad compatibility

## How It Works

### 1. Multi-Modal Detection

**OCR (Chyron Detection)**
- Scans on-screen text (lower thirds, name plates)
- Provides high-confidence initial identifications
- Typical use: News broadcasts, interviews, conferences

**Facial Recognition**
- Tracks known faces throughout video timeline
- Uses 128-dimensional face encodings
- Continuous presence monitoring

**Speaker Diarization**
- Segments audio by speaker
- Links voice patterns to identities
- Handles audio-only segments

### 2. Identity Correlation

The system correlates detections across methods:
1. OCR establishes initial identities when names appear on screen
2. Facial recognition extends tracking throughout the video
3. Speaker diarization confirms identities through voice patterns
4. All occurrences logged with timestamps and confidence scores

### 3. VIML Generation

Produces WebVTT files with embedded VIML tags:

```
WEBVTT

1
00:00:15.250 --> 00:00:17.250
[OCR] Jane Doe detected. <id person_id="1" name="Jane Doe" conf="95" method="ocr">

2
00:00:18.100 --> 00:00:20.100
[FACE] Jane Doe detected. <id person_id="1" name="Jane Doe" conf="92" method="face">
```

## Quick Start

### Prerequisites

- Python 3.8+
- FFmpeg (with OCR filter support)
- CUDA-capable GPU (recommended for facial recognition)

### Installation

1. Clone the repository:
```bash
git clone https://github.com/yargnad/VIML.git
cd VIML
```

2. Install dependencies:
```bash
pip install -r requirements.txt
```

3. Set up environment:
```bash
export HUGGING_FACE_TOKEN="your_token_here"
```

### Usage

#### Process a Video

```python
from processing import process_video

# Analyzes video and stores person identifications in database
process_video("path/to/video.mp4")
```

#### Generate VIML File

```python
from viml_generator import generate_vtt_from_db

# Creates WebVTT file with VIML tags
viml_content = generate_vtt_from_db("video.mp4")
with open("output.vtt", "w") as f:
    f.write(viml_content)
```

#### Search for Person Appearances

```python
from database import get_db_connection

conn = get_db_connection()
results = conn.execute("""
    SELECT timestamp_seconds, method_used, confidence
    FROM occurrences o
    JOIN persons p ON o.person_id = p.person_id
    WHERE p.name = ? AND o.video_path = ?
""", ("Jane Doe", "video.mp4")).fetchall()
```

### REST API

Run the Flask server:

```bash
python app.py
```

**Process Video**
```bash
curl -X POST -F "video=@broadcast.mp4" http://localhost:5000/v1/process
```

**Search Appearances**
```bash
curl "http://localhost:5000/v1/search?video_filename=broadcast.mp4&name=Jane%20Doe"
```

**Download VIML Video**
```bash
curl "http://localhost:5000/v1/videos/broadcast.mp4/download" -o output.mp4
```

## Use Cases

### News Broadcasting
- Automatically tag and index news archives
- Search by guest, reporter, or public figure
- Navigate to specific interview segments

### Conference & Events
- Make presentations searchable by speaker
- Find Q&A segments with specific experts
- Track speaker participation across sessions

### Education
- Index lecture videos by instructor
- Track guest lecturer appearances
- Enable student review of specific topics by speaker

### Enterprise
- Meeting video organization
- Compliance documentation
- Training video navigation

## Documentation

- **[Quick Start Guide](QUICKSTART.md)**: 5-minute tutorial to get started
- **[VIML Specification](VIML_SPECIFICATION.md)**: Complete technical specification
- **[Examples & Use Cases](EXAMPLES.md)**: Real-world examples and integrations
- **[Project Opinion](PROJECT_OPINION.md)**: Analysis and strategic assessment
- **[Roadmap](ROADMAP.md)**: Project roadmap and future plans
- **[Contributing](CONTRIBUTING.md)**: How to contribute to the project
- **[Database Schema](database.py)**: Schema documentation
- **[API Reference](app.py)**: REST API endpoints

## Architecture

```
┌─────────────────┐
│  Input Video    │
└────────┬────────┘
         │
    ┌────▼─────┐
    │ Process  │
    └────┬─────┘
         │
    ┌────▼────────────────────────┐
    │   Parallel Recognition      │
    ├─────────┬──────────┬────────┤
    │   OCR   │   Face   │ Voice  │
    └────┬────┴────┬─────┴───┬────┘
         │         │         │
         └────┬────┴────┬────┘
              │         │
         ┌────▼─────────▼────┐
         │   Correlation     │
         └────────┬──────────┘
                  │
         ┌────────▼──────────┐
         │   Database        │
         │  - persons        │
         │  - identifiers    │
         │  - occurrences    │
         └────────┬──────────┘
                  │
         ┌────────▼──────────┐
         │  VIML Generator   │
         └────────┬──────────┘
                  │
         ┌────────▼──────────┐
         │  WebVTT + VIML    │
         └───────────────────┘
```

## Development Setup

### From Source Compilation

For building Python and FFmpeg from source:

```bash
chmod +x compile_from_source.sh
./compile_from_source.sh
```

### Linting

```bash
shellcheck -x compile_from_source.sh
```

## Privacy & Ethics

VIML handles biometric data (face encodings, voice prints). Implementers must:

- ✅ Obtain consent for private video processing
- ✅ Encrypt stored biometric data
- ✅ Provide data deletion mechanisms
- ✅ Comply with GDPR, CCPA, and biometric privacy laws
- ✅ Disclose tracking methods transparently

Public broadcast content has different considerations than private video.

## Licensing

This project is open source under the [LICENSE](LICENSE) file.

For commercial licensing inquiries, particularly for broadcast integration, see [PROJECT_OPINION.md](PROJECT_OPINION.md) for licensing strategy details.

## Contributing

Contributions welcome! Areas of interest:

- Accuracy improvements and bias reduction
- Real-time processing optimizations
- Additional detection methods
- Player plugins for VIML consumption
- International language support

## Roadmap

- [x] Core VIML specification
- [x] Multi-modal detection pipeline
- [x] Database schema and storage
- [x] REST API
- [ ] Player plugins (Video.js, JWPlayer)
- [ ] Real-time broadcast integration
- [ ] Cross-video person tracking
- [ ] Enhanced privacy features
- [ ] W3C standardization submission

## Support

For questions, issues, or discussions:
- Open an issue on GitHub
- Review the [VIML Specification](VIML_SPECIFICATION.md)
- See [PROJECT_OPINION.md](PROJECT_OPINION.md) for strategic context

---

**VIML**: Natural extension of closed captioning for the AI era.
