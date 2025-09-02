#!/bin/bash
set -e

# --- Configuration ---
PYTHON_VERSION="3.11.9"
FFMPEG_VERSION="7.0"
PROJECT_REPO="https://github.com/yargnad/VIML.git" # IMPORTANT: Change this
PROJECT_DIR="VIML"
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
    # AV1 build helpers and meson/ninja for dav1d
    meson
    ninja-build
    cmake
    libtool
    autoconf
    automake
    pkg-config
    # prefer distro AV1 dev packages if available
    libaom-dev
    libdav1d-dev
    libsvtav1-dev
)
sudo apt install -y "${PACKAGES[@]}"
success "Build dependencies installed."

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Local install prefix for optional source-built libraries (libaom, dav1d, svt-av1)
LOCAL_PREFIX="$BUILD_DIR/local"
mkdir -p "$LOCAL_PREFIX"
export PKG_CONFIG_PATH="$LOCAL_PREFIX/lib/pkgconfig:$LOCAL_PREFIX/share/pkgconfig:${PKG_CONFIG_PATH:-}"
export PATH="$LOCAL_PREFIX/bin:$PATH"

# --- Network helpers: retry with exponential backoff for wget and git clones
retry() {
    # usage: retry <max_attempts> <sleep_base_seconds> -- command args...
    local max_attempts=${1:-5}; shift
    local sleep_base=${1:-2}; shift
    if [ "$#" -eq 0 ]; then
        echo "retry: no command provided" >&2
        return 2
    fi
    local attempt=1
    local exit_code=0
    while [ "${attempt}" -le "${max_attempts}" ]; do
        "$@" && return 0
        exit_code=$?
        local sleep_for=$(( sleep_base ** attempt ))
        echo "Command failed (exit ${exit_code}). Retrying in ${sleep_for}s (attempt ${attempt}/${max_attempts})..." >&2
        sleep "${sleep_for}"
        attempt=$(( attempt + 1 ))
    done
    return $exit_code
}

retry_git_clone() {
    # usage: retry_git_clone <dest_dir> <git_url1> [git_url2 ...]
    local dest="$1"; shift
    local url
    for url in "$@"; do
        echo "Trying git clone from: $url"
        if retry 4 2 git clone --depth 1 "$url" "$dest"; then
            return 0
        fi
    done
    return 1
}

retry_wget() {
    # usage: retry_wget <url> <out_file>
    local url="$1"; local out="$2"
    retry 4 2 wget -c -O "$out" "$url"
}


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
# Build AV1 libs from source into LOCAL_PREFIX if distro packages weren't available
cd "$BUILD_DIR"
if ! pkg-config --exists aom || ! pkg-config --exists dav1d || ! pkg-config --exists svtav1; then
    info "Building AV1 codec libraries into $LOCAL_PREFIX"

    # libaom
    if [ ! -d "aom" ]; then
        git clone https://aomedia.googlesource.com/aom aom || git clone https://aomedia.org/aom.git aom || true
    fi
    if [ -d "aom" ]; then
        cd aom
        mkdir -p build && cd build
        cmake -G"Unix Makefiles" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$LOCAL_PREFIX" ..
        make -j"$(nproc)" && make install
        cd "$BUILD_DIR"
    fi

    # dav1d (meson)
    if [ ! -d "dav1d" ]; then
        git clone https://code.videolan.org/videolan/dav1d.git dav1d || true
    fi
    if [ -d "dav1d" ]; then
        cd dav1d
        meson setup build --prefix="$LOCAL_PREFIX" --buildtype=release || true
        ninja -C build && ninja -C build install || true
        cd "$BUILD_DIR"
    fi

    # SVT-AV1: try multiple git mirrors first, then tarball fallbacks
    if [ ! -d "SVT-AV1" ]; then
        SVT_DEST="$BUILD_DIR/SVT-AV1"
        SVT_GIT_URLS=(
            "https://gitlab.com/AOMediaCodec/SVT-AV1.git"
            "https://github.com/AOMediaCodec/SVT-AV1.git"
            "https://github.com/AV1-Codec-SVT/SVT-AV1.git"
        )
        if ! retry_git_clone "$SVT_DEST" "${SVT_GIT_URLS[@]}"; then
            echo "Git clones failed, attempting tarball fallbacks..."
            SVT_TARBALLS=(
                "https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/master/SVT-AV1-master.tar.gz"
                "https://github.com/AOMediaCodec/SVT-AV1/archive/refs/heads/master.tar.gz"
            )
            mkdir -p "$SVT_DEST"
            for tb in "${SVT_TARBALLS[@]}"; do
                echo "Trying tarball: $tb"
                tmpfile="$BUILD_DIR/svtav1.tar.gz"
                if retry_wget "$tb" "$tmpfile"; then
                    mkdir -p "$SVT_DEST"
                    tar -xzf "$tmpfile" -C "$BUILD_DIR"
                    # move extracted dir to SVT-AV1 if needed
                    extracted=$(tar -tzf "$tmpfile" | head -1 | cut -f1 -d"/") || true
                    if [ -d "$BUILD_DIR/$extracted" ]; then
                        mv "$BUILD_DIR/$extracted" "$SVT_DEST"
                    fi
                    rm -f "$tmpfile"
                    break
                fi
            done
        fi
    fi
    if [ -d "SVT-AV1" ]; then
        cd SVT-AV1
        mkdir -p build && cd build
        cmake -G"Unix Makefiles" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$LOCAL_PREFIX" ..
        make -j"$(nproc)" && make install || true
        cd "$BUILD_DIR"
    fi
fi

# Return to FFmpeg source directory
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
    --enable-libtesseract \
    --enable-libaom \
    --enable-libdav1d \
    --enable-libsvtav1 \
    --extra-cflags="-I$LOCAL_PREFIX/include" \
    --extra-ldflags="-L$LOCAL_PREFIX/lib"
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