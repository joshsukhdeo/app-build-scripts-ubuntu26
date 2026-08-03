#!/bin/bash
set -e

# Hardware specific optimizations
export CFLAGS="-O3 -march=native -pipe"
export CXXFLAGS="-O3 -march=native -pipe"
echo "Updating packages and installing required dependencies..."
sudo apt-get update
sudo apt-get install -y git build-essential ninja-build python3-pip python3-dev \
    yasm nasm libtool autoconf automake cmake libfribidi-dev libfontconfig1-dev \
    libfreetype6-dev libharfbuzz-dev liblcms2-dev libx11-dev libxv-dev libvulkan-dev \
    libgl1-mesa-dev libegl1-mesa-dev libxkbcommon-dev libwayland-dev libxrandr-dev \
    python3-setuptools python3-wheel libzimg-dev libmujs-dev \
    luajit libluajit-5.1-dev libssl-dev libplacebo-dev libshaderc-dev libvulkan-dev \
    libass-dev libbluray-dev libdvdread-dev libdvdnav-dev libuchardet-dev \
    mediainfo lsof libqt5concurrent5 libqt5svg5 libqt5qml5

# Use a global persistent virtualenv for VapourSynth so mpv and CLI can share it
export VS_VENV="/opt/vapoursynth-venv"
echo "Setting up latest Python virtualenv with uv at $VS_VENV..."
sudo mkdir -p $VS_VENV
sudo chown -R $USER:$USER $VS_VENV
uv python install
if [ ! -d "$VS_VENV/bin" ]; then
    uv venv $VS_VENV
fi
source $VS_VENV/bin/activate
uv pip install meson ninja cython


# 0. Build zimg from source (VapourSynth R79+ requires newer zimg than apt provides)
echo "======================================"
echo "Step 0: Building and Installing zimg"
echo "======================================"
if [ ! -d "zimg" ]; then
    git clone --recursive https://github.com/sekrit-twc/zimg.git
fi
cd zimg
git fetch origin
git checkout master
git pull origin master
git submodule update --init --recursive
./autogen.sh
./configure
make -j$(nproc)
sudo make install
sudo ldconfig
cd ..

# 1. Build latest VapourSynth
echo "======================================"
echo "Step 1: Building and Installing VapourSynth"
echo "======================================"
if [ ! -d "vapoursynth" ]; then
    git clone https://github.com/vapoursynth/vapoursynth.git
fi
cd vapoursynth
# Ensure we are using the latest master branch
git fetch origin
git checkout master
git pull origin master

rm -rf build
meson setup build
meson compile -C build
sudo $(which meson) install -C build

