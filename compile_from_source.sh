#!/bin/bash
set -e

# --- Configuration ---
PYTHON_VERSION="3.11.9"
FFMPEG_VERSION="7.0"
PROJECT_REPO="https://github.com/yargnad/VIML.git" # IMPORTANT: Change this
PROJECT_DIR="viml_project"
BUILD_DIR="$HOME/source_builds"

# --- Helper Functions ---
info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
success() { echo -e "\033[1;32m[SUCCESS]\033[0m $1"; }
warn() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }

# --- Warning ---
warn "This script will compile Python and FFmpeg from source."
warn "This will take a significant amount of time and disk space."
read -r -p "Press [Enter] to continue or Ctrl+C to cancel..."

# --- 1. System Preparation for Compiling ---
info "Updating system packages..."
sudo apt update && sudo apt upgrade -y

info "Installing essential build tools and dependencies..."
PACKAGES=(
    build-essential
    cmake
    pkg-config
    git
    libgl1
    libglib2.0-0
    # Python dependencies
    libssl-dev
    zlib1g-dev
    libbz2-dev
    libreadline-dev
    libsqlite3-dev
    libncurses5-dev
    libncursesw5-dev
    xz-utils
    tk-dev
    libffi-dev
    liblzma-dev
    # FFmpeg dependencies
    nasm
    yasm
    libx264-dev
    libx265-dev
    libnuma-dev
    libvpx-dev
    libfdk-aac-dev
    libmp3lame-dev
    libopus-dev
    libtesseract-dev
    tesseract-ocr
    tesseract-ocr-eng
    tesseract-ocr-script-latn
    libleptonica-dev
)
sudo apt install -y "${PACKAGES[@]}"
success "Build dependencies installed."

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# --- 2. Compile Python from Source ---
info "Compiling Python $PYTHON_VERSION..."
if [ ! -f "Python-$PYTHON_VERSION.tar.xz" ]; then
    wget "https://www.python.org/ftp/python/$PYTHON_VERSION/Python-$PYTHON_VERSION.tar.xz"
fi
tar -xf "Python-$PYTHON_VERSION.tar.xz"
cd "Python-$PYTHON_VERSION"
./configure --enable-optimizations --with-ensurepip=install
make -j"$(nproc)"
# Use 'altinstall' to avoid overwriting the system's python3
sudo make altinstall
cd ..
# The new binary will be python3.11
PYTHON_EXEC="python$(echo $PYTHON_VERSION | cut -d'.' -f1-2)"
success "Python $PYTHON_VERSION compiled and installed as $PYTHON_EXEC."

# --- 3. Compile FFmpeg from Source ---
info "Compiling FFmpeg $FFMPEG_VERSION..."
if [ ! -f "ffmpeg-$FFMPEG_VERSION.tar.bz2" ]; then
    wget "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.bz2"
fi
tar -xf "ffmpeg-$FFMPEG_VERSION.tar.bz2"
cd "ffmpeg-$FFMPEG_VERSION"
# NOTE: The hypothetical '--enable-libtesseract' flag would go here
./configure \
    --enable-gpl \
    --enable-libx264 \
    --enable-libx265 \
    --enable-libvpx \
    --enable-libfdk-aac \
    --enable-libmp3lame \
    --enable-libopus \
    --enable-nonfree \
    --enable-libtesseract
make -j"$(nproc)"
sudo make install
# Refresh library cache
sudo ldconfig
cd ..
success "FFmpeg $FFMPEG_VERSION compiled and installed."

# --- 4. Project Setup (using compiled versions) ---
cd "$HOME"
if [ ! -d "$PROJECT_DIR" ]; then
    info "Checking repository accessibility: $PROJECT_REPO"
    if ! git ls-remote "$PROJECT_REPO" >/dev/null 2>&1; then
        warn "Repository '$PROJECT_REPO' not found or inaccessible."
        warn "Possible causes: incorrect URL, repository is private, or network/authentication issues."
        read -r -p "Would you like to try cloning with HTTPS credentials? [y/N]: " TRY_CREDS
        if [[ "$TRY_CREDS" =~ ^[Yy]$ ]]; then
            read -r -p "Git username: " GIT_USER
            read -r -s -p "Git personal access token or password: " GIT_TOKEN
            echo
            # Construct authenticated HTTPS URL (do not print token)
            if [[ "$PROJECT_REPO" == https://* ]]; then
                AUTH_REPO="${PROJECT_REPO/https:\/\//https:\/\/$GIT_USER:$GIT_TOKEN@}"
            else
                warn "PROJECT_REPO is not an HTTPS URL; please use an SSH URL or manually clone the repo."
                exit 1
            fi
            if git ls-remote "$AUTH_REPO" >/dev/null 2>&1; then
                info "Authenticated access confirmed. Cloning..."
                git clone "$AUTH_REPO" "$PROJECT_DIR"
                # remove sensitive variable
                unset GIT_TOKEN
            else
                warn "Authenticated access failed. Check username/token and try again."
                unset GIT_TOKEN
                exit 1
            fi
        else
            warn "Update the PROJECT_REPO variable in compile_from_source.sh or ensure you have access (SSH key or HTTPS credentials)."
            exit 1
        fi
    else
        git clone "$PROJECT_REPO" "$PROJECT_DIR"
    fi
fi
cd "$PROJECT_DIR"
mkdir -p uploads generated

info "Creating Python virtual environment with compiled Python..."
$PYTHON_EXEC -m venv venv
# shellcheck disable=SC1091
source venv/bin/activate

info "Installing Python packages..."
pip install --upgrade pip
pip install torch torchaudio --index-url https://download.pytorch.org/whl/cpu
pip install Flask face_recognition opencv-python pyannote.audio
success "Python packages installed."

# --- 5. Final Configuration ---
PROCESSING_FILE="processing.py"
if [ -f "$PROCESSING_FILE" ]; then
    read -r -p "Please enter your Hugging Face Access Token: " HF_TOKEN
    sed -i "s#YOUR_HUGGING_FACE_TOKEN_HERE#${HF_TOKEN}#g" "$PROCESSING_FILE"
    success "Hugging Face token has been set."
fi

deactivate

# --- Completion Message ---
echo
success "Full compilation and project installation complete!"
info "To run the application:"
info "1. cd ~/$PROJECT_DIR"
info "2. source venv/bin/activate"
info "3. python app.py"
echo