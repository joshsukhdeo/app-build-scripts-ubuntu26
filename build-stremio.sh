#!/bin/bash
set -euo pipefail

echo "=== Stremio Lunar Lake Native Build Script ==="
echo "Master, preparing to build Stremio with external MPV config support and Node.js backend..."

# --- Parse Command Line Switches ---
BUILD_V44=0
while [[ $# -gt 0 ]]; do
    case $1 in
        -v4.4) BUILD_V44=1; shift ;;
        *) echo "Unknown argument: $1. Ignoring."; shift ;;
    esac
done

if [ "$BUILD_V44" -eq 1 ]; then
    echo "Mode: Building Stremio v4.4 (Qt-based shell)..."
else
    echo "Mode: Building Stremio Native (Rust-based shell)..."
fi

# --- 1. Environment Setup ---
export PATH="$HOME/.cargo/bin:$PATH"

# We cast a wide net for the system Python paths because `sudo meson install` dumps 
# the VapourSynth libraries here, completely bypassing local user environments like mise.
SYS_PY_PATHS="/usr/local/lib/python3/dist-packages:/usr/local/lib/python3/site-packages:/usr/local/lib/python3.11/site-packages:/usr/local/lib/python3.11/dist-packages:/usr/local/lib/python3.12/site-packages:/usr/local/lib/python3.12/dist-packages:/usr/local/lib/python3.14/site-packages:/usr/local/lib/python3.14/dist-packages"
WRAPPER_PY_PATH=""
WRAPPER_LD_PATH=""

