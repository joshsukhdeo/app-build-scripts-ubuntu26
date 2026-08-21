#!/usr/bin/env bash

# build_mpv_vapoursynth_hardened.sh
# Hardened version of the mpv + VapourSynth build script
# Applies strict error handling and defensive programming patterns

set -Eeuo pipefail
shopt -s inherit_errexit 2>/dev/null || true

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
readonly VS_VENV="/opt/vapoursynth-venv"
readonly USER_NAME="${SUDO_USER:-$USER}"

# -----------------------------------------------------------------------------
# Parameter Parsing
# -----------------------------------------------------------------------------
ALL_CODECS=false
STD_FLAGS=false
DISABLE_PROFILING=false

show_help() {
    cat << HELP
Usage: $0 [OPTIONS]

Builds a highly optimized, PGO-enabled mpv and VapourSynth stack.

Default behavior:
  - Compiles FFmpeg with only the necessary hardware accelerators for your GPU (disables unused hwaccels).
  - Applies aggressive experimental hardware optimizations (CFLAGS: -flto -fuse-ld=lld -march=native -mtune=native).
  - Executes a PGO (Profile-Guided Optimization) build for mpv.

Options:
  -h, --help                 Show this help message and exit.
  --std-flags-only           Disable aggressive experimental hardware optimizations (keeps standard optimizations).
  --no-experimental-flags    Alias for --std-flags-only.
  --all-codecs               Build FFmpeg with all codecs (do not disable unused hwaccels). Explicitly discouraged.
  --unoptimized              Alias for --std-flags-only + --all-codecs. Explicitly discouraged.
  --disable-profiling        Skip the PGO execution block for mpv (build once normally). Explicitly discouraged.
HELP
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            ;;
        --std-flags-only|--no-experimental-flags)
            STD_FLAGS=true
            shift
            ;;
        --all-codecs)
            ALL_CODECS=true
            shift
            ;;
        --unoptimized)
            STD_FLAGS=true
            ALL_CODECS=true
            shift
            ;;
        --disable-profiling)
            DISABLE_PROFILING=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
done

if [[ "$STD_FLAGS" == true ]]; then
    export CFLAGS="-O2 -pipe"
    export CXXFLAGS="-O2 -pipe"
    export LDFLAGS="-lstdc++ -Wl,-O1 -Wl,--as-needed"
else
    export CFLAGS="-O3 -march=native -mtune=native -pipe -fno-plt -fno-semantic-interposition"
    export CXXFLAGS="-O3 -march=native -mtune=native -pipe -fno-plt -fno-semantic-interposition"
    export LDFLAGS="-fuse-ld=lld -lstdc++ -Wl,-O1 -Wl,--as-needed -Wl,--sort-common -Wl,-z,now"
fi
export CC="clang"
export CXX="clang++"
export AR="llvm-ar"
export NM="llvm-nm"
export RANLIB="llvm-ranlib"

# -----------------------------------------------------------------------------
# Core Functions
# -----------------------------------------------------------------------------

# shellcheck source=utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
trap cleanup EXIT ERR

# -----------------------------------------------------------------------------
# Core Functions
# -----------------------------------------------------------------------------

check_prerequisites() {
    log_info "Checking prerequisites..."
    if ! command -v git >/dev/null 2>&1; then
        log_info "git not found, installing prerequisites will fix this."
    fi
}

clear_build_caches() {
    log_step "Clearing build caches..."
    rm -rf zimg vapoursynth mpv-build
    sudo apt-get clean
}

install_dependencies() {
    log_step "Updating packages and installing required dependencies..."
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        git build-essential ninja-build python3-pip python3-dev \
        yasm nasm libtool autoconf automake cmake libfribidi-dev libfontconfig1-dev \
        libfreetype6-dev libharfbuzz-dev liblcms2-dev libx11-dev libxv-dev libvulkan-dev \
        libgl1-mesa-dev libegl1-mesa-dev libxkbcommon-dev libwayland-dev libxrandr-dev \
        python3-setuptools python3-wheel libzimg-dev libmujs-dev \
        luajit libluajit-5.1-dev libssl-dev libplacebo-dev libshaderc-dev \
        libass-dev libbluray-dev libdvdread-dev libdvdnav-dev libuchardet-dev \
        mediainfo lsof libqt5concurrent5 libqt5svg5 libqt5qml5 \
        libmimalloc-dev numactl clang lld llvm libstdc++-16-dev \
        libpipewire-0.3-dev libpulse-dev libasound2-dev \
        libarchive-dev libva-dev libvdpau-dev librubberband-dev
}

