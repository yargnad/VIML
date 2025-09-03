#!/bin/bash
set -e

# --- Configuration ---
PYTHON_VERSION="3.11.9"
FFMPEG_VERSION="7.0"
PROJECT_REPO="https://github.com/yargnad/VIML.git" # IMPORTANT: Change this
PROJECT_DIR="VIML"
BUILD_DIR="$HOME/source_builds"

# Local install prefix (default under BUILD_DIR). Define early so other checks
# that reference $LOCAL_PREFIX won't accidentally operate on root (empty var).
LOCAL_PREFIX="${LOCAL_PREFIX:-$BUILD_DIR/local}"


# --- Helper Functions ---
info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
success() { echo -e "\033[1;32m[SUCCESS]\033[0m $1"; }
warn() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }

# Ensure a pkg-config package exists, with optional minimum version.
# Usage: ensure_pkg <pkg-name> [version]
ensure_pkg() {
    local pkg="$1"
    local ver="$2"
    local query
    if [ -n "$ver" ]; then
        query="$pkg >= $ver"
    else
        query="$pkg"
    fi

    if pkg-config --exists "$query"; then
        success "$pkg found via pkg-config."
        return 0
    fi

    warn "$pkg not found via pkg-config. Attempting auto-discovery under $BUILD_DIR..."
    FOUND_PKG_DIRS=()
    while IFS= read -r pc; do
        pkgdir=$(dirname "$pc")
        case " ${FOUND_PKG_DIRS[*]} " in
            *" $pkgdir "*) ;;
            *) FOUND_PKG_DIRS+=("$pkgdir");;
        esac
    done < <(find "$BUILD_DIR" -type f -name '*.pc' 2>/dev/null || true)

    if [ ${#FOUND_PKG_DIRS[@]} -gt 0 ]; then
        for d in "${FOUND_PKG_DIRS[@]}"; do
            export PKG_CONFIG_PATH="$d:$PKG_CONFIG_PATH"
            info "Added pkg-config dir: $d"
        done
        info "Retrying pkg-config discovery for $pkg..."
        if pkg-config --exists "$query"; then
            success "$pkg found after adding discovered pkg-config dirs."
            return 0
        else
            warn "$pkg still not found after auto-discovery."
            # If pkg-config still fails, try a header-based fallback for
            # packages that install headers but do not provide a .pc file.
            # Some distro -dev packages (for example libsvtav1-dev) ship only
            # headers under /usr/include and no pkg-config metadata.
            declare -A HEADER_FALLBACKS=(
                [svtav1]="svt-av1/EbSvtAv1Enc.h"
            )
            if [ -n "${HEADER_FALLBACKS[$pkg]:-}" ]; then
                hdr="${HEADER_FALLBACKS[$pkg]}"
                for incp in /usr/include /usr/local/include "$LOCAL_PREFIX/include"; do
                    if [ -f "$incp/$hdr" ]; then
                        success "$pkg appears available (header found at $incp/$hdr). Treating as present."
                        return 0
                    fi
                done
            fi
            return 1
        fi
    else
        warn "No .pc files found under $BUILD_DIR to help auto-discover $pkg."
        # Try header fallback when no .pc files are found
        declare -A HEADER_FALLBACKS=(
            [svtav1]="svt-av1/EbSvtAv1Enc.h"
        )
        if [ -n "${HEADER_FALLBACKS[$pkg]:-}" ]; then
            hdr="${HEADER_FALLBACKS[$pkg]}"
            for incp in /usr/include /usr/local/include "$LOCAL_PREFIX/include"; do
                if [ -f "$incp/$hdr" ]; then
                    success "$pkg appears available (header found at $incp/$hdr). Treating as present."
                    return 0
                fi
            done
        fi
        return 1
    fi
}

# retry a shell command (passed as a single string) with exponential backoff
# usage: retry "git clone ..."  # will try up to 5 times
retry() {
    local cmd="$1"
    local max=${2:-5}
    local attempt=1
    local delay=2
    while [ "$attempt" -le "$max" ]; do
        if bash -c "$cmd"; then
            return 0
        fi
        warn "Command failed (attempt $attempt/$max): $cmd"
    if [ "$attempt" -lt "$max" ]; then
            info "Retrying in ${delay}s..."
            sleep $delay
            delay=$((delay * 2))
        fi
        attempt=$((attempt + 1))
    done
    return 1
}

# Build SVT-AV1 from GitHub into LOCAL_PREFIX as a fallback when pkg-config discovery fails
build_svt_from_github() {
    info "Attempting to build SVT-AV1 from GitHub into $LOCAL_PREFIX"
    mkdir -p "$BUILD_DIR"
    pushd "$BUILD_DIR" >/dev/null || return 1
    local svt_dir="SVT-AV1"
    if [ -d "$svt_dir" ]; then
        info "SVT-AV1 directory already exists at $BUILD_DIR/$svt_dir, pulling latest"
        (cd "$svt_dir" && git fetch --all --tags) || true
    else
        if ! retry "git clone 'https://github.com/AOMediaCodec/SVT-AV1.git' '$svt_dir'" 3; then
            warn "Failed to clone SVT-AV1 from GitHub"
            popd >/dev/null || true
            return 1
        fi
    fi
    if [ -d "$svt_dir" ]; then
        cd "$svt_dir"
        mkdir -p build
        cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$LOCAL_PREFIX"
        cmake --build build -j"$(nproc)" || true
        cmake --install build || true
        popd >/dev/null || true
        # Update PKG_CONFIG_PATH so subsequent pkg-config checks can find the .pc
        export PKG_CONFIG_PATH="$LOCAL_PREFIX/lib/pkgconfig:$LOCAL_PREFIX/lib64/pkgconfig:${PKG_CONFIG_PATH:-}"
        success "Attempted SVT-AV1 build/install into $LOCAL_PREFIX"
        return 0
    fi
    popd >/dev/null || true
    return 1
}

# Parse simple command-line flags
SKIP_PKGCHECK=0
INSTALL_MISSING=0
parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --skip-pkgcheck)
                SKIP_PKGCHECK=1
                shift
                ;;
            --install-missing)
                INSTALL_MISSING=1
                shift
                ;;
            --help|-h)
                cat <<EOF
