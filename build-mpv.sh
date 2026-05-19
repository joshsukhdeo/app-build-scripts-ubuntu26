#!/bin/bash
set -euo pipefail

# --- Parse Command Line Switches ---
STABLE_BUILD=0
USE_MISE_PYTHON=0
USE_UV_PYTHON=0
UV_PYTHON_VER=""
USE_SVP_PYTHON=0
INSTALL_SVP_PREREQS=0
VS_R73=0
REBUILD_VS=0

while [[ $# -gt 0 ]]; do
    case $1 in
        -Stable) STABLE_BUILD=1; shift ;;
        -useMisePython) USE_MISE_PYTHON=1; shift ;;
        -uvPython) USE_UV_PYTHON=1; UV_PYTHON_VER="$2"; shift 2 ;;
        -useSvpPython) USE_SVP_PYTHON=1; shift ;;
        -svp) INSTALL_SVP_PREREQS=1; shift ;;
        -vapoursynthR73) VS_R73=1; shift ;;
        -rebuildVS) REBUILD_VS=1; shift ;;
        *) echo "Unknown argument: $1. Ignoring."; shift ;;
    esac
done

echo "=== Build Configuration ==="
echo "Stable Compiler Flags : $STABLE_BUILD"
echo "Use Mise Python       : $USE_MISE_PYTHON"
echo "Use uv Python         : $USE_UV_PYTHON ($UV_PYTHON_VER)"
echo "Use SVP Python        : $USE_SVP_PYTHON"
echo "Install SVP Prereqs   : $INSTALL_SVP_PREREQS"
echo "VapourSynth R73       : $VS_R73"
echo "Force Rebuild VS      : $REBUILD_VS"
echo "==========================="

# --- 0. Environment Setup ---
# We cast a wide net for the system Python paths because `sudo meson install` dumps 
# the VapourSynth libraries here, completely bypassing local user environments like mise.
SYS_PY_PATHS="/usr/local/lib/python3/dist-packages:/usr/local/lib/python3/site-packages:/usr/local/lib/python3.12/site-packages:/usr/local/lib/python3.12/dist-packages:/usr/local/lib/python3.11/site-packages:/usr/local/lib/python3.11/dist-packages:/usr/local/lib/python3.14/site-packages:/usr/local/lib/python3.14/dist-packages"
WRAPPER_PY_PATH=""
WRAPPER_LD_PATH=""

if [ "$INSTALL_SVP_PREREQS" -eq 1 ]; then
    echo "--> Installing SVP prerequisites..."
    sudo apt-get update || echo "Warning: apt-get update failed, attempting install anyway..."
    sudo apt-get install -y lsof libxcb-cursor0 openssl libssl-dev \
        vulkan-tools libvulkan-dev va-driver-all \
        mkvtoolnix qt6-base-dev libavcodec-dev libavformat-dev libswscale-dev \
        libva-dev libvdpau-dev git build-essential cmake meson ninja-build \
        pkg-config cython3 python3-dev python3-pip libzimg-dev nasm libnuma-dev \
        mesa-vdpau-drivers || echo "Warning: Some packages failed to install."
fi

