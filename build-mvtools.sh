#!/bin/bash
set -e

# --- Parse Command Line Switches ---
REBUILD=0

for arg in "$@"; do
    case $arg in
        -rebuild) REBUILD=1 ;;
        *) echo "Unknown argument: $arg. Ignoring." ;;
    esac
done

echo "=== MVTools Build Configuration ==="
echo "Force Rebuild : $REBUILD"
echo "==================================="

# --- 1. Install Missing Dependencies ---
echo "Step 1: Installing system dependencies (FFTW3 & NASM)..."
sudo apt-get update
sudo apt-get install -y libfftw3-dev nasm git meson ninja-build pkg-config

# --- 2. Clone or Update Repository ---
echo "Step 2: Preparing MVTools repository..."
if [ ! -d "vapoursynth-mvtools" ]; then
    git clone https://github.com/dubhater/vapoursynth-mvtools.git
    cd vapoursynth-mvtools
else
    cd vapoursynth-mvtools
    git pull
fi

# CRITICAL: Fetch the nested VapourSynth headers required for API v4 / R73+
echo "--> Syncing git submodules..."
git submodule update --init

# --- 3. Clean Build Cache ---
if [ "$REBUILD" -eq 1 ] && [ -d "build" ]; then
    echo "--> -rebuild detected: Purging old Meson cache..."
    rm -rf build
elif [ -d "build" ] && [ ! -f "build/build.ninja" ]; then
    # Auto-nuke the build folder if a previous setup crashed (like the fftw3f error)
    echo "--> Broken build cache detected. Purging..."
    rm -rf build
fi

# --- 4. Expose VapourSynth to pkg-config ---
echo "Step 3: Configuring linker paths..."
export PKG_CONFIG_PATH="/usr/local/lib/x86_64-linux-gnu/pkgconfig:/usr/local/lib/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:$PKG_CONFIG_PATH"

# --- 5. Compile and Install ---
echo "Step 4: Compiling MVTools..."
if [ -d "build" ]; then
    meson setup build --reconfigure --buildtype=release
else
    meson setup build --buildtype=release
fi

meson compile -C build
sudo meson install -C build

# --- 6. Refresh Linker Cache ---
echo "Step 5: Registering library with system linker..."
sudo ldconfig

echo "------------------------------------------------"
echo "Success, master! MVTools is now installed."
echo "You can now use core.mv.* functions in your VapourSynth scripts."