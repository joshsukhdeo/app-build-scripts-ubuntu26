#!/usr/bin/env bats

setup() {
    export SCRIPT="build_mpv_vapoursynth.sh"
}

@test "Phase 2 - FFmpeg disables unused components (encoders, muxers, programs)" {
    run grep -q -- "--disable-encoders" "$SCRIPT"
    if [ "$status" -ne 0 ]; then
        echo "Missing --disable-encoders"
        return 1
    fi
    
    run grep -q -- "--disable-muxers" "$SCRIPT"
    if [ "$status" -ne 0 ]; then
        echo "Missing --disable-muxers"
        return 1
    fi

    run grep -q -- "--disable-programs" "$SCRIPT"
    if [ "$status" -eq 0 ]; then
        echo "Error: --disable-programs is present! skiptosilence.lua and dynamic-crop.lua need ffprobe!"
        return 1
    fi
}