if [ "$USE_UV_PYTHON" -eq 1 ]; then
    echo "--> Forcing Python $UV_PYTHON_VER via uv..."
    if ! command -v uv &> /dev/null; then
        echo "--> uv not found. Installing uv..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="$HOME/.cargo/bin:$PATH"
    fi
    
    echo "--> Ensuring Python $UV_PYTHON_VER is installed via uv..."
    uv python install "$UV_PYTHON_VER"
    
    # CRITICAL: Remove any local .venv that might confuse uv or meson
    if [ -d "$HOME/builds/.venv" ]; then
        echo "--> Removing conflicting local .venv in builds directory..."
        rm -rf "$HOME/builds/.venv"
    fi
    
    # Force uv to find the toolchain Python by bypassing project/venv detection
    # We use env -i to strip the environment completely for this check
    UV_PYTHON_BIN=$(env -i PATH="$PATH" HOME="$HOME" uv python find "$UV_PYTHON_VER" --python-preference managed)
    UV_BASE_PREFIX=$("$UV_PYTHON_BIN" -c "import sys; print(sys.base_prefix)")
    
    # Create a stable virtual environment for the build to avoid "externally managed environment" errors
    echo "--> Creating/Updating build virtualenv for Python $UV_PYTHON_VER..."
    uv venv "$HOME/builds/vs_build_venv" --python "$UV_PYTHON_VER" --seed --clear
    export VIRTUAL_ENV="$HOME/builds/vs_build_venv"
    export PATH="$VIRTUAL_ENV/bin:$PATH"
    
    UV_PY_BIN="$VIRTUAL_ENV/bin/python"
    
    echo "--> Installing cython and guessit in the virtualenv..."
    uv pip install cython guessit
    
    # Export environment variables for the build
    export PYTHON="$UV_PY_BIN"
    # Crucial: Add the toolchain's pkgconfig to resolve python-<ver>-embed
    export PKG_CONFIG_PATH="$UV_BASE_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
    export LDFLAGS="-L$UV_BASE_PREFIX/lib ${LDFLAGS:-}"
    export CPPFLAGS="-I$UV_BASE_PREFIX/include ${CPPFLAGS:-}"
    
    WRAPPER_PY_PATH="$VIRTUAL_ENV/lib/python$UV_PYTHON_VER/site-packages"
    WRAPPER_LD_PATH="$UV_BASE_PREFIX/lib"
    
    echo "--> Using virtualenv Python $UV_PYTHON_VER: $UV_PY_BIN"
    echo "--> Real uv Python prefix: $UV_BASE_PREFIX"
elif [ "$USE_SVP_PYTHON" -eq 1 ]; then
    echo "--> Forcing Python from SVP4 directory..."
    SVP_PY_BIN="$HOME/SVP4/python/python3.12"
    if [ ! -f "$SVP_PY_BIN" ]; then
        echo "ERROR: SVP Python binary not found at $SVP_PY_BIN"
        exit 1
    fi
    
    SVP_PY_PREFIX="$HOME/SVP4/python"
    
    export PYTHON="$SVP_PY_BIN"
    # Note: SVP bundled python lacks pkgconfig/headers, so core VS build might fail
    # unless using system headers. We set paths for the runtime wrapper primarily.
    export PKG_CONFIG_PATH="$SVP_PY_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
    export LDFLAGS="-L$SVP_PY_PREFIX/lib ${LDFLAGS:-}"
    export CPPFLAGS="-I$SVP_PY_PREFIX/include ${CPPFLAGS:-}"
    
    # Only include the bundled lib from the python directory
    WRAPPER_PY_PATH="$SVP_PY_PREFIX/lib"
    WRAPPER_LD_PATH="$SVP_PY_PREFIX"
    
    echo "--> Using SVP Python: $SVP_PY_BIN"
elif [ "$USE_MISE_PYTHON" -eq 0 ]; then
    echo "--> Forcing system Python (blinding mise)..."
    export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
    echo "--> Installing guessit in system environment..."
    python3 -m pip install guessit --user --break-system-packages || true
