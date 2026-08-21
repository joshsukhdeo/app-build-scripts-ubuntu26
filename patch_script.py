import re

with open('build_mpv_vapoursynth.sh', 'r') as f:
    content = f.read()

# Replace the static ffmpeg_options generation with a dynamic one
old_ffmpeg_config = """    log_info "Configuring FFmpeg options..."
    cat > ffmpeg_options << 'EOF'
--cc=clang
--cxx=clang++
--ar=llvm-ar
--nm=llvm-nm
--ranlib=llvm-ranlib
--enable-vapoursynth
--enable-libzimg
--enable-gpl
--enable-version3
--enable-nonfree
--enable-vaapi
--enable-lto
--disable-encoders
--disable-muxers
--disable-doc
--extra-cflags=-O3 -march=native -mtune=native -pipe -fno-plt -flto -fuse-ld=lld
--extra-cxxflags=-O3 -march=native -mtune=native -pipe -fno-plt -flto -fuse-ld=lld
--extra-ldflags=-fuse-ld=lld
EOF"""

new_ffmpeg_config = """    log_info "Configuring FFmpeg options dynamically based on GPU..."
    
    # Detect GPU
    local gpu_flags=""
    if lspci | grep -iE 'vga|3d|display' | grep -i intel >/dev/null; then
        log_info "Intel GPU detected. Enabling VAAPI and OpenVINO, disabling AMD/Nvidia specific hwaccels."
        gpu_flags="--enable-vaapi --disable-amf --disable-nvenc --disable-cuvid --disable-ffnvcodec"
    elif lspci | grep -iE 'vga|3d|display' | grep -i nvidia >/dev/null; then
        log_info "Nvidia GPU detected. Enabling NVENC/CUVID, disabling AMD/Intel specific hwaccels."
        gpu_flags="--enable-nvenc --enable-cuvid --enable-ffnvcodec --disable-vaapi --disable-amf"
    elif lspci | grep -iE 'vga|3d|display' | grep -i amd >/dev/null; then
        log_info "AMD GPU detected. Enabling AMF/VAAPI, disabling Nvidia specific hwaccels."
        gpu_flags="--enable-amf --enable-vaapi --disable-nvenc --disable-cuvid --disable-ffnvcodec"
    else
        log_info "No specific recognized GPU detected. Falling back to default."
        gpu_flags="--disable-amf --disable-nvenc --disable-cuvid --disable-ffnvcodec"
    fi

    cat > ffmpeg_options << EOF
--cc=clang
--cxx=clang++
--ar=llvm-ar
--nm=llvm-nm
--ranlib=llvm-ranlib
--enable-vapoursynth
--enable-libzimg
--enable-gpl
--enable-version3
--enable-nonfree
--enable-lto
--disable-doc
\$gpu_flags
--extra-cflags=-O3 -march=native -mtune=native -pipe -fno-plt -flto -fuse-ld=lld
--extra-cxxflags=-O3 -march=native -mtune=native -pipe -fno-plt -flto -fuse-ld=lld
--extra-ldflags=-fuse-ld=lld
EOF"""

content = content.replace(old_ffmpeg_config, new_ffmpeg_config)

# Fix ffmpeg installation to ensure it is in PATH
old_install = """    log_info "Installing compiled FFmpeg..."
    sudo make -C ffmpeg_build install"""

new_install = """    log_info "Installing compiled FFmpeg to PATH..."
    sudo make -C ffmpeg_build install
    sudo cp ffmpeg_build/ffmpeg /usr/local/bin/ffmpeg
    sudo cp ffmpeg_build/ffprobe /usr/local/bin/ffprobe
    sudo chmod +x /usr/local/bin/ffmpeg /usr/local/bin/ffprobe"""

content = content.replace(old_install, new_install)

with open('build_mpv_vapoursynth.sh', 'w') as f:
    f.write(content)
