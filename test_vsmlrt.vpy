import sys
import vapoursynth as vs

core = vs.core
# Explicitly load the OpenVINO plugin before importing vsmlrt
core.std.LoadPlugin("/usr/local/lib/vapoursynth/libvsov.so")

import vsmlrt

print(f"[TEST] Python version: {sys.version}", file=sys.stderr)
print("[TEST] vsmlrt module imported successfully", file=sys.stderr)
print(f"[TEST] OpenVINO CPU Backend available: {vsmlrt.Backend.OV_CPU}", file=sys.stderr)

# Create a blank clip and test if RIFE can be instantiated
# RIFE via vsmlrt requires RGBS format
clip = core.std.BlankClip(width=1920, height=1088, format=vs.RGBS, length=10)

# Instantiate RIFE using the OpenVINO CPU backend
try:
    clip = vsmlrt.RIFE(clip, model=vsmlrt.RIFEModel.v4_12_lite, 
                       multi=2, scale=1.0, 
                       backend=vsmlrt.Backend.OV_CPU(fp16=False))
    print("[TEST] vsmlrt.RIFE initialized successfully!", file=sys.stderr)
    clip.set_output()
except Exception as e:
    print(f"[TEST] vsmlrt.RIFE initialization failed: {e}", file=sys.stderr)
    sys.exit(1)
