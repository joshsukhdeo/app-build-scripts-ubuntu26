#!/usr/bin/env bats

@test "vsmlrt.py is installed in vapoursynth-venv" {
    [ -f "/opt/vapoursynth-venv/lib/python3.14/site-packages/vsmlrt.py" ]
}

@test "OpenVINO plugin libvsov.so is installed" {
    [ -f "/usr/local/lib/vapoursynth/libvsov.so" ]
}

@test "RIFE ONNX models are installed" {
    [ -f "/usr/local/lib/vapoursynth/models/rife_v2/rife_v4.12_lite.onnx" ] || [ -f "/usr/local/lib/vapoursynth/models/rife/rife_v4.12_lite.onnx" ]
}

@test "vspipe successfully executes test_vsmlrt.vpy with OpenVINO backend" {
    # Check if vspipe exists
    if ! command -v /opt/vapoursynth-venv/bin/vspipe >/dev/null; then
        skip "vspipe not found in /opt/vapoursynth-venv/bin/"
    fi
    
    run /opt/vapoursynth-venv/bin/vspipe -p test_vsmlrt.vpy .
    [ "$status" -eq 0 ]
    [[ "$output" == *"[TEST] vsmlrt.RIFE initialized successfully!"* ]]
}