Usage: $0 [--skip-pkgcheck]

Options:
  --skip-pkgcheck   Do not run the proactive pkg-config checks before running FFmpeg configure.
  --help            Show this help message.
EOF
                exit 0
                ;;
            *)
                # Unknown flags are ignored; script will prompt interactively for missing info
                shift
                ;;
        esac
    done
}

# Parse args early so non-interactive flags apply
parse_args "$@"

# --- Warning ---
warn "This script will compile Python and FFmpeg from source." 
warn "This will take a significant amount of time and disk space."
read -r -p "Press [Enter] to continue or Ctrl+C to cancel..."

# --- Ask about NVIDIA support ---
read -r -p "Enable NVIDIA/CUDA hardware acceleration support for FFmpeg (NVENC/CUDA)? [y/N]: " ENABLE_NVIDIA
ENABLE_NVIDIA=${ENABLE_NVIDIA:-N}

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
    libvorbis-dev
    libxvidcore-dev
    libwebp-dev
    libopenjp2-7-dev
    libaom-dev
    libsvtav1-dev
    libdav1d-dev
    libtesseract-dev
    tesseract-ocr
    tesseract-ocr-eng
    tesseract-ocr-script-latn
    libleptonica-dev
)

if [[ "$ENABLE_NVIDIA" =~ ^[Yy]$ ]]; then
    info "Adding NVIDIA/CUDA related packages to install list (may be distro-specific)."
    # Use distro-provided NVENC headers and FFmpeg NVENC helper package where available.
    # On Ubuntu/Debian these are provided by 'nv-codec-headers' and 'libffmpeg-nvenc-dev'.
    # Some systems may require installing NVIDIA's CUDA toolkit/driver from NVIDIA directly.
    # Append NVIDIA-related packages to the existing PACKAGES array so we don't
    # lose the core build dependencies (e.g., libvorbis-dev) when NVIDIA support
    # is enabled.
    PACKAGES+=(
        nvidia-cuda-toolkit
        libffmpeg-nvenc-dev
    )
