#!/usr/bin/env bats

setup() {
    export SCRIPT="install_openvino_vsmlrt.sh"
}

@test "Script exists" {
    [ -f "$SCRIPT" ]
}

@test "Script uses strict mode (set -Eeuo pipefail)" {
    run grep -q "set -Eeuo pipefail" "$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "Script implements safe temporary directory" {
    run grep -q "mktemp -d" "$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "Script dynamically locates OpenVINOConfig.cmake from pip installation" {
    run grep -q "find.*OpenVINOConfig.cmake" "$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "Script compiles vs-mlrt with CMake and Ninja" {
    run grep -q "cmake -G Ninja" "$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "Script defines VapourSynth include directory for CMake" {
    run grep -q "VAPOURSYNTH_INCLUDE_DIRECTORY" "$SCRIPT"
    [ "$status" -eq 0 ]
}

