#!/usr/bin/env bash

# utils.sh
# Common utility functions for build scripts

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