setup_python_venv() {
    log_step "Setting up latest Python virtualenv with mise at ${VS_VENV}..."
    sudo mkdir -p "${VS_VENV}"
    sudo chown -R "${USER_NAME}:${USER_NAME}" "${VS_VENV}"
    
    if command -v mise >/dev/null 2>&1; then
        mise install python@3.14.7
        if [[ ! -d "${VS_VENV}/bin" ]]; then
            mise exec python@3.14.7 -- python -m venv "${VS_VENV}"
        fi
    else
        log_err "mise is not installed or not in PATH."
        exit 1
    fi
    
    # Bootstrap pip inside the venv
    "${VS_VENV}/bin/python" -m ensurepip --upgrade
    
    # shellcheck source=/dev/null
    source "${VS_VENV}/bin/activate"
    python -m pip install --upgrade pip
    python -m pip install meson ninja cython
}

build_zimg() {
    log_step "Building and Installing zimg"
    if [[ ! -d "zimg" ]]; then
        git clone --recursive https://github.com/sekrit-twc/zimg.git
    fi
    pushd zimg >/dev/null
    git fetch origin
    git checkout master
    git pull origin master
    git submodule update --init --recursive
    ./autogen.sh
    ./configure
    make "-j$(nproc)"
    sudo make install
    sudo ldconfig
    popd >/dev/null
}

build_vapoursynth() {
    log_step "Building and Installing VapourSynth"
    if [[ ! -d "vapoursynth" ]]; then
        git clone https://github.com/vapoursynth/vapoursynth.git
    fi
    pushd vapoursynth >/dev/null
    git fetch origin
    git checkout master
    git pull origin master

    rm -rf build
    
    # Activate venv so meson detects and links against our specific Python
    source "${VS_VENV}/bin/activate"
    
    meson setup build
    meson compile -C build
    sudo "$(command -v meson)" install -C build

    # Create symlinks for vspipe and vapoursynth just in case
    sudo ln -sf "${VS_VENV}/bin/vspipe" /usr/local/bin/vspipe
    sudo ln -sf "${VS_VENV}/bin/vapoursynth" /usr/local/bin/vapoursynth
    
    sudo ldconfig
    popd >/dev/null
}

install_vs_plugins() {
    log_step "Installing zsmooth, essential VapourSynth plugins, and yt-dlp"
    # shellcheck source=/dev/null
    source "${VS_VENV}/bin/activate"
    
    # Use uv for blazingly fast dependency installation and resolution
    python -m pip install --upgrade pip uv
    
    # Install yt-dlp with [default] extras for maximum download performance (brotli, websockets, etc)
    uv pip install --upgrade vsutil vstools vskernels havsfunc psutil numpy scipy numexpr orjson "yt-dlp[default]"
    uv pip install --upgrade --reinstall git+https://github.com/adworacz/zsmooth.git
    uv pip install --upgrade --reinstall git+https://github.com/HomeOfVapourSynthEvolution/mvsfunc.git
    
    # Symlink yt-dlp so mpv and the system can use it
    sudo ln -sf "${VS_VENV}/bin/yt-dlp" /usr/local/bin/yt-dlp
}

fetch_mpv_sources() {
    log_step "Fetching mpv and ffmpeg sources in the background..."
    if [[ ! -d "mpv-build" ]]; then
        git clone https://github.com/mpv-player/mpv-build.git
    fi
    pushd mpv-build >/dev/null
    ./use-ffmpeg-master
    ./use-mpv-master
    ./use-libass-master
    git pull origin master
    ./update
    popd >/dev/null
}

