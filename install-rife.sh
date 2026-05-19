#!/bin/bash
set -e

echo "=== RIFE (NCNN Vulkan) Final Source Build Script ==="

# --- 1. Dependencies ---
echo "Step 1: Checking build tools..."
sudo apt-get install -y libvulkan-dev glslang-tools vulkan-tools cmake g++ git

# --- 2. Build NCNN (Skip if already built) ---
cd ~/builds
if [ ! -d "ncnn" ]; then
    echo "Step 2: Building NCNN library..."
    git clone https://github.com/Tencent/ncnn.git
    cd ncnn
    git submodule update --init
    mkdir -p build && cd build
    cmake -DNCNN_VULKAN=ON -DNCNN_BUILD_EXAMPLES=OFF ..
    make -j$(nproc)
    sudo make install
    cd ~/builds
else
    echo "--> NCNN already exists, skipping to RIFE."
fi

# --- 3. Build RIFE Plugin (styler00dollar fork) ---
echo "Step 3: Preparing RIFE source from styler00dollar fork..."
if [ ! -d "VapourSynth-RIFE-ncnn-Vulkan" ]; then
    git clone https://github.com/styler00dollar/VapourSynth-RIFE-ncnn-Vulkan.git
fi
cd VapourSynth-RIFE-ncnn-Vulkan
# Ensure the submodules (like ncnn headers) are present
git submodule update --init --recursive

echo "Step 4: Compiling RIFE Plugin..."
# Point to your custom VapourSynth R73 build
export PKG_CONFIG_PATH="/usr/local/lib/x86_64-linux-gnu/pkgconfig:/usr/local/lib/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:$PKG_CONFIG_PATH"

rm -rf build
meson setup build --buildtype=release
meson compile -C build

# --- 4. Install ---
echo "Step 5: Installing to system..."
sudo mkdir -p /usr/local/lib/vapoursynth
sudo cp build/librife.so /usr/local/lib/vapoursynth/

# --- 5. Fetch Models ---
# The styler00dollar repo usually has models in the models/ folder already.
# If not, we'll download the standard RIFE ensemble.
if [ ! -d "models" ] || [ -z "$(ls -A models)" ]; then
    echo "Step 6: Downloading AI Models..."
    wget -q --show-progress "https://github.com/HomeOfVapourSynthEvolution/VapourSynth-RIFE-ncnn-Vulkan/archive/refs/tags/r8.zip" -O models_temp.zip
    unzip -q models_temp.zip
    mkdir -p models
    cp -r VapourSynth-RIFE-ncnn-Vulkan-r8/models/* ./models/
    rm -rf VapourSynth-RIFE-ncnn-Vulkan-r8 models_temp.zip
fi
sudo cp -r models /usr/local/lib/vapoursynth/

sudo ldconfig
echo "------------------------------------------------"
echo "Success! RIFE is now native to your system, senpai."
