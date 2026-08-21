# app-build-scripts-ubuntu26

A collection of custom build scripts specifically tuned for Ubuntu.

## `build_mpv_vapoursynth.sh`

This script compiles a highly optimized, custom toolchain containing `mpv`, `ffmpeg`, and `VapourSynth`.

### Key Features
- **Dynamic Hardware Acceleration**: Automatically detects your hardware (`lspci`) and limits compilation strictly to the GPUs present (e.g. `vaapi` for Intel) to prevent bloat.
- **PGO Optimization**: Compiles `mpv` with two Profiling-Guided Optimization passes for maximum performance.
- **VapourSynth Integration**: Fully integrates VapourSynth and its critical plugins (`mvsfunc`, `havsfunc`, `zsmooth`) into the build.
- **PATH Accessibility**: Automatically symlinks `ffmpeg`, `mpv`, and `vspipe` to `/usr/local/bin` while generating dummy `equivs` debian packages to satisfy system apt dependencies.
