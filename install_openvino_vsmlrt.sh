#!/usr/bin/env bash
#
# Secure Installer for vs-mlrt and OpenVINO Backend
# Adheres to Bash Pro and Performance Engineering standards.

set -Eeuo pipefail
shopt -s inherit_errexit 2>/dev/null || true

# --- Configuration ---
readonly VS_MLRT_URL="https://github.com/AmusementClub/vs-mlrt/releases/download/v14/vsmacros-v14-linux-x64.zip" # Replace with exact URL
readonly EXPECTED_SHA256="UPDATE_ME" # Replace with exact SHA256 sum for the zip
readonly PLUGIN_DIR="/usr/local/lib/vapoursynth"
readonly VS_VENV="/opt/vapoursynth-venv"

log_info() { printf "[INFO] %s\n" "$*"; }
log_err() { printf "[ERROR] %s\n" "$*" >&2; }

# Safe temp handling
TMP_DIR=$(mktemp -d)
cleanup() {
    local exit_code=$?
    rm -rf "${TMP_DIR}"
    if [ ${exit_code} -ne 0 ]; then
        log_err "Script failed with exit code ${exit_code}"
    fi
    exit ${exit_code}
}
trap cleanup EXIT ERR

main() {
    log_info "Setting up secure OpenVINO + vs-mlrt installation..."
    
    if [[ "${EXPECTED_SHA256}" == "UPDATE_ME" ]]; then
        log_err "SECURITY STOP: Please update the EXPECTED_SHA256 constant in this script with the correct checksum to prevent supply-chain attacks."
        exit 1
    fi
    
    cd "${TMP_DIR}"
    
    log_info "Downloading vs-mlrt..."
    curl -sSL "${VS_MLRT_URL}" -o vs-mlrt.zip
    
    log_info "Verifying SHA256 checksum..."
    echo "${EXPECTED_SHA256}  vs-mlrt.zip" | sha256sum -c - || {
        log_err "Checksum verification failed! Supply chain compromise or corrupted download."
        exit 1
    }
    
    log_info "Extracting plugin..."
    unzip -q vs-mlrt.zip
    
    log_info "Installing to VapourSynth plugin directory..."
    sudo mkdir -p "${PLUGIN_DIR}"
    sudo cp -a *.so "${PLUGIN_DIR}/"
    
    log_info "Installing OpenVINO runtime via python pip into VapourSynth VENV..."
    # The python openvino package provides the massive runtime libraries securely and natively
    sudo "${VS_VENV}/bin/python" -m pip install --upgrade openvino
    
    log_info "Installation complete."
}

main
