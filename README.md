# app-build-scripts-ubuntu26

A collection of custom build scripts specifically tuned for Ubuntu.

## `build_mpv_vapoursynth.sh`

This script compiles a highly optimized, custom toolchain containing `mpv`, `ffmpeg`, and `VapourSynth`.

### Key Features
- **Dynamic Hardware Acceleration**: Automatically detects your hardware (`lspci`) and limits compilation strictly to the GPUs present (e.g. `vaapi` for Intel) to prevent bloat.
- **PGO Optimization**: Compiles `mpv` with two Profiling-Guided Optimization passes for maximum performance.
- **VapourSynth Integration**: Fully integrates VapourSynth and its critical plugins (`mvsfunc`, `havsfunc`, `zsmooth`) into the build.
- **PATH Accessibility**: Automatically symlinks `ffmpeg`, `mpv`, and `vspipe` to `/usr/local/bin` while generating dummy `equivs` debian packages to satisfy system apt dependencies.

### Command Line Arguments
The script supports several arguments to modify its compilation behavior:
- `-h`, `--help`: Show the help message and exit.
- `--std-flags-only` or `--no-experimental-flags`: Disables aggressive experimental hardware optimizations (keeps standard optimizations).
- `--all-codecs`: Builds FFmpeg with all codecs (do not disable unused hwaccels). *Explicitly discouraged.*
- `--unoptimized`: Disables both hardware optimizations and codec restrictions (alias for `--std-flags-only` + `--all-codecs`). *Explicitly discouraged.*
- `--disable-profiling`: Skips the PGO profiling compilation block for `mpv`. *Explicitly discouraged.*

## Testing

This repository is strictly tested via the `bats` framework.
To run the tests:
```bash
bats tests/
```

Test directories are isolated for modularity:
- `tests/ffmpeg/`: Validates hardware acceleration flags and paths.
- `tests/mpv-vapoursynth/`: Validates the PGO generation loop and runtime.
- `tests/ncnn/`: Validates OpenVINO and vs-mlrt AI bindings.
- `tests/utils/`: Validates helper scripts and compiler prerequisites.
