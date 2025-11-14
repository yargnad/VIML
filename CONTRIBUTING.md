# Contributing to VIML

Thank you for your interest in contributing to VIML (Video Identification Markup Language)! This document provides guidelines for contributing to the project.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How Can I Contribute?](#how-can-i-contribute)
- [Development Setup](#development-setup)
- [Coding Standards](#coding-standards)
- [Testing Guidelines](#testing-guidelines)
- [Submitting Changes](#submitting-changes)
- [Community](#community)

## Code of Conduct

### Our Pledge

We are committed to providing a welcoming and inclusive environment for all contributors, regardless of:
- Experience level
- Gender identity and expression
- Sexual orientation
- Disability
- Personal appearance
- Race or ethnicity
- Age
- Religion or lack thereof

### Expected Behavior

- Be respectful and considerate
- Welcome newcomers and help them get started
- Provide constructive feedback
- Focus on what's best for the community and project
- Show empathy towards other contributors

### Unacceptable Behavior

- Harassment, intimidation, or discrimination
- Trolling or insulting comments
- Public or private harassment
- Publishing others' private information
- Other conduct inappropriate in a professional setting

## How Can I Contribute?

### Reporting Bugs

**Before submitting a bug report:**
1. Check existing issues to avoid duplicates
2. Verify the bug in the latest version
3. Collect relevant information (logs, screenshots, environment)

**Bug Report Should Include:**
- Clear, descriptive title
- Steps to reproduce
- Expected vs. actual behavior
- Environment details (OS, Python version, dependencies)
- Relevant logs or error messages
- Sample video (if applicable and anonymized)

**Example Bug Report:**
```markdown
**Title**: Face detection fails on low-contrast images

**Description**: 
When processing videos with poor lighting, face detection returns 0 results even when faces are clearly visible to human eye.

**Steps to Reproduce**:
1. Process video with low-contrast faces
2. Check occurrences table for face detections
3. Observe that no faces were detected

**Expected**: Faces should be detected even in suboptimal lighting
**Actual**: No face detections recorded

**Environment**:
- OS: Ubuntu 22.04
- Python: 3.10.12
- face-recognition: 1.3.0
- Video: 720p MP4, H.264

**Logs**:
```
Processing video.mp4...
Step 2: Running OCR, Facial, and Speaker Recognition...
Face processing completed: 0 faces found
```

### Suggesting Enhancements

**Enhancement Suggestions Should Include:**
- Clear use case description
- Expected behavior/outcome
- Why this enhancement is valuable
- Potential implementation approach (optional)

**Example Enhancement Suggestion:**
```markdown
**Title**: Add support for multiple OCR regions

**Use Case**: 
Some broadcasts have multiple text overlays (lower third + corner banner). Current implementation only scans one region.

**Proposal**:
Allow configuration of multiple crop regions in processing.py:
```python
OCR_CROP_AREAS = [
    "1920:200:0:880",  # Lower third
    "400:100:1520:0"   # Top-right corner
]
```

**Value**: Increases OCR coverage for complex broadcast layouts

**Implementation Notes**:
Would require modifying _run_ocr() to iterate over multiple regions
```

### Contributing Code

#### Areas for Contribution

**High Priority:**
- Accuracy improvements (reduce false positives/negatives)
- Performance optimization (faster processing)
- Privacy enhancements (data protection, consent management)
- Documentation improvements
- Test coverage expansion

**Medium Priority:**
- Integration examples (CMS plugins, player plugins)
- UI/Dashboard for video management
- Multi-language support
- Advanced analytics features

**Good First Issues:**
- Documentation fixes and additions
- Code cleanup and refactoring
- Adding type hints
- Writing unit tests
- Example scripts

## Development Setup

### Prerequisites

- Python 3.8 or higher
- FFmpeg (with OCR filter support)
- CUDA-capable GPU (optional but recommended)
- Git
- Virtual environment tool (venv, virtualenv, conda)

### Setup Steps

1. **Fork and Clone**
```bash
git clone https://github.com/YOUR_USERNAME/VIML.git
cd VIML
```

2. **Create Virtual Environment**
```bash
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
```

3. **Install Dependencies**
```bash
pip install -r requirements.txt
```

4. **Set Environment Variables**
```bash
export HUGGING_FACE_TOKEN="your_token_here"
```

5. **Initialize Database**
```bash
python3 -c "from database import init_db; init_db()"
```

6. **Run Tests (when available)**
```bash
pytest
```

### Project Structure

```
VIML/
├── app.py                 # Flask REST API
├── database.py            # Database schema and connections
├── processing.py          # Main video processing pipeline
├── viml_generator.py      # VIML WebVTT generation
├── chyron_ocr.py          # Standalone OCR utility
├── requirements.txt       # Python dependencies
├── README.md              # Project overview
├── VIML_SPECIFICATION.md  # Technical specification
├── PROJECT_OPINION.md     # Strategic analysis
├── EXAMPLES.md            # Usage examples
├── QUICKSTART.md          # Quick start guide
├── ROADMAP.md             # Project roadmap
└── CONTRIBUTING.md        # This file
```

## Coding Standards

### Python Style

Follow [PEP 8](https://pep8.org/) with these specifics:

**Formatting:**
- 4 spaces for indentation (no tabs)
- Max line length: 100 characters
- Use `black` for automatic formatting:
  ```bash
  black *.py
  ```

**Naming:**
- `snake_case` for functions and variables
- `PascalCase` for classes
- `UPPER_CASE` for constants
- Descriptive names (avoid abbreviations)

**Example:**
```python
# Good
def process_video_with_ocr(video_path: str) -> dict:
    """Process video using OCR detection."""
    OCR_CONFIDENCE_THRESHOLD = 85.0
    results = {}
    # ...
    return results

# Avoid
def pv(vp):
    """Process video."""
    t = 85.0
    r = {}
    # ...
    return r
```

### Type Hints

Use type hints for function signatures:

```python
from typing import List, Dict, Optional, Tuple

def correlate_faces(
    face_data: Dict[float, List[dict]], 
    known_faces: Dict[int, List[np.ndarray]]
) -> List[Tuple[int, float, float]]:
    """Correlate detected faces with known identities."""
    # ...
```

### Documentation

**Docstrings** (Google style):
```python
def process_video(video_path: str) -> None:
    """
    Orchestrates the complete video analysis pipeline.
    
    Performs OCR, facial recognition, and speaker diarization on the input
    video, then correlates the results and stores in database.
    
    Args:
        video_path: Absolute or relative path to video file
        
    Raises:
        FileNotFoundError: If video file doesn't exist
        ProcessingError: If any processing step fails
        
    Example:
        >>> process_video("/path/to/video.mp4")
        Processing complete. Found 3 persons.
    """
    # Implementation
```

**Comments:**
- Use comments to explain *why*, not *what*
- Comment complex algorithms or non-obvious logic
- Keep comments up-to-date with code changes

```python
# Good - explains why
# Use 1-second tolerance because chyrons typically appear
# within 1 second of the person speaking
if abs(closest_face_ts - timestamp) < 1.0:

# Unnecessary - obvious from code
# Check if difference is less than 1
if abs(closest_face_ts - timestamp) < 1.0:
```

### Error Handling

Be explicit about error conditions:

```python
# Good
try:
    process_video(video_path)
except FileNotFoundError:
    logger.error(f"Video not found: {video_path}")
    raise
except cv2.error as e:
    logger.error(f"OpenCV error processing video: {e}")
    # Handle or re-raise with context
    raise ProcessingError(f"Failed to process {video_path}") from e

# Avoid bare except
try:
    process_video(video_path)
except:
    pass  # Silent failure - bad!
```

## Testing Guidelines

### Test Structure

```python
import pytest
from database import init_db, get_db_connection
from processing import process_video

@pytest.fixture
def test_db():
    """Fixture for test database."""
    init_db()
    yield
    # Cleanup
    
def test_process_video_creates_persons(test_db):
    """Test that processing creates person records."""
    # Arrange
    video_path = "test_fixtures/sample.mp4"
    
    # Act
    process_video(video_path)
    
    # Assert
    conn = get_db_connection()
    count = conn.execute("SELECT COUNT(*) FROM persons").fetchone()[0]
    assert count > 0, "Should create at least one person record"
```

### Running Tests

```bash
# Run all tests
pytest

# Run with coverage
pytest --cov=. --cov-report=html

# Run specific test file
pytest test_processing.py

# Run specific test
pytest test_processing.py::test_ocr_detection
```

### Test Data

- Use anonymized, publicly available test videos
- Keep test files small (< 1MB)
- Include test fixtures for common scenarios
- Never commit real personal data

## Submitting Changes

### Workflow

1. **Create a Branch**
```bash
git checkout -b feature/your-feature-name
# or
git checkout -b fix/bug-description
```

2. **Make Changes**
- Write clear, focused commits
- Follow coding standards
- Add/update tests as needed
- Update documentation

3. **Commit Messages**

Use conventional commit format:
```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Formatting, no code change
- `refactor`: Code restructuring
- `test`: Adding tests
- `chore`: Maintenance tasks

**Example:**
```
feat(processing): add multi-region OCR support

Allows configuration of multiple crop areas for OCR detection,
enabling detection of chyrons in multiple screen positions.

Closes #123
```

4. **Push and Create PR**
```bash
git push origin feature/your-feature-name
```

Then create a Pull Request on GitHub.

### Pull Request Guidelines

**PR Description Should Include:**
- What: Clear description of changes
- Why: Problem being solved or feature added
- How: Implementation approach
- Testing: How you tested the changes
- Screenshots: For UI changes
- Related Issues: Link to relevant issues

**PR Checklist:**
- [ ] Code follows style guidelines
- [ ] Documentation updated
- [ ] Tests added/updated
- [ ] All tests passing
- [ ] No merge conflicts
- [ ] Commits are clear and focused

**Example PR:**
```markdown
## Description
Adds support for configuring multiple OCR crop regions, enabling detection of chyrons in different screen positions.

## Motivation
Fixes #123 - some broadcasts have multiple text overlays that the current single-region scan misses.

## Changes
- Modified `processing.py` to accept list of crop regions
- Updated `_run_ocr()` to iterate over multiple regions
- Added configuration validation
- Updated documentation

## Testing
Tested with sample news broadcast containing both lower third and corner banner:
- Both text regions successfully detected
- No regression on single-region videos

## Screenshots
N/A

## Related Issues
Closes #123
```

### Code Review Process

1. **Automated Checks**: CI runs tests and linters
2. **Maintainer Review**: At least one maintainer reviews
3. **Address Feedback**: Make requested changes
4. **Approval**: Maintainer approves PR
5. **Merge**: Maintainer or contributor merges

**Review Timeline:**
- Initial response: Within 3 business days
- Full review: Within 1 week
- Merge (if approved): Within 2 weeks

## Community

### Communication Channels

- **GitHub Discussions**: General questions and discussion
- **GitHub Issues**: Bug reports and feature requests
- **Pull Requests**: Code contributions and review

### Getting Help

- Check documentation first
- Search existing issues/discussions
- Ask in GitHub Discussions
- Be patient and respectful

### Recognition

Contributors are recognized in:
- `CONTRIBUTORS.md` file (to be created)
- Release notes
- Project README

## Questions?

If you have questions about contributing, please:
1. Check this guide
2. Search GitHub Discussions
3. Ask in a new Discussion thread

Thank you for contributing to VIML! 🎉
