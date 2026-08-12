#!/usr/bin/env bash
#
# C++ Source Compilation Installer for vs-mlrt (OpenVINO Backend)
# Adheres to Bash Pro and Performance Engineering standards.

set -Eeuo pipefail
shopt -s inherit_errexit 2>/dev/null || true

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
readonly VS_VENV="/opt/vapoursynth-venv"
readonly TMP_DIR=$(mktemp -d)
readonly VS_MLRT_REPO="https://github.com/AmusementClub/vs-mlrt.git"
readonly PLUGIN_DIR="/usr/local/lib/vapoursynth"

# shellcheck source=utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

script_cleanup() {
    rm -rf "${TMP_DIR}"
    cleanup # Call the generic cleanup from utils.sh
}
trap script_cleanup EXIT ERR
main() {
    log_info "Preparing vs-mlrt source compilation..."
    
    log_info "Installing build dependencies (cmake, ninja-build, onnx, protobuf, stdc++)..."
    sudo apt-get update
    sudo apt-get install -y build-essential cmake ninja-build git libonnx-dev libprotobuf-dev p7zip-full
    
    log_info "Installing OpenVINO C++ runtime via pip..."
    sudo "${VS_VENV}/bin/python" -m pip install --upgrade openvino
    
    log_info "Dynamically locating OpenVINO CMake config..."
    # We find the directory containing OpenVINOConfig.cmake
    OV_CMAKE_DIR=$(find "${VS_VENV}" -type f -name "OpenVINOConfig.cmake" | head -n 1 | xargs dirname)
    
    if [[ -z "${OV_CMAKE_DIR}" ]]; then
        log_err "Failed to locate OpenVINOConfig.cmake in ${VS_VENV}!"
        exit 1
    fi
    log_info "Found OpenVINO CMake dir at: ${OV_CMAKE_DIR}"
    
    cd "${TMP_DIR}"
    
    log_info "Cloning vs-mlrt repository recursively..."
    git clone --recursive "${VS_MLRT_REPO}" vs-mlrt
    cd vs-mlrt/vsov
    
    log_info "Patching CMakeLists.txt for Ubuntu Protobuf compatibility..."
    # Ubuntu's libprotobuf-dev does not provide a CONFIG file, we must use the standard FindProtobuf module
    sed -i 's/find_package(protobuf REQUIRED CONFIG)/find_package(Protobuf REQUIRED)/' CMakeLists.txt
    
    log_info "Configuring CMake build for OpenVINO..."
    mkdir build && cd build
    
    # We let CMake default to GCC (via build-essential) to guarantee C++ ABI compatibility 
    # with the pre-compiled Intel OpenVINO runtime libraries.
    
    cmake -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DVAPOURSYNTH_INCLUDE_DIRECTORY=/usr/local/include/vapoursynth \
        -DOpenVINO_DIR="${OV_CMAKE_DIR}" \
        ..
        
    log_info "Compiling with Ninja..."
    ninja
    
    log_info "Installing to VapourSynth plugin directory..."
    sudo mkdir -p "${PLUGIN_DIR}"
    sudo cp -a *.so "${PLUGIN_DIR}/"
    
    log_info "Installing vsmlrt python wrapper..."
    if command -v gh >/dev/null 2>&1; then
        gh api -H "Accept: application/vnd.github.v3.raw" /repos/AmusementClub/vs-mlrt/contents/scripts/vsmlrt.py > "${TMP_DIR}/vsmlrt.py"
        sudo mv "${TMP_DIR}/vsmlrt.py" "${VS_VENV}/lib/python3.14/site-packages/vsmlrt.py"
    else
        sudo curl -sL "https://raw.githubusercontent.com/AmusementClub/vs-mlrt/master/scripts/vsmlrt.py" -o "${VS_VENV}/lib/python3.14/site-packages/vsmlrt.py"
    fi
    
    log_info "Downloading and installing OpenVINO ONNX RIFE models..."
    sudo mkdir -p "${PLUGIN_DIR}/models"
    if command -v gh >/dev/null 2>&1; then
        gh release download "external-models" -R "AmusementClub/vs-mlrt" -p "rife_v4.12_lite.7z" -D "${TMP_DIR}"
        sudo 7z x "${TMP_DIR}/rife_v4.12_lite.7z" -o"${PLUGIN_DIR}/models/" -y
    else
        curl -sL "https://github.com/AmusementClub/vs-mlrt/releases/download/external-models/rife_v4.12_lite.7z" -o "${TMP_DIR}/rife.7z"
        sudo 7z x "${TMP_DIR}/rife.7z" -o"${PLUGIN_DIR}/models/" -y
    fi
    
    log_info "Source compilation complete. The OpenVINO vs-mlrt plugin is securely installed!"
}

main