build_mpv() {
    log_step "Building mpv and FFmpeg with mpv-build"
    # Sources were already cloned in the background by fetch_mpv_sources
    pushd mpv-build >/dev/null

    # Clean any previous builds to ensure options are applied cleanly
    ./clean

    log_info "Configuring FFmpeg options dynamically based on GPU..."
    
    # Detect GPU
    local gpu_flags=""
    if [[ "$ALL_CODECS" == true ]]; then
        log_info "--all-codecs or --unoptimized passed. Building all codecs."
    elif lspci | grep -iE 'vga|3d|display' | grep -i intel >/dev/null; then
        log_info "Intel GPU detected. Enabling VAAPI and OpenVINO, disabling AMD/Nvidia specific hwaccels."
        gpu_flags="--enable-vaapi
--disable-amf
--disable-nvenc
--disable-cuvid
--disable-ffnvcodec"
    elif lspci | grep -iE 'vga|3d|display' | grep -i nvidia >/dev/null; then
        log_info "Nvidia GPU detected. Enabling NVENC/CUVID, disabling AMD/Intel specific hwaccels."
        gpu_flags="--enable-nvenc
--enable-cuvid
--enable-ffnvcodec
--disable-vaapi
--disable-amf"
    elif lspci | grep -iE 'vga|3d|display' | grep -i amd >/dev/null; then
        log_info "AMD GPU detected. Enabling AMF/VAAPI, disabling Nvidia specific hwaccels."
        gpu_flags="--enable-amf
--enable-vaapi
--disable-nvenc
--disable-cuvid
--disable-ffnvcodec"
    else
        log_info "No specific recognized GPU detected. Falling back to default."
        gpu_flags="--disable-amf
--disable-nvenc
--disable-cuvid
--disable-ffnvcodec"
    fi

    local ffmpeg_extra_cflags=""
    local ffmpeg_extra_ldflags=""
    if [[ "$STD_FLAGS" == true ]]; then
        ffmpeg_extra_cflags="-O2 -pipe"
        ffmpeg_extra_ldflags=""
    else
        ffmpeg_extra_cflags="-O3 -march=native -mtune=native -pipe -fno-plt -flto -fuse-ld=lld"
        ffmpeg_extra_ldflags="-fuse-ld=lld"
    fi

    cat > ffmpeg_options << EOF
--cc=clang
--cxx=clang++
--ar=llvm-ar
--nm=llvm-nm
--ranlib=llvm-ranlib
--enable-vapoursynth
--enable-libzimg
--enable-gpl
--enable-version3
--enable-nonfree
$([[ "$STD_FLAGS" == false ]] && echo "--enable-lto")
--disable-doc
$(echo -e "$gpu_flags")
--extra-cflags=${ffmpeg_extra_cflags}
--extra-cxxflags=${ffmpeg_extra_cflags}
--extra-ldflags=${ffmpeg_extra_ldflags}
EOF

    log_info "Configuring mpv options..."
    local mpv_c_args=""
    local mpv_link_args=""
    local mpv_lto="false"
    local mpv_optimization="2"
    if [[ "$STD_FLAGS" == true ]]; then
        mpv_c_args="-pipe"
        mpv_link_args=""
    else
        mpv_c_args="-march=native -mtune=native -pipe"
        mpv_link_args="-fuse-ld=lld"
        mpv_lto="true"
        mpv_optimization="3"
    fi

    cat > mpv_options << EOF
-Dlua=luajit
-Djavascript=enabled
-Dvapoursynth=enabled
-Dlibarchive=enabled
-Drubberband=enabled
-Doptimization=${mpv_optimization}
-Db_lto=${mpv_lto}
$([[ "$DISABLE_PROFILING" == false ]] && echo "-Db_pgo=generate")
-Dc_args=${mpv_c_args}
-Dcpp_args=${mpv_c_args}
$([[ -n "$mpv_link_args" ]] && echo "-Dc_link_args=${mpv_link_args}")
$([[ -n "$mpv_link_args" ]] && echo "-Dcpp_link_args=${mpv_link_args}")
-Dalsa=enabled
-Dpulse=enabled
-Dpipewire=enabled
EOF

    log_info "Running rebuild to compile FFmpeg and mpv (PGO Pass 1)..."
    ./update
    ./clean
    scripts/libplacebo-config
    scripts/libplacebo-build "-j$(nproc)"

    log_info "Patching libplacebo.pc to include -lstdc++ statically..."
    sed -i 's/-lplacebo/-lplacebo -lstdc++/' build_libs/lib/pkgconfig/libplacebo.pc

    scripts/libass-config
    scripts/libass-build "-j$(nproc)"
    scripts/ffmpeg-config
    scripts/ffmpeg-build "-j$(nproc)"
    scripts/mpv-config
    scripts/mpv-build "-j$(nproc)"
    if [[ "$DISABLE_PROFILING" == false ]]; then
        log_info "Running headless mpv to generate PGO profiling data..."
        export LLVM_PROFILE_FILE="default_%p.profraw"
        ./mpv/build/mpv "av://lavfi:testsrc=size=1920x1080:rate=60:duration=10" -vo=null -ao=null || true
        
        log_info "Merging profraw files into profdata..."
        llvm-profdata merge -output=mpv/build/default.profdata *.profraw || true

        log_info "Configuring mpv options (PGO Use Phase)..."
        sed -i 's/-Db_pgo=generate/-Db_pgo=use/g' mpv_options
        
        log_info "Rebuilding mpv (PGO Pass 2)..."
        scripts/mpv-config
        scripts/mpv-build "-j$(nproc)"
    fi

    log_info "Installing mpv..."
    sudo "${VS_VENV}/bin/meson" install -C mpv/build

    log_info "Setting up jemalloc and VapourSynth python env wrapper for mpv..."
    if [[ -f "/usr/local/bin/mpv" ]]; then
        sudo mv /usr/local/bin/mpv /usr/local/bin/mpv-bin
    fi
    
    local vs_python_site_packages
    vs_python_site_packages=$(ls -d /opt/vapoursynth-venv/lib/python*/site-packages | head -n 1)
    
    sudo tee /usr/local/bin/mpv > /dev/null << EOF
#!/bin/bash
export LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libmimalloc.so
export MIMALLOC_LARGE_OS_PAGES=1
export PYTHONPATH=${vs_python_site_packages}:\${PYTHONPATH:-}
export VSSCRIPT_PATH=${vs_python_site_packages}/vapoursynth/libvsscript.so
export OCL_ICD_VENDORS=none
exec /usr/local/bin/mpv-bin "\$@"
EOF
    sudo chmod +x /usr/local/bin/mpv

    log_info "Installing compiled FFmpeg to PATH..."
    sudo make -C ffmpeg_build install
    sudo cp ffmpeg_build/ffmpeg /usr/local/bin/ffmpeg
    sudo cp ffmpeg_build/ffprobe /usr/local/bin/ffprobe
    sudo chmod +x /usr/local/bin/ffmpeg /usr/local/bin/ffprobe

    popd >/dev/null
}

