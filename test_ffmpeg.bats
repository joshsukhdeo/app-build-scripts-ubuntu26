#!/usr/bin/env bats

@test "ffmpeg is accessible on PATH" {
    run command -v ffmpeg
    [ "$status" -eq 0 ]
}

@test "vapoursynth is accessible on PATH" {
    run command -v vspipe
    [ "$status" -eq 0 ]
}

@test "mpv is accessible on PATH" {
    run command -v mpv
    [ "$status" -eq 0 ]
}

@test "ffmpeg has vaapi hardware acceleration (Intel)" {
    run bash -c "ffmpeg -hwaccels | grep -i vaapi"
    [ "$status" -eq 0 ]
}

@test "ffmpeg does NOT have nvidia hardware acceleration" {
    run bash -c "ffmpeg -hwaccels | grep -i cuda"
    [ "$status" -eq 1 ]
}

@test "ffmpeg does NOT have amf hardware acceleration" {
    run bash -c "ffmpeg -encoders | grep -i amf"
    [ "$status" -eq 1 ]
}

@test "yt-dlp is accessible on PATH" {
    run command -v yt-dlp
    [ "$status" -eq 0 ]
}

@test "VapourSynth python module can be imported" {
    run /opt/vapoursynth-venv/bin/python -c "import vapoursynth"
    [ "$status" -eq 0 ]
}

@test "Dummy packages for mpv, ffmpeg, vapoursynth are installed" {
    run bash -c "dpkg -l | grep -E 'mpv|ffmpeg|vapoursynth' | grep -i custom"
    [ "$status" -eq 0 ]
}

@test "ffmpeg supports necessary demuxers" {
    run bash -c "ffmpeg -demuxers | grep -i vapoursynth"
    [ "$status" -eq 0 ]
}

@test "havsfunc can be imported" {
    run /opt/vapoursynth-venv/bin/python -c "import havsfunc"
    [ "$status" -eq 0 ]
}

@test "mvsfunc can be imported" {
    run /opt/vapoursynth-venv/bin/python -c "import mvsfunc"
    [ "$status" -eq 0 ]
}

@test "zsmooth plugin is loaded in VapourSynth" {
    run /opt/vapoursynth-venv/bin/python -c "import vapoursynth as vs; assert hasattr(vs.core, 'zsmooth')"
    [ "$status" -eq 0 ]
}