fi

sudo apt install -y "${PACKAGES[@]}"
success "Build dependencies installed."

# Quick post-install checks for NVIDIA headers / runtime
if [[ "$ENABLE_NVIDIA" =~ ^[Yy]$ ]]; then
    # Check for distribution NVENC helper package first
    if ! dpkg -s libffmpeg-nvenc-dev >/dev/null 2>&1; then
        warn "libffmpeg-nvenc-dev was not found after apt install."
    fi

    # Look for the NVENC header in common system locations and local prefix
    NVENC_HEADER_FOUND=0
    for p in /usr/include /usr/local/include "$LOCAL_PREFIX/include"; do
        if [ -f "$p/nvEncodeAPI.h" ] || [ -f "$p/nvCodec/nvEncodeAPI.h" ]; then
            NVENC_HEADER_FOUND=1
            break
        fi
    done

    if [ $NVENC_HEADER_FOUND -eq 0 ]; then
        warn "nvEncodeAPI.h not found on the system or in local prefix. FFmpeg NVENC will need these headers."
        info "Attempting to fetch and install nv-codec-headers into local prefix: $LOCAL_PREFIX (no sudo)."

        # Clone and attempt to install into LOCAL_PREFIX without sudo.
        if [ ! -d "$BUILD_DIR/nv-codec-headers" ]; then
            retry "git clone 'https://github.com/FFmpeg/nv-codec-headers.git' '$BUILD_DIR/nv-codec-headers'" || true
        fi

        if [ -d "$BUILD_DIR/nv-codec-headers" ]; then
            pushd "$BUILD_DIR/nv-codec-headers" >/dev/null || true
            # Prefer a make-based install if present; otherwise copy headers to local include.
            if make -n install >/dev/null 2>&1; then
                make || true
                # Try installing into the local prefix; fall back to copying headers.
                if ! make install PREFIX="$LOCAL_PREFIX" >/dev/null 2>&1; then
                    if [ -n "$LOCAL_PREFIX" ] && [[ "$LOCAL_PREFIX" == "$HOME"* ]]; then
                        mkdir -p "$LOCAL_PREFIX/include"
                        cp -v include/*.h "$LOCAL_PREFIX/include/" || true
                    else
                        warn "LOCAL_PREFIX is unsafe ('$LOCAL_PREFIX'); not copying headers to avoid creating root-level paths."
                    fi
                fi
            else
                if [ -n "$LOCAL_PREFIX" ] && [[ "$LOCAL_PREFIX" == "$HOME"* ]]; then
                    mkdir -p "$LOCAL_PREFIX/include"
                    cp -v include/*.h "$LOCAL_PREFIX/include/" || true
                else
                    warn "LOCAL_PREFIX is unsafe ('$LOCAL_PREFIX'); not copying headers to avoid creating root-level paths."
                fi
            fi
            popd >/dev/null || true
        else
            warn "Failed to clone nv-codec-headers; please fetch it manually and place nvEncodeAPI.h into $LOCAL_PREFIX/include or a system include path."
        fi
    else
        success "nvEncodeAPI.h found; NVENC headers are available."
    fi

    if ! command -v nvidia-smi >/dev/null 2>&1; then
        warn "nvidia-smi not found: NVIDIA drivers/toolkit may not be installed. NVENC/NVDEC support requires an installed NVIDIA driver and compatible hardware."
    fi
fi

# Ensure build directory exists and use previously-defined LOCAL_PREFIX
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
mkdir -p "$LOCAL_PREFIX"

# Initialize extra flags to point at local prefix (will be appended to by CUDA detection)
EXTRA_CFLAGS="-I${LOCAL_PREFIX}/include"
EXTRA_LDFLAGS="-L${LOCAL_PREFIX}/lib"

# --- Optional: Build AV1 dependencies from source (libaom, svt-av1, dav1d)
info "Preparing source builds for AV1 libraries (libaom, svt-av1, dav1d)..."
sudo apt install -y git meson ninja-build pkg-config || true

# libaom
if [ ! -d "aom" ]; then
    info "Cloning libaom..."
    retry "git clone 'https://aomedia.googlesource.com/aom' 'aom'" || true
fi
cd aom
info "Building libaom (install prefix: $LOCAL_PREFIX)..."
mkdir -p build
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DENABLE_TESTS=0 -DBUILD_SHARED_LIBS=1 -DCMAKE_INSTALL_PREFIX="$LOCAL_PREFIX"
cmake --build build -j"$(nproc)"
cmake --install build || true
cd ..

# SVT-AV1
if dpkg -s libsvtav1-dev >/dev/null 2>&1; then
    info "libsvtav1-dev detected from distro; skipping SVT-AV1 source build and using system package."
else
if [ ! -d "SVT-AV1" ]; then
    info "Cloning SVT-AV1 (trying known mirrors)..."
    SVT_DIR="SVT-AV1"
    SVT_URLS=(
        "https://github.com/AOMediaCodec/SVT-AV1.git"
        "https://gitlab.com/AOMediaCodec/SVT-AV1.git"
    )
    CLONED=0
    for url in "${SVT_URLS[@]}"; do
        info "Trying $url"
        if git ls-remote "$url" >/dev/null 2>&1; then
            if retry "git clone '$url' '$SVT_DIR'" 4; then
                CLONED=1 && break
            fi
        else
            warn "$url not available or inaccessible."
        fi
    done

    # If cloning failed, try downloading a release tarball (master branch tarball) from known hosts
    if [ $CLONED -ne 1 ]; then
        info "Attempting to download SVT-AV1 tarball from known URLs as a fallback..."
        SVT_TARBALLS=(
            "https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/master/SVT-AV1-master.tar.gz"
        )
        for turl in "${SVT_TARBALLS[@]}"; do
            info "Trying tarball $turl"
            rm -rf "$BUILD_DIR/SVT-AV1"
            mkdir -p "$BUILD_DIR/SVT-AV1"
            if retry "wget -qO- '$turl' | tar -xz -C '$BUILD_DIR/SVT-AV1' --strip-components=1" 4; then
                CLONED=1
                break
            else
                warn "Failed to download/extract $turl"
                rm -rf "$BUILD_DIR/SVT-AV1"
            fi
        done
    fi

    if [ $CLONED -ne 1 ]; then
        warn "Could not obtain SVT-AV1 from known mirrors or tarballs. Attempting to build from GitHub as a last resort."
        if build_svt_from_github; then
            CLONED=1
        else
            warn "Automatic GitHub build of SVT-AV1 failed. Please clone or download it manually into $BUILD_DIR/SVT-AV1."
        fi
    fi
fi

if [ -d "SVT-AV1" ]; then
    cd SVT-AV1
    info "Building SVT-AV1 (install prefix: $LOCAL_PREFIX)..."
    mkdir -p build
    cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$LOCAL_PREFIX"
    cmake --build build -j"$(nproc)"
    cmake --install build || true
    # Ensure the installed SVT-AV1 shared libraries are discoverable at runtime.
    # Prefer installing into /usr/local so the system loader finds them automatically.
            if ls "$LOCAL_PREFIX/lib"/libSvtAv1Enc.so* >/dev/null 2>&1; then
        info "SVT-AV1 libraries installed into $LOCAL_PREFIX/lib"
        # If the system linker already knows about a matching soname, nothing to do.
        if ldconfig -p | grep -q "libSvtAv1Enc.so"; then
            info "libSvtAv1Enc already available to system linker."
        else
            # If we can run sudo non-interactively, install into /usr/local.
            if sudo -n true 2>/dev/null; then
                info "Installing SVT-AV1 into /usr/local so ffmpeg can load it at runtime..."
                # Try using cmake install to /usr/local; fall back to copying files.
                if ! sudo cmake --install build --prefix /usr/local >/dev/null 2>&1; then
                    info "cmake --install to /usr/local failed; copying libraries to /usr/local/lib as fallback."
                    sudo install -v -m 0755 "$LOCAL_PREFIX/lib"/libSvtAv1Enc.so* /usr/local/lib/ || true
                fi
                sudo ldconfig || true
            else
                # No sudo: add rpath so the ffmpeg binary can find the local libs without ldconfig.
                warn "sudo not available: will embed rpath in FFmpeg build so it can find $LOCAL_PREFIX/lib at runtime."
                EXTRA_LDFLAGS="$EXTRA_LDFLAGS -Wl,-rpath,$LOCAL_PREFIX/lib"
            fi
        fi
    else
        warn "SVT-AV1 build completed but no libSvtAv1Enc.* files found in $LOCAL_PREFIX/lib"
    fi
    cd ..
else
    warn "SVT-AV1 directory missing; skipping SVT-AV1 build."
fi
fi

# dav1d
if [ ! -d "dav1d" ]; then
    info "Cloning dav1d..."
    retry "git clone 'https://code.videolan.org/videolan/dav1d.git' 'dav1d'" || true
fi
cd dav1d
info "Building dav1d (install prefix: $LOCAL_PREFIX)..."
meson setup build --buildtype release -Ddefault_library=shared --prefix "$LOCAL_PREFIX" || meson setup build --buildtype release --prefix "$LOCAL_PREFIX"
ninja -C build -j"$(nproc)"
ninja -C build install || true
cd ..

export PKG_CONFIG_PATH="$LOCAL_PREFIX/lib/pkgconfig:$LOCAL_PREFIX/lib64/pkgconfig:${PKG_CONFIG_PATH:-}"

# Ensure dav1d is available for FFmpeg
if ! ensure_pkg dav1d 0.5.0; then
    warn "ERROR: dav1d >= 0.5.0 not found. See previous messages for how to make it discoverable to pkg-config."
    exit 1
fi

# Verify libvorbis (vorbis) is discoverable; try auto-discovery like for dav1d
if ! pkg-config --exists "vorbis"; then
    warn "vorbis not found via pkg-config. Attempting to auto-discover .pc files under $BUILD_DIR..."

    FOUND_PKG_DIRS=()
    while IFS= read -r pc; do
        pkgdir=$(dirname "$pc")
        case " ${FOUND_PKG_DIRS[*]} " in
            *" $pkgdir "*) ;;
            *) FOUND_PKG_DIRS+=("$pkgdir");;
        esac
    done < <(find "$BUILD_DIR" -type f -name '*.pc' 2>/dev/null || true)

    if ! ensure_pkg vorbis; then
        warn "ERROR: vorbis not found via pkg-config and auto-discovery failed. Consider: sudo apt install libvorbis-dev"
        exit 1
    fi
fi

# --- 2. Compile Python from Source ---
info "Compiling Python $PYTHON_VERSION..."
if [ ! -f "Python-$PYTHON_VERSION.tar.xz" ]; then
    retry "wget -q -O 'Python-$PYTHON_VERSION.tar.xz' 'https://www.python.org/ftp/python/$PYTHON_VERSION/Python-$PYTHON_VERSION.tar.xz'" 4 || true
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

# --- 3. Compile FFmpeg from Source (with optional NVIDIA support) ---
info "Compiling FFmpeg $FFMPEG_VERSION..."
if [ ! -f "ffmpeg-$FFMPEG_VERSION.tar.bz2" ]; then
    retry "wget -q -O 'ffmpeg-$FFMPEG_VERSION.tar.bz2' 'https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.bz2'" 4 || true
fi
tar -xf "ffmpeg-$FFMPEG_VERSION.tar.bz2"
cd "ffmpeg-$FFMPEG_VERSION"

# Ensure pkg-config can find locally installed libraries
export PKG_CONFIG_PATH="$LOCAL_PREFIX/lib/pkgconfig:$LOCAL_PREFIX/lib64/pkgconfig:${PKG_CONFIG_PATH}"

# Detect CUDA installation if requested
CUDA_PREFIX=""
NV_FLAGS=()
if [[ "$ENABLE_NVIDIA" =~ ^[Yy]$ ]]; then
    if command -v nvcc >/dev/null 2>&1; then
        CUDA_PREFIX="$(dirname "$(dirname "$(command -v nvcc)")")"
        info "Detected nvcc at: $CUDA_PREFIX"
    elif [ -d "/usr/local/cuda" ]; then
        CUDA_PREFIX="/usr/local/cuda"
        info "Found CUDA at /usr/local/cuda"
    else
        warn "CUDA toolkit not found on PATH or /usr/local/cuda. The script installed 'nvidia-cuda-toolkit' package; if CUDA is still missing consider installing NVIDIA's CUDA toolkit from developer.nvidia.com."
    fi

    if [ -n "$CUDA_PREFIX" ]; then
        EXTRA_CFLAGS="$EXTRA_CFLAGS -I${CUDA_PREFIX}/include"
        EXTRA_LDFLAGS="$EXTRA_LDFLAGS -L${CUDA_PREFIX}/lib64"
    NV_FLAGS+=("--enable-cuda" "--enable-cuvid" "--enable-nvenc" "--enable-nvdec" "--enable-libnpp")
        info "NVIDIA/CUDA support will be enabled for FFmpeg."
    else
        warn "CUDA not located — proceeding without GPU acceleration support for FFmpeg."
    fi
fi

# Configure FFmpeg with many codecs and optional NVIDIA support
if [ "$SKIP_PKGCHECK" -eq 0 ]; then
    info "Checking for common pkg-config dependencies before running FFmpeg configure..."
    MISSING=()
    COMMON_PKGS=(x264 x265 vpx aom svtav1 dav1d opus vorbis)
    for pkg in "${COMMON_PKGS[@]}"; do
        if ! ensure_pkg "$pkg"; then
            MISSING+=("$pkg")
        fi
    done
    if [ ${#MISSING[@]} -gt 0 ]; then
        warn "The following pkg-config packages appear missing or undiscoverable: ${MISSING[*]}"

        # If svtav1 is missing, try to build SVT-AV1 from GitHub into the local prefix
        for idx in "${!MISSING[@]}"; do
            if [ "${MISSING[$idx]}" = "svtav1" ]; then
                warn "svtav1 missing: attempting to build SVT-AV1 from source into $LOCAL_PREFIX as a fallback."
                if build_svt_from_github; then
                    info "SVT-AV1 built into $LOCAL_PREFIX; retrying pkg-config discovery."
                    # retry discovery
                    if ensure_pkg svtav1; then
                        unset 'MISSING[$idx]'
                    fi
                else
                    warn "Automated SVT-AV1 build failed; proceeding with normal install flow." 
                fi
            fi
        done

        # Mapping from pkg names to apt package names
        declare -A PKG_TO_APT=(
            [x264]=libx264-dev
            [x265]=libx265-dev
            [vpx]=libvpx-dev
            [aom]=libaom-dev
            [svtav1]=libsvtav1-dev
            [dav1d]=libdav1d-dev
            [opus]=libopus-dev
            [vorbis]=libvorbis-dev
        )

        if [ "$INSTALL_MISSING" -eq 1 ]; then
            APT_LIST=()
            for p in "${MISSING[@]}"; do
                if [ -n "${PKG_TO_APT[$p]:-}" ]; then
                    APT_LIST+=("${PKG_TO_APT[$p]}")
                else
                    warn "No apt mapping known for pkg '$p' — skipping automatic install for this item."
                fi
            done
            if [ ${#APT_LIST[@]} -gt 0 ]; then
                info "Attempting to install missing apt packages: ${APT_LIST[*]}"
                echo "This will run: sudo apt update && sudo apt install -y ${APT_LIST[*]}"
                read -r -p "Proceed with apt install? [y/N]: " _ans
                if [[ "${_ans}" =~ ^[Yy]$ ]]; then
                    if ! sudo apt update || ! sudo apt install -y "${APT_LIST[@]}"; then
                        warn "apt install failed for some packages. Will attempt special-case fallbacks where possible."
                        # Special-case: if libvorbis-dev was requested, try to download from Launchpad (Ubuntu noble)
                        for p in "${APT_LIST[@]}"; do
                            if [ "$p" = "libvorbis-dev" ]; then
                                warn "Attempting fallback: download libvorbis-dev .deb from Launchpad (Ubuntu noble)"
                                tmpdir=$(mktemp -d)
                                page="$tmpdir/page.html"
                                deb="$tmpdir/libvorbis-dev.deb"
                                if wget -q -O "$page" "https://launchpad.net/ubuntu/noble/+package/libvorbis-dev"; then
                                    # Grep for .deb links (arm/amd64) and pick the first amd64 one if available
                                    deb_url=$(grep -oE "https?://[^\"']+\\.deb" "$page" | grep amd64 | head -n 1 || true)
                                    if [ -z "$deb_url" ]; then
                                        deb_url=$(grep -oE "https?://[^\"']+\\.deb" "$page" | head -n 1 || true)
                                    fi
                                    if [ -n "$deb_url" ]; then
                                        info "Found .deb URL: $deb_url"
                                        if wget -q -O "$deb" "$deb_url"; then
                                            info "Installing downloaded .deb: $deb"
                                            sudo dpkg -i "$deb" || true
                                            sudo apt-get -f install -y || true
                                        else
                                            warn "Failed to download .deb from $deb_url"
                                        fi
                                    else
                                        warn "Could not find a .deb link on Launchpad page for libvorbis-dev."
                                    fi
                                else
                                    warn "Failed to fetch Launchpad page; cannot auto-download .deb."
                                fi
                                rm -rf "$tmpdir" || true
                            fi
                        done
                    fi
                    info "Retrying pkg-config checks after apt install/fallbacks..."
                    STILL_MISSING=()
                    for pkg in "${MISSING[@]}"; do
                        if ! ensure_pkg "$pkg"; then
                            STILL_MISSING+=("$pkg")
                        fi
                    done
                    if [ ${#STILL_MISSING[@]} -gt 0 ]; then
                        warn "Some packages are still not discoverable after installation or fallbacks: ${STILL_MISSING[*]}"
                        warn "Please check installation or set PKG_CONFIG_PATH appropriately."
                        exit 1
                    else
                        success "All missing packages resolved after apt install/fallbacks."
                    fi
                else
                    warn "User declined to install apt packages. Exiting to allow manual fix."
                    exit 1
                fi
            else
                warn "No apt package candidates to install for missing pkgs: ${MISSING[*]}"
                warn "Please install the required -dev packages or ensure their .pc files are discoverable via PKG_CONFIG_PATH."
                exit 1
            fi
        else
            warn "Install missing packages automatically by running this script with --install-missing or install them manually (e.g., sudo apt install libx264-dev ...)."
            exit 1
        fi
    fi
else
    info "Skipping proactive pkg-config checks because --skip-pkgcheck was provided."
fi

./configure \
    --enable-gpl \
    --enable-libx264 \
    --enable-libx265 \
    --enable-libvpx \
    --enable-libfdk-aac \
    --enable-libmp3lame \
    --enable-libopus \
    --enable-libvorbis \
    --enable-libxvid \
    --enable-libwebp \
    --enable-libaom \
    --enable-libsvtav1 \
    --enable-libdav1d \
    --enable-nonfree \
    --enable-libtesseract \
    "${NV_FLAGS[@]}" \
    --extra-cflags="$EXTRA_CFLAGS" \
    --extra-ldflags="$EXTRA_LDFLAGS"

# Some SVT-AV1 releases changed the svt_av1_enc_init_handle signature (reordered/removed
# a parameter). FFmpeg versions that expect the old 3-arg call will fail to compile.
# Apply a local, idempotent patch to the FFmpeg source to call the API that matches the
# installed SVT-AV1 headers when needed. This is safe because it only replaces the
# exact old call site and leaves other code untouched.
if [ -f "libavcodec/libsvtav1.c" ]; then
    if grep -q "svt_av1_enc_init_handle(&svt_enc->svt_handle, svt_enc, &svt_enc->enc_params)" libavcodec/libsvtav1.c; then
        info "Patching libavcodec/libsvtav1.c to match installed SVT-AV1 API (robust replace)..."
        # Create a backup if one doesn't already exist
        if [ ! -f libavcodec/libsvtav1.c.svtapi.bak ]; then
            cp -v libavcodec/libsvtav1.c libavcodec/libsvtav1.c.svtapi.bak || true
        fi
        tmpf=$(mktemp)
        # Try a robust perl-based replace of the first matching svt_av1_enc_init_handle call.
        # This replaces the first occurrence only and writes to a temporary file.
        perl -0777 -pe 's/\bsvt_ret\s*=\s*svt_av1_enc_init_handle\([^;]*?svt_enc[^;]*?enc_params\);/svt_ret = svt_av1_enc_init_handle(&svt_enc->svt_handle, &svt_enc->enc_params);/s' libavcodec/libsvtav1.c > "$tmpf" || true
        # Validate the temp file contains the expected corrected call before replacing the original.
        if [ -f "$tmpf" ] && grep -q "svt_av1_enc_init_handle(&svt_enc->svt_handle, &svt_enc->enc_params)" "$tmpf"; then
            mv -f "$tmpf" libavcodec/libsvtav1.c
            info "Patched libavcodec/libsvtav1.c successfully (perl)."
        else
            warn "Automated perl patch failed or did not produce expected output. Restoring from backup and leaving source unchanged."
            rm -f "$tmpf" || true
            if [ -f libavcodec/libsvtav1.c.svtapi.bak ]; then
                cp -v libavcodec/libsvtav1.c.svtapi.bak libavcodec/libsvtav1.c || true
            fi
        fi
    else
        info "No SVT-AV1 API patch necessary (call site absent or already patched)."
    fi
else
    warn "FFmpeg source libavcodec/libsvtav1.c not found; cannot apply SVT-AV1 API patch."
fi

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
pip install --upgrade pip setuptools wheel

# Locate requirements.txt: prefer project dir, then script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQ_FILE_PATH=""
if [ -f "$PROJECT_DIR/requirements.txt" ]; then
    REQ_FILE_PATH="$PROJECT_DIR/requirements.txt"
elif [ -f "$SCRIPT_DIR/requirements.txt" ]; then
    REQ_FILE_PATH="$SCRIPT_DIR/requirements.txt"
fi

if [ -n "$REQ_FILE_PATH" ]; then
    info "Installing Python packages from $REQ_FILE_PATH"
    if ! pip install -r "$REQ_FILE_PATH"; then
        warn "pip install -r failed; falling back to individual package installs"
        pip install torch torchaudio --index-url https://download.pytorch.org/whl/cpu || true
        pip install Flask face_recognition opencv-python pyannote.audio || true
    fi
else
    info "No requirements.txt found; installing default packages"
    pip install torch torchaudio --index-url https://download.pytorch.org/whl/cpu || true
    pip install Flask face_recognition opencv-python pyannote.audio || true
fi
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