install_dummy_packages() {
    log_step "Generating equivs dummy packages for mpv, ffmpeg, and vapoursynth..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get --fix-broken install -y equivs
    
    # mpv dummy
    cat << 'EOF' > /tmp/mpv-dummy
Section: video
Priority: optional
Standards-Version: 3.9.2

Package: mpv
Version: 99:1.0.0-custom
Maintainer: Local Admin <admin@localhost>
Architecture: all
Description: Dummy package for custom mpv build
 This package prevents apt from installing the repository version of mpv,
 satisfying dependencies for other packages.
EOF

    # ffmpeg dummy
    cat << 'EOF' > /tmp/ffmpeg-dummy
Section: video
Priority: optional
Standards-Version: 3.9.2

Package: ffmpeg
Version: 99:7.0.0-custom
Maintainer: Local Admin <admin@localhost>
Architecture: all
Description: Dummy package for custom ffmpeg build
EOF

    # vapoursynth dummy
    cat << 'EOF' > /tmp/vapoursynth-dummy
Section: video
Priority: optional
Standards-Version: 3.9.2

Package: vapoursynth
Version: 99:65.0-custom
Maintainer: Local Admin <admin@localhost>
Architecture: all
Provides: libvapoursynth, libvapoursynth-dev, python3-vapoursynth
Description: Dummy package for custom vapoursynth build
EOF

    pushd /tmp >/dev/null
    
    equivs-build mpv-dummy
    sudo dpkg -i mpv_1.0.0-custom_all.deb
    rm mpv-dummy mpv_1.0.0-custom_all.deb
    
    equivs-build ffmpeg-dummy
    sudo dpkg -i ffmpeg_7.0.0-custom_all.deb
    rm ffmpeg-dummy ffmpeg_7.0.0-custom_all.deb

    equivs-build vapoursynth-dummy
    sudo dpkg -i vapoursynth_65.0-custom_all.deb
    rm vapoursynth-dummy vapoursynth_65.0-custom_all.deb
    
    popd >/dev/null
}

finalize_installation() {
    log_step "Registering VapourSynth installation for the current user..."
    # Ensure this runs in the context of the user, not root
    if command -v vapoursynth >/dev/null 2>&1; then
        vapoursynth register-install
    else
        log_err "vapoursynth command not found. Registration failed."
    fi

    log_step "Build and installation complete!"
    log_info "You can verify the VapourSynth filter is available by running:"
    log_info "mpv --vf=help | grep vapoursynth"
}

# -----------------------------------------------------------------------------
# Main Execution
# -----------------------------------------------------------------------------
main() {
    check_prerequisites
    clear_build_caches
    install_dependencies
    
    # Phase 1: Heavy network and independent tasks parallelized
    fetch_mpv_sources &
    pid_mpv_fetch=$!
    
    ( setup_python_venv && install_vs_plugins ) &
    pid_python=$!
    
    build_zimg &
    pid_zimg=$!
    
    wait $pid_python
    wait $pid_zimg
    
    build_vapoursynth
    wait $pid_mpv_fetch
    
    build_mpv
    install_dummy_packages
    finalize_installation
}

main "$@"