# Find where vapoursynth installed its pkgconfig file (it now installs as a Python package)
VS_PKG_CONFIG=$(find /usr -name "vapoursynth.pc" 2>/dev/null | head -n 1)
if [ -n "$VS_PKG_CONFIG" ]; then
    export PKG_CONFIG_PATH="$(dirname "$VS_PKG_CONFIG"):$PKG_CONFIG_PATH"
    echo "Found vapoursynth pkgconfig at $(dirname "$VS_PKG_CONFIG")"
    
    # FFmpeg expects headers in <vapoursynth/VapourSynth4.h>
    VS_LIB_DIR=$(dirname "$VS_PKG_CONFIG")
    VS_LIB_DIR=$(dirname "$VS_LIB_DIR")
    VS_INCLUDE_DIR="$VS_LIB_DIR/include"
    
    # Copy headers to standard include path so FFmpeg can find them
    if [ -d "$VS_INCLUDE_DIR" ]; then
        sudo mkdir -p /usr/local/include/vapoursynth
        sudo cp -r "$VS_INCLUDE_DIR"/*.h /usr/local/include/vapoursynth/
    fi
    
    # Copy shared libraries to standard lib path
    sudo cp -a "$VS_LIB_DIR"/libvapoursynth*.so* /usr/local/lib/
    sudo ldconfig
    
    # Expose vapoursynth CLI commands
    sudo ln -sf "$VS_VENV/bin/vspipe" /usr/local/bin/vspipe
    
    # Create a user-friendly vapoursynth command that runs Python with the venv
    sudo tee /usr/local/bin/vapoursynth > /dev/null << 'EOF'
#!/bin/bash
if [ $# -eq 0 ] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    echo "VapourSynth CLI Wrapper"
    echo "Usage: vapoursynth <script.vpy> [options...]"
    echo ""
    echo "This wrapper executes VapourSynth scripts using the configured Python environment."
    echo "To enter an interactive Python REPL with VapourSynth loaded, use:"
    echo "  vapoursynth --repl"
    exit 0
fi

if [[ "$1" == "--repl" ]]; then
    shift
    exec /opt/vapoursynth-venv/bin/python "$@"
fi

exec /opt/vapoursynth-venv/bin/python "$@"
EOF
    sudo chmod +x /usr/local/bin/vapoursynth
else
    echo "WARNING: Could not find vapoursynth.pc"
fi
cd ..

# 1.5 Install zsmooth and essential VapourSynth plugins for stability and performance
echo "======================================"
echo "Step 1.5: Installing zsmooth and essential VapourSynth plugins"
echo "======================================"
# Re-activate virtualenv just in case
source $VS_VENV/bin/activate
uv pip install vsutil vstools vskernels havsfunc psutil numpy scipy numexpr orjson
uv pip install git+https://github.com/adworacz/zsmooth.git
uv pip install git+https://github.com/HomeOfVapourSynthEvolution/mvsfunc.git
uv pip install git+https://github.com/dubhater/vapoursynth-adjust.git

# 2. Build mpv using mpv-build
echo "======================================"
echo "Step 2: Building mpv with mpv-build"
echo "======================================"
if [ ! -d "mpv-build" ]; then
    git clone https://github.com/mpv-player/mpv-build.git
fi
cd mpv-build

# Clean any previous builds to ensure options are applied cleanly
./clean

# Configure FFmpeg to enable VapourSynth support (needed for demuxing .vpy scripts)
echo "Configuring FFmpeg options..."
echo "--enable-vapoursynth" > ffmpeg_options
echo "--enable-libzimg" >> ffmpeg_options
# Disable CUDA to prevent CUDA errors on non-Nvidia GPUs
echo "--disable-cuda-llvm" >> ffmpeg_options
echo "--disable-cuvid" >> ffmpeg_options
echo "--disable-nvdec" >> ffmpeg_options
echo "--disable-nvenc" >> ffmpeg_options
# Enable Intel VAAPI for Arc GPU
echo "--enable-vaapi" >> ffmpeg_options
echo "--extra-cflags=-O3 -march=native -pipe" >> ffmpeg_options
echo "--extra-cxxflags=-O3 -march=native -pipe" >> ffmpeg_options

# Configure mpv options
echo "Configuring mpv options..."
# Enable LuaJIT specifically
echo "-Dlua=luajit" > mpv_options
# Enable JavaScript (MuJS)
echo "-Djavascript=enabled" >> mpv_options
# Enable VapourSynth video filter support
echo "-Dvapoursynth=enabled" >> mpv_options
# Hardware optimizations
echo "-Doptimization=3" >> mpv_options
echo "-Db_lto=true" >> mpv_options
echo "-Dc_args=-march=native" >> mpv_options
echo "-Dcpp_args=-march=native" >> mpv_options

echo "Running rebuild to compile FFmpeg and mpv..."
./rebuild -j$(nproc)

echo "Installing compiled mpv..."
sudo $VS_VENV/bin/meson install -C mpv/build

echo "Setting up jemalloc and VapourSynth python env wrapper for mpv..."
sudo mv /usr/local/bin/mpv /usr/local/bin/mpv-bin
VS_PYTHON_SITE_PACKAGES=$(ls -d /opt/vapoursynth-venv/lib/python*/site-packages | head -n 1)
sudo tee /usr/local/bin/mpv > /dev/null << EOF
#!/bin/bash
export LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2
# Ensure VapourSynth loads plugins from the system-wide venv
export PYTHONPATH=${VS_PYTHON_SITE_PACKAGES}:\$PYTHONPATH
export VSSCRIPT_PATH=${VS_PYTHON_SITE_PACKAGES}/vapoursynth/libvsscript.so
exec /usr/local/bin/mpv-bin "\$@"
EOF
sudo chmod +x /usr/local/bin/mpv

echo "Installing compiled FFmpeg..."
sudo make -C ffmpeg_build install

echo "======================================"
echo "Build and installation complete!"
echo "You can verify the VapourSynth filter is available by running:"
echo "mpv --vf=help | grep vapoursynth"
echo "======================================"
