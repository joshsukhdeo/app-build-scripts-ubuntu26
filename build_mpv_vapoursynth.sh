#!/bin/bash
set -e

echo "Updating packages and installing required dependencies..."
sudo apt-get update
sudo apt-get install -y git build-essential meson ninja-build python3-pip python3-dev \
    yasm nasm libtool autoconf automake cmake libfribidi-dev libfontconfig1-dev \
    libfreetype6-dev libharfbuzz-dev liblcms2-dev libx11-dev libxv-dev libvulkan-dev \
    libgl1-mesa-dev libegl1-mesa-dev libxkbcommon-dev libwayland-dev libxrandr-dev \
    python3-setuptools python3-wheel cython3 libzimg-dev libmujs-dev \
    luajit libluajit-5.1-dev libssl-dev libplacebo-dev libshaderc-dev libvulkan-dev \
    libass-dev libbluray-dev libdvdread-dev libdvdnav-dev libuchardet-dev

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

./autogen.sh
./configure
make -j$(nproc)
sudo make install
# Update shared library cache so mpv/ffmpeg builds can find the newly installed libvapoursynth
sudo ldconfig
cd ..

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

# Configure mpv options
echo "Configuring mpv options..."
# Enable LuaJIT specifically
echo "-Dlua=luajit" > mpv_options
# Enable JavaScript (MuJS)
echo "-Djavascript=enabled" >> mpv_options
# Enable VapourSynth video filter support
echo "-Dvapoursynth=enabled" >> mpv_options

echo "Running rebuild to compile FFmpeg and mpv..."
./rebuild -j$(nproc)

echo "Installing compiled mpv..."
sudo ./install

echo "======================================"
echo "Build and installation complete!"
echo "You can verify the VapourSynth filter is available by running:"
echo "mpv --vf=help | grep vapoursynth"
echo "======================================"
