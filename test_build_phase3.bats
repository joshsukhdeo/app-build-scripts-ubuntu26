#!/usr/bin/env bats

setup() {
    export SCRIPT="build_mpv_vapoursynth.sh"
}

@test "Phase 3 - MPV configuration sets -Db_pgo=generate initially" {
    run grep -q "\-Db_pgo=generate" "$SCRIPT"
    if [ "$status" -ne 0 ]; then
        echo "Missing -Db_pgo=generate in mpv_options"
        return 1
    fi
}

@test "Phase 3 - Script executes headless mpv on dummy.mp4 to generate profiling data" {
    run grep -q "mpv/build/mpv.*dummy.mp4" "$SCRIPT"
    if [ "$status" -ne 0 ]; then
        echo "Missing headless PGO execution step"
        return 1
    fi
}

@test "Phase 3 - Script mutates mpv_options to -Db_pgo=use" {
    run grep -q "sed.*-Db_pgo=use" "$SCRIPT"
    if [ "$status" -ne 0 ]; then
        echo "Missing sed replacement to -Db_pgo=use"
        return 1
    fi
}

@test "Phase 3 - Script recompiles mpv with build-mpv (Pass 2)" {
    run grep -q "\./build-mpv" "$SCRIPT"
    if [ "$status" -ne 0 ]; then
        echo "Missing ./build-mpv execution for PGO Pass 2"
        return 1
    fi
}
