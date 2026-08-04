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

# Optimized compilation flags for best hardware performance and stability
export CFLAGS="-O3 -march=native -mtune=native -pipe -fno-plt -fno-semantic-interposition"
export CXXFLAGS="-O3 -march=native -mtune=native -pipe -fno-plt -fno-semantic-interposition"
export LDFLAGS="-Wl,-O1 -Wl,--as-needed -Wl,--sort-common -Wl,-z,now"

# -----------------------------------------------------------------------------
# Logging Functions
# -----------------------------------------------------------------------------
log_info() {
    printf "[INFO] %s\n" "$*"
}

log_err() {
    printf "[ERROR] %s\n" "$*" >&2
}

log_step() {
    printf "\n======================================\n"
    printf " %s\n" "$*"
    printf "======================================\n"
}

cleanup() {
    local exit_code=$?
    if [[ ${exit_code} -ne 0 ]]; then
        log_err "Script failed with exit code ${exit_code} at line ${BASH_LINENO[0]}."
    fi
}
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
        libjemalloc2 libjemalloc-dev numactl \
        libpipewire-0.3-dev libpulse-dev libasound2-dev
}

setup_python_venv() {
    log_step "Setting up latest Python virtualenv with mise at ${VS_VENV}..."
    sudo mkdir -p "${VS_VENV}"
    sudo chown -R "${USER_NAME}:${USER_NAME}" "${VS_VENV}"
    
    if command -v mise >/dev/null 2>&1; then
        mise install python@latest
        if [[ ! -d "${VS_VENV}/bin" ]]; then
            mise exec python@latest -- python -m venv "${VS_VENV}"
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
    meson setup build
    meson compile -C build
    sudo "$(command -v meson)" install -C build

    local vs_pkg_config
    vs_pkg_config=$(find /usr -name "vapoursynth.pc" 2>/dev/null | head -n 1 || true)
    
    if [[ -n "${vs_pkg_config}" ]]; then
        export PKG_CONFIG_PATH="$(dirname "${vs_pkg_config}"):${PKG_CONFIG_PATH:-}"
        log_info "Found vapoursynth pkgconfig at $(dirname "${vs_pkg_config}")"
        
        local vs_lib_dir
        vs_lib_dir=$(dirname "${vs_pkg_config}")
        vs_lib_dir=$(dirname "${vs_lib_dir}")
        local vs_include_dir="${vs_lib_dir}/include"
        
        if [[ -d "${vs_include_dir}" ]]; then
            sudo mkdir -p /usr/local/include/vapoursynth
            sudo cp -r "${vs_include_dir}"/*.h /usr/local/include/vapoursynth/
        fi
        
        sudo cp -a "${vs_lib_dir}"/libvapoursynth*.so* /usr/local/lib/
        sudo ldconfig
        
        sudo ln -sf "${VS_VENV}/bin/vspipe" /usr/local/bin/vspipe
        sudo ln -sf "${VS_VENV}/bin/vapoursynth" /usr/local/bin/vapoursynth
    else
        log_err "WARNING: Could not find vapoursynth.pc"
    fi
    popd >/dev/null
}

install_vs_plugins() {
    log_step "Installing zsmooth, essential VapourSynth plugins, and yt-dlp"
    # shellcheck source=/dev/null
    source "${VS_VENV}/bin/activate"
    
    # Always force upgrade for python modules and tools using python -m pip
    python -m pip install --upgrade pip
    python -m pip install --upgrade vsutil vstools vskernels havsfunc psutil numpy scipy numexpr orjson yt-dlp
    python -m pip install --upgrade --force-reinstall git+https://github.com/adworacz/zsmooth.git
    python -m pip install --upgrade --force-reinstall git+https://github.com/HomeOfVapourSynthEvolution/mvsfunc.git
    
    # Symlink yt-dlp so mpv and the system can use it
    sudo ln -sf "${VS_VENV}/bin/yt-dlp" /usr/local/bin/yt-dlp
}

build_mpv() {
    log_step "Building mpv and FFmpeg with mpv-build"
    if [[ ! -d "mpv-build" ]]; then
        git clone https://github.com/mpv-player/mpv-build.git
    fi
    pushd mpv-build >/dev/null

    log_info "Fetching the latest FFmpeg, libass, and mpv sources..."
    git pull origin master
    ./update

    # Clean any previous builds to ensure options are applied cleanly
    ./clean

    log_info "Configuring FFmpeg options..."
    cat > ffmpeg_options << 'EOF'
--enable-vapoursynth
--enable-libzimg
--enable-gpl
--enable-version3
--enable-nonfree
--disable-cuda-llvm
--disable-cuvid
--disable-nvdec
--disable-nvenc
--enable-vaapi
--enable-lto
--extra-cflags=-O3 -march=native -mtune=native -pipe -fno-plt
--extra-cxxflags=-O3 -march=native -mtune=native -pipe -fno-plt
EOF

    log_info "Configuring mpv options..."
    cat > mpv_options << 'EOF'
-Dlua=luajit
-Djavascript=enabled
-Dvapoursynth=enabled
-Doptimization=3
-Db_lto=true
-Dc_args=-march=native -mtune=native -pipe
-Dcpp_args=-march=native -mtune=native -pipe
-Dalsa=enabled
-Dpulse=enabled
-Dpipewire=enabled
EOF

    log_info "Running rebuild to compile FFmpeg and mpv..."
    ./rebuild "-j$(nproc)"

    log_info "Installing compiled mpv..."
    sudo "${VS_VENV}/bin/meson" install -C mpv/build

    log_info "Setting up jemalloc and VapourSynth python env wrapper for mpv..."
    if [[ -f "/usr/local/bin/mpv" ]]; then
        sudo mv /usr/local/bin/mpv /usr/local/bin/mpv-bin
    fi
    
    local vs_python_site_packages
    vs_python_site_packages=$(ls -d /opt/vapoursynth-venv/lib/python*/site-packages | head -n 1)
    
    sudo tee /usr/local/bin/mpv > /dev/null << EOF
#!/bin/bash
export LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2
export PYTHONPATH=${vs_python_site_packages}:\${PYTHONPATH:-}
export VSSCRIPT_PATH=${vs_python_site_packages}/vapoursynth/libvsscript.so
exec /usr/local/bin/mpv-bin "\$@"
EOF
    sudo chmod +x /usr/local/bin/mpv

    log_info "Installing compiled FFmpeg..."
    sudo make -C ffmpeg_build install

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
    setup_python_venv
    build_zimg
    build_vapoursynth
    install_vs_plugins
    build_mpv
    finalize_installation
}

main "$@"
