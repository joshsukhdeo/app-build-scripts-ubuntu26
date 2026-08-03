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

# Use uv python 3.12 for VapourSynth
echo "Setting up Python 3.12 virtualenv with uv..."
uv python install 3.12
uv venv --python 3.12 .venv
source .venv/bin/activate
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
else
    echo "WARNING: Could not find vapoursynth.pc"
fi
cd ..

# 1.5 Install zsmooth and essential VapourSynth plugins for stability and performance
echo "======================================"
echo "Step 1.5: Installing zsmooth and essential VapourSynth plugins"
echo "======================================"
# Re-activate virtualenv just in case
source .venv/bin/activate
uv pip install vsutil vstools vskernels havsfunc mvsfunc
uv pip install git+https://github.com/adworacz/zsmooth.git

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
sudo ../.venv/bin/meson install -C mpv/build

echo "Setting up jemalloc wrapper for mpv..."
sudo mv /usr/local/bin/mpv /usr/local/bin/mpv-bin
sudo bash -c 'cat << EOF > /usr/local/bin/mpv
#!/bin/bash
export LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2
exec /usr/local/bin/mpv-bin "\$@"
EOF'
sudo chmod +x /usr/local/bin/mpv

echo "Installing compiled FFmpeg..."
sudo make -C ffmpeg_build install

echo "======================================"
echo "Build and installation complete!"
echo "You can verify the VapourSynth filter is available by running:"
echo "mpv --vf=help | grep vapoursynth"
echo "======================================"
