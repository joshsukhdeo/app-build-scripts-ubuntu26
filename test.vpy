import vapoursynth as vs
core = vs.core
clip = core.std.BlankClip(format=vs.YUV420P8, width=1280, height=720, length=100)
clip.set_output()
