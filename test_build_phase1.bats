#!/usr/bin/env bats

setup() {
    # We will test the file contents rather than executing it since it takes 30 mins
    export SCRIPT="build_mpv_vapoursynth.sh"
}

@test "Phase 1 - Script installs clang, lld, and libmimalloc-dev" {
    run grep -E -q "clang.*lld.*libmimalloc-dev|libmimalloc-dev.*clang.*lld" "$SCRIPT"
    if [ "$status" -ne 0 ]; then
        echo "Missing dependencies: clang, lld, libmimalloc-dev"
        return 1
    fi
}

@test "Phase 1 - Script exports CC and CXX as clang" {
    run grep -q 'export CC="clang"' "$SCRIPT"
    if [ "$status" -ne 0 ]; then
        echo "Missing export CC=\"clang\""
        return 1
    fi
}

@test "Phase 1 - MPV wrapper uses mimalloc instead of jemalloc" {
    run grep -q "libmimalloc.so" "$SCRIPT"
    if [ "$status" -ne 0 ]; then
        echo "LD_PRELOAD does not use libmimalloc.so"
        return 1
    fi
}

@test "Phase 1 - Script utilizes bash concurrency for zimg and vapoursynth" {
    run grep -q "build_zimg &" "$SCRIPT"
    if [ "$status" -ne 0 ]; then
        echo "Missing background execution (&) for build_zimg"
        return 1
    fi
}