else
    echo "--> Attempting to use mise Python environment..."
    if command -v mise &> /dev/null; then
        MISE_PY_BIN=$(mise which python3 2>/dev/null || true)
        if [ -n "$MISE_PY_BIN" ]; then
            MISE_PY_PREFIX="$(dirname "$(dirname "$MISE_PY_BIN")")"
            MISE_PY_PKGCONFIG="$MISE_PY_PREFIX/lib/pkgconfig"
            
            # Extract Python version to target the correct site-packages
            MISE_PY_VER=$(mise exec -- python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
            
            if [ -d "$MISE_PY_PKGCONFIG" ]; then
                export PKG_CONFIG_PATH="$MISE_PY_PKGCONFIG:${PKG_CONFIG_PATH:-}"
                echo "--> Added $MISE_PY_PKGCONFIG to PKG_CONFIG_PATH"
            fi
            
            # Append the mise specific paths to the wrapper
            WRAPPER_PY_PATH="$MISE_PY_PREFIX/lib/python$MISE_PY_VER/site-packages"
            WRAPPER_LD_PATH="$MISE_PY_PREFIX/lib"

            echo "--> Installing guessit in mise environment..."
            "$MISE_PY_BIN" -m pip install guessit
        fi
    fi
fi

# Make apt non-interactive to prevent pausing during automated runs
export DEBIAN_FRONTEND=noninteractive

echo "--> Pre-build cleanup: Killing active mpv and VapourSynth processes..."
pkill -9 -x mpv-real || true
pkill -9 -x mpv || true
pkill -9 -x vspipe || true

echo "--> Pre-build cleanup: Removing conflicting system VapourSynth installations..."
sudo rm -rf /usr/local/lib/python3/dist-packages/vapoursynth
sudo rm -f /usr/local/lib/python3/dist-packages/vapoursynth.cpython-*-x86_64-linux-gnu.so
sudo ldconfig

# --- 1. Robust Repository Check ---
echo "Step 1: Verifying Repositories (Skipped to avoid sudo hangs)..."
# sudo apt-get update
# sudo apt-get install -y software-properties-common
# sudo add-apt-repository -y universe multiverse
# sudo apt-get update

# --- 2. Install Build Dependencies ---
echo "Step 2: Installing dependencies (Skipped to avoid sudo hangs)..."
# sudo apt-get install -y \
#     build-essential cmake meson ninja-build pkg-config git \
#     libssl-dev libfribidi-dev libharfbuzz-dev libluajit-5.1-dev \
#     libx264-dev libx265-dev xorg-dev libxpresent-dev libegl1-mesa-dev \
#     libfreetype-dev libfontconfig-dev libva-dev libdrm-dev libplacebo-dev \
#     libasound2-dev libpulse-dev lsof libxcb-cursor0 \
#     python3-dev python3-pip cython3 libzimg-dev nasm libnuma-dev \
#     intel-opencl-icd ocl-icd-opencl-dev \
#     libvulkan-dev vulkan-tools glslang-dev glslang-tools libshaderc-dev \
#     autoconf automake libtool libmujs-dev wayland-protocols libxkbcommon-dev \
#     librubberband-dev libdav1d-dev

# --- 3. Build VapourSynth Core & Script ---
echo "Step 3: Cloning and building VapourSynth..."
if [ ! -d "vapoursynth" ]; then
    git clone https://github.com/vapoursynth/vapoursynth.git
fi

if [ "$REBUILD_VS" -eq 1 ] && [ -d "vapoursynth/build" ]; then
    echo "--> -rebuildVS detected: Purging old VapourSynth build cache..."
    rm -rf vapoursynth/build
fi

cd vapoursynth

# Handle Checkout version
if [ "$VS_R73" -eq 1 ]; then
    echo "--> Checking out VapourSynth tag R73..."
    git fetch --tags
    git checkout R73
else
    echo "--> Using VapourSynth master branch..."
    git checkout master
    git pull || echo "Warning: git pull failed, using current master state."
fi

# Handle Compiler Flags with safe Bash Arrays
if [ "$STABLE_BUILD" -eq 1 ]; then
    echo "--> Using stable compiler defaults..."
    MESON_ARGS=(--buildtype=release)
else
    echo "--> Using bleeding-edge native optimizations..."
    export CFLAGS="-O3 -march=native -pipe"
    export CXXFLAGS="-O3 -march=native -pipe"
    MESON_ARGS=(--buildtype=release -Db_lto=true -Doptimization=3 -Dc_args="-march=native -O3 -pipe" -Dcpp_args="-march=native -O3 -pipe")
fi

if [ -d "build" ]; then
    meson setup build --reconfigure "${MESON_ARGS[@]}"
else
    meson setup build "${MESON_ARGS[@]}"
fi

meson compile -C build
sudo meson install -C build --no-rebuild
sudo ldconfig
cd ..

# --- 4. Expose VapourSynth to pkg-config ---
echo "Step 4: Configuring paths and verifying VapourSynth build..."

if [ "$VS_R73" -eq 1 ]; then
    export PKG_CONFIG_PATH="/usr/local/lib/x86_64-linux-gnu/pkgconfig:/usr/local/lib/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:${PKG_CONFIG_PATH:-}"
else
    VS_PC_PATH=$(find /usr/local/lib/python* -name "vapoursynth.pc" -print -quit 2>/dev/null || find /usr/lib/python* -name "vapoursynth.pc" -print -quit 2>/dev/null || true)
    
    if [ -n "$VS_PC_PATH" ]; then
        VS_PC_DIR=$(dirname "$VS_PC_PATH")
        VS_LIB_DIR=$(dirname "$VS_PC_DIR")
        
        if [ ! -f "$VS_PC_DIR/vapoursynth-script.pc" ]; then
            echo "--> Generating legacy vapoursynth-script.pc to satisfy mpv..."
            sudo cp "$VS_PC_PATH" "$VS_PC_DIR/vapoursynth-script.pc"
        fi
        
        export PKG_CONFIG_PATH="$VS_PC_DIR:/usr/local/lib/x86_64-linux-gnu/pkgconfig:/usr/local/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
        echo "$VS_LIB_DIR" | sudo tee /etc/ld.so.conf.d/vapoursynth-python.conf > /dev/null
        sudo ldconfig
    else
        echo "ERROR: Could not locate vapoursynth.pc in Python dist-packages. VapourSynth R74+ build failed."
        exit 1
    fi
fi

# --- VERIFICATION BLOCK ---
echo "--> Current PKG_CONFIG_PATH: $PKG_CONFIG_PATH"
echo "--> Verifying VapourSynth pkg-config accessibility..."

# Verify core vapoursynth
if pkg-config --exists vapoursynth; then
    echo "  [OK] vapoursynth core found (Version: $(pkg-config --modversion vapoursynth))"
else
    echo "  [ERROR] pkg-config cannot find vapoursynth. The core build or installation failed."
    exit 1
fi

# Verify vapoursynth-script based on version switch
if [ "$VS_R73" -eq 1 ]; then
    if pkg-config --exists vapoursynth-script; then
        echo "  [OK] vapoursynth-script found (R73 bridge successfully compiled)"
    else
        echo "  [ERROR] pkg-config cannot find vapoursynth-script.pc."
        echo "          The R73 Python bridge failed to compile. Ensure python3-dev headers match the active Python environment."
        exit 1
    fi
else
    if pkg-config --exists vapoursynth-script; then
        echo "  [OK] vapoursynth-script alias found (R74+ bridge workaround active)"
    else
        echo "  [ERROR] pkg-config cannot find the vapoursynth-script.pc alias. Workaround failed."
        exit 1
    fi
fi

# --- 5. Build mpv ---
echo "Step 5: Cloning and building mpv..."
if [ ! -d "mpv-build" ]; then
    git clone https://github.com/mpv-player/mpv-build.git
    cd mpv-build
else
    cd mpv-build
    git pull || echo "Warning: git pull failed, using current master state."
fi

if [ "$STABLE_BUILD" -eq 1 ]; then
    echo "--> Using stable releases for mpv and ffmpeg..."
    ./use-ffmpeg-release
    ./use-mpv-release
else
    echo "--> Using master branches for mpv and ffmpeg for maximum performance & latest features..."
    ./use-ffmpeg-master
    ./use-mpv-master
fi

cat << 'EOF' > ffmpeg_options
--enable-libx264
--enable-libx265
--enable-libdav1d
--enable-vaapi
--enable-vulkan
--enable-opencl
--enable-gpl
--enable-nonfree
EOF

if [ "$STABLE_BUILD" -eq 0 ]; then
    cat << 'EOF' >> ffmpeg_options
--extra-cflags=-O2
--extra-cxxflags=-O2
EOF
fi

if [ "$STABLE_BUILD" -eq 1 ]; then
    cat << 'EOF' > mpv_options
-Dvapoursynth=enabled
-Dlibmpv=true
-Dlua=enabled
-Djavascript=enabled
-Dvulkan=enabled
-Doptimization=2
-Db_lto=false
EOF
else
    cat << 'EOF' > mpv_options
-Dvapoursynth=enabled
-Dlibmpv=true
-Dlua=enabled
-Djavascript=enabled
-Dvulkan=enabled
-Doptimization=2
-Db_lto=false
EOF
fi

# Fix mpv VapourSynth crash where missing _MP_IMAGE causes mapGetData to abort
echo "--> Applying VapourSynth R74+ mapGetData crash fix to mpv..."
sed -i 's/mpi = (void \*)p->vsapi->mapGetData(map, "_MP_IMAGE", 0, NULL);/int err = 0; mpi = (void \*)p->vsapi->mapGetData(map, "_MP_IMAGE", 0, \&err);/' mpv/video/filter/vf_vapoursynth.c
sed -i 's/int num = p->vsapi->mapGetInt(map, "_DurationNum", 0, NULL);/int err1 = 0; int num = p->vsapi->mapGetInt(map, "_DurationNum", 0, \&err1);/' mpv/video/filter/vf_vapoursynth.c
sed -i 's/int den = p->vsapi->mapGetInt(map, "_DurationDen", 0, NULL);/int err2 = 0; int den = p->vsapi->mapGetInt(map, "_DurationDen", 0, \&err2);/' mpv/video/filter/vf_vapoursynth.c

./rebuild -j"$(nproc)"
sudo ./install
cp mpv/build/mpv ~/.local/bin/mpv-real

# --- 6. Security & Isolation Fixes (CLI Wrapper & Desktop Shortcut) ---
echo "Step 6: Deploying secure isolation wrappers..."

mkdir -p ~/.local/bin
mkdir -p ~/.local/share/applications

# Generate the wrapper with high-isolation to bypass shell environment corruption
cat << 'EOF' > ~/.local/bin/mpv
#!/bin/bash
# High-isolation environment for mpv + VapourSynth + SVP
# Clear shell-specific Python variables that conflict with our build
unset PYTHONPATH
unset PYTHONHOME
unset PYTHONNOUSERSITE
unset MISE_SHELL

EOF

# Inject the paths into the wrapper safely
# Force a clean system PATH + our virtualenv
echo "export PATH=\"$VIRTUAL_ENV/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin\"" >> ~/.local/bin/mpv

# Inject standard library and site-packages locations
echo "export LD_LIBRARY_PATH=\"$WRAPPER_LD_PATH:/usr/local/lib/x86_64-linux-gnu:/usr/local/lib:\$LD_LIBRARY_PATH\"" >> ~/.local/bin/mpv
if [ "$USE_UV_PYTHON" -eq 1 ]; then
    echo "export PYTHONHOME=\"$UV_BASE_PREFIX\"" >> ~/.local/bin/mpv
elif [ "$USE_SVP_PYTHON" -eq 1 ]; then
    echo "export PYTHONHOME=\"$SVP_PY_PREFIX\"" >> ~/.local/bin/mpv
fi

# Prioritize virtualenv site-packages and then the specific python3.12 system paths
echo "export PYTHONPATH=\"$WRAPPER_PY_PATH:$SYS_PY_PATHS\"" >> ~/.local/bin/mpv
echo "export PYTHONNOUSERSITE=1" >> ~/.local/bin/mpv

# Pass execution to the real binary
echo 'exec ~/.local/bin/mpv-real "$@"' >> ~/.local/bin/mpv
chmod +x ~/.local/bin/mpv

if [ "$USE_MISE_PYTHON" -eq 1 ] && [ -n "${MISE_PY_BIN:-}" ]; then
    echo "--> Running 'vapoursynth config' to initialize the python environment for VSScript..."
    # We must ensure the environment matches what the wrapper will use
    PYTHONPATH="$SYS_PY_PATHS:$WRAPPER_PY_PATH:${PYTHONPATH:-}" LD_LIBRARY_PATH="$WRAPPER_LD_PATH:${LD_LIBRARY_PATH:-}" "$MISE_PY_BIN" -m vapoursynth config || true
fi

# Fix the GUI shortcut to use our wrapper
if [ -f /usr/local/share/applications/mpv.desktop ]; then
    cp /usr/local/share/applications/mpv.desktop ~/.local/share/applications/
    sed -i "s|^Exec=mpv|Exec=$HOME/.local/bin/mpv|" ~/.local/share/applications/mpv.desktop
    # Update desktop database so the system registers the local override
    update-desktop-database ~/.local/share/applications/ || true
fi

echo "------------------------------------------------"
echo "Success! VapourSynth and mpv have been securely installed and isolated."
echo "Terminal usage: ~/.local/bin/mpv"
echo "GUI usage: Open file via file manager."