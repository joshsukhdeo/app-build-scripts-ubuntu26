import vapoursynth as vs
import psutil
import zsmooth
import mvsfunc
import sys

core = vs.core

print(f"[TEST] Python version: {sys.version}")
print(f"[TEST] psutil version: {psutil.__version__}")
print(f"[TEST] Plugins loaded: {[p.namespace for p in core.plugins()]}")

clip = video_in
# Just doing a trivial passthrough or blank
clip.set_output()
