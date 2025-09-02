#!/bin/bash
# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
PROJECT_REPO="https://github.com/your-username/your-viml-project.git" # IMPORTANT: Change this to your project's git repo
PROJECT_DIR="viml_project"
PYTHON_VENV_DIR="venv"

# --- Helper Functions for Colored Output ---
info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
success() { echo -e "\033[1;32m[SUCCESS]\033[0m $1"; }
warn() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }

# --- 1. System Preparation ---
info "Updating system packages. This may take a few minutes..."
sudo apt update && sudo apt upgrade -y

info "Installing system dependencies for Python, FFmpeg, and building wheels..."
sudo apt install -y \
    git \
    ffmpeg \
    python3-pip \
    python3-venv \
    build-essential \
    cmake \
    pkg-config \
    libgl1-mesa-glx \
    libglib2.0-0
success "System dependencies installed."

# --- 2. Project Setup ---
if [ -d "$PROJECT_DIR" ]; then
    warn "Project directory '$PROJECT_DIR' already exists. Skipping clone."
else
    info "Cloning project from $PROJECT_REPO..."
    git clone "$PROJECT_REPO" "$PROJECT_DIR"
fi
cd "$PROJECT_DIR"
info "Creating required subdirectories: 'uploads' and 'generated'."
mkdir -p uploads generated
success "Project directory is ready."

# --- 3. Python Environment Setup ---
info "Creating Python virtual environment at '$PYTHON_VENV_DIR'..."
python3 -m venv "$PYTHON_VENV_DIR"

info "Activating virtual environment and installing Python packages..."
source "$PYTHON_VENV_DIR/bin/activate"

# Install PyTorch for CPU first for reliability
pip install torch torchaudio --index-url https://download.pytorch.org/whl/cpu

# Install the rest of the packages
pip install \
    Flask \
    face_recognition \
    opencv-python \
    pyannote.audio
success "All Python packages installed successfully."

# --- 4. Final Configuration ---
PROCESSING_FILE="processing.py"
if [ -f "$PROCESSING_FILE" ]; then
    info "Configuring Hugging Face API Token..."
    read -p "Please enter your Hugging Face Access Token: " HF_TOKEN
    
    # Use sed to replace the placeholder token in processing.py
    # Using '#' as a delimiter to avoid issues with special characters in the token
    sed -i "s#YOUR_HUGGING_FACE_TOKEN_HERE#${HF_TOKEN}#g" "$PROCESSING_FILE"
    success "Hugging Face token has been set in $PROCESSING_FILE."
else
    warn "Could not find '$PROCESSING_FILE'. Please configure your Hugging Face token manually."
fi

deactivate

# --- Completion Message ---
echo
success "Project installation complete!"
info "To run the application:"
info "1. cd $PROJECT_DIR"
info "2. source $PYTHON_VENV_DIR/bin/activate"
info "3. Place a video file in the 'uploads' directory."
info "4. python3 app.py"
echo