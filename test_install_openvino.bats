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

@test "Script creates a safe temporary directory" {
    run grep -q "mktemp -d" "$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "Script implements SHA256 checksum verification for security" {
    run grep -q "sha256sum" "$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "Script installs vs-mlrt to the VapourSynth plugin directory" {
    run grep -q "/usr/local/lib/vapoursynth" "$SCRIPT"
    [ "$status" -eq 0 ]
}