# Auto-detect existing VapourSynth build environment from build-mpv.sh
if [ -d "$HOME/builds/vs_build_venv" ]; then
    echo "--> Detected existing VapourSynth build virtualenv..."
    VENV_PATH="$HOME/builds/vs_build_venv"
    PY_VER=$("$VENV_PATH/bin/python" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    WRAPPER_PY_PATH="$VENV_PATH/lib/python$PY_VER/site-packages"
    WRAPPER_LD_PATH=$("$VENV_PATH/bin/python" -c "import sys; print(sys.base_prefix)")/lib
fi

echo "--> Pre-build cleanup: Killing active Stremio processes..."
pkill -9 -x stremio-bin || true
pkill -9 -x stremio || true
pkill -9 -f "node.*server\.js" || true

# Force pkg-config to use your custom mpv v0.41.0 build
# We include the internal build_libs path because mpv.pc depends on those .pc files
export PKG_CONFIG_PATH="/usr/local/lib/x86_64-linux-gnu/pkgconfig:/usr/local/lib/pkgconfig:$HOME/builds/mpv-build/build_libs/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

# Ensure the linker finds our custom libmpv during the build
export LIBRARY_PATH="/usr/local/lib/x86_64-linux-gnu:${LIBRARY_PATH:-}"
export LD_LIBRARY_PATH="/usr/local/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"

# --- 2. Install Build Dependencies ---
echo "Step 1: Installing dependencies..."
if [ "$BUILD_V44" -eq 1 ]; then
    # Dependencies for v4.4 (Qt) as per DEBIAN.md
    sudo apt-get update
    sudo apt-get install -y build-essential pkgconf g++ libssl-dev librsvg2-bin \
        qt5-qmake libqt5webview5-dev qtwebengine5-dev \
        qml-module-qtwebchannel qml-module-qt-labs-platform qml-module-qtwebengine \
        qml-module-qtquick-dialogs qml-module-qtquick-controls qtdeclarative5-dev \
        qml-module-qt-labs-settings qml-module-qt-labs-folderlistmodel nodejs git wget
else
    # Dependencies for Native (Rust)
    sudo apt-get update
    sudo apt-get install -y build-essential pkg-config libgtk-4-dev libadwaita-1-dev libwebkitgtk-6.0-dev gettext nodejs cmake git wget
fi

# --- 3. Clone Repository ---
if [ "$BUILD_V44" -eq 1 ]; then
    echo "Step 2: Cloning stremio-shell (v4.4)..."
    mkdir -p ~/builds
    cd ~/builds
    if [ ! -d "stremio-shell" ]; then
        git clone --recurse-submodules -j8 https://github.com/Stremio/stremio-shell.git
    fi
    cd stremio-shell
    git pull
    git submodule update --init --recursive
else
    echo "Step 2: Cloning stremio-linux-shell (Native)..."
    mkdir -p ~/builds
    cd ~/builds
    if [ ! -d "stremio-linux-shell" ]; then
        git clone --recurse-submodules https://github.com/Stremio/stremio-linux-shell.git
    fi
    cd stremio-linux-shell
    git pull
    git submodule update --init --recursive
fi

# --- 5. Fetch Backend ---
echo "Step 5: Downloading Official Node.js Backend..."
mkdir -p ~/.local/share/stremio
# Note: Using v4.4.168 as the stable backend for both shells
wget -q --show-progress "https://s3-eu-west-1.amazonaws.com/stremio-artifacts/four/v4.4.168/server.js" -O ~/.local/share/stremio/server.js
# Patch server.js to use our local mpv wrapper for external playback
sed -i "s|path: \[\"/usr/bin/mpv\"\]|path: [\"$HOME/.local/bin/mpv\", \"/usr/bin/mpv\"]|g" ~/.local/share/stremio/server.js

# --- 6. Build Process ---
if [ "$BUILD_V44" -eq 1 ]; then
    echo "Step 3: Building Stremio v4.4..."
    # Ensure main.cpp is clean before patching
    git checkout HEAD -- main.cpp
    # Explicitly enable HiDPI scaling on Linux in main.cpp
    sed -i 's/#ifndef Q_OS_LINUX/#if 1 \/\/ Enabled for Linux/g' main.cpp
    
    # Force rebuild by removing the old binary
    rm -f build/stremio
    
    # Generate Makefiles
    qmake
    # Compile
    make -f release.makefile -j"$(nproc)"
    
    # Prepare server in build directory as per instructions
    cp ~/.local/share/stremio/server.js ./build/server.js
    ln -sf "$(which node)" ./build/node
else
    echo "Step 3: Injecting MPV Config Support..."
    cat << 'EOF' > patch_mpv.py
import os
import re

for root, _, files in os.walk('src'):
    for file in files:
        if file.endswith('.rs'):
            filepath = os.path.join(root, file)
            with open(filepath, 'r') as f:
                content = f.read()
            
            orig = content
            
            # Pattern 1: Convert standard initialization to use closures
            content = content.replace('Mpv::new()', 'Mpv::with_initializer(|ctx| { ctx.set_property("config", "yes").ok(); })')
            content = content.replace('mpv::Mpv::new()', 'mpv::Mpv::with_initializer(|ctx| { ctx.set_property("config", "yes").ok(); })')
            
            # Pattern 2: Inject into existing closures
            content = re.sub(
                r'with_initializer\(\s*\|([^|]+)\|\s*\{', 
                r'with_initializer(|\1| { \1.set_property("config", "yes").ok(); ', 
                content
            )

            # Pattern 3: Fallback override
            # libmpv clients almost universally set "terminal" to "yes" to get logs. 
            # Replacing this string natively activates the config parser instead.
            content = content.replace('"terminal"', '"config"')
            
            if orig != content:
                with open(filepath, 'w') as f:
                    f.write(content)
                print(f"  -> Patched {file}")
EOF
    python3 patch_mpv.py

    echo "Step 4: Compiling with Lunar Lake optimizations..."
    export RUSTFLAGS="-C target-cpu=native -C opt-level=3"
    cargo build --release
fi

# --- 7. Isolate and Deploy ---
echo "Step 6: Deploying Stremio..."
mkdir -p ~/.local/bin
mkdir -p ~/.local/share/applications
mkdir -p ~/.local/share/stremio

if [ "$BUILD_V44" -eq 1 ]; then
    # v4.4 expects the binary, server.js, and node symlink in the same application directory
    cp build/stremio ~/.local/share/stremio/stremio-bin
    # v4.4 requires server.js and a 'node' symlink in the execution directory
    cp build/server.js ~/.local/share/stremio/server.js
    ln -sf "$(which node)" ~/.local/share/stremio/node
else
    cp target/release/stremio-linux-shell ~/.local/share/stremio/stremio-bin
fi

# Create wrapper script
cat << 'EOF' > ~/.local/bin/stremio
#!/bin/bash
# Wrapper to prioritize your custom VapourSynth-enabled libmpv
EOF

# Inject the paths into the wrapper safely
echo "export PYTHONPATH=\"$SYS_PY_PATHS:$WRAPPER_PY_PATH:\$PYTHONPATH\"" >> ~/.local/bin/stremio
echo "export LD_LIBRARY_PATH=\"/usr/local/lib/x86_64-linux-gnu:$WRAPPER_LD_PATH:\$LD_LIBRARY_PATH\"" >> ~/.local/bin/stremio

# Point to the Node.js backend and handle execution
if [ "$BUILD_V44" -eq 1 ]; then
    # Enable fractional scaling to prevent 200% snap on HiDPI displays
    echo 'export QT_AUTO_SCREEN_SCALE_FACTOR=1' >> ~/.local/bin/stremio
    echo 'export QT_ENABLE_HIGHDPI_SCALING=1' >> ~/.local/bin/stremio
    echo 'export QT_SCALE_FACTOR_ROUNDING_POLICY=PassThrough' >> ~/.local/bin/stremio
    echo 'export QT_QPA_PLATFORM=xcb' >> ~/.local/bin/stremio
    # Ensure server settings directory exists to prevent ENOENT crashes
    echo 'mkdir -p ~/.stremio-server' >> ~/.local/bin/stremio
    # We explicitly kill any hanging node servers to prevent EADDRINUSE
    echo 'pkill -9 -f "node.*server\.js" || true' >> ~/.local/bin/stremio
    echo 'exec ~/.local/share/stremio/stremio-bin "$@"' >> ~/.local/bin/stremio
else
    echo 'pkill -9 -f "node.*server\.js" || true' >> ~/.local/bin/stremio
    echo "export SERVER_PATH=\"$HOME/.local/share/stremio/server.js\"" >> ~/.local/bin/stremio
    echo 'exec ~/.local/share/stremio/stremio-bin "$@"' >> ~/.local/bin/stremio
fi
chmod +x ~/.local/bin/stremio

# Create Desktop Entry
cat << EOF > ~/.local/share/applications/stremio.desktop
[Desktop Entry]
Name=Stremio (Native)
Comment=Watch Video Content
Exec=$HOME/.local/bin/stremio
Terminal=false
Type=Application
Categories=Video;AudioVideo;
EOF
update-desktop-database ~/.local/share/applications/ || true

echo "------------------------------------------------"
echo "Success! Stremio is built and integrated with your custom MPV & Node.js backend."
echo "Any hardware decoders or VapourSynth filters in ~/.config/mpv/mpv.conf will now apply to your streams."