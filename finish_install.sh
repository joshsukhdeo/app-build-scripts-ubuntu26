#!/bin/bash
set -e

log_step() { echo -e "\n\033[1;36m==>\033[0m \033[1m$1\033[0m"; }
log_info() { echo -e "  \033[1;34m->\033[0m $1"; }
log_err() { echo -e "  \033[1;31m-> ERROR:\033[0m $1" >&2; }

install_dummy_packages() {
    log_step "Generating equivs dummy packages for mpv, ffmpeg, and vapoursynth..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get --fix-broken install -y equivs
    
    # mpv dummy
    cat << 'INNEREOF' > /tmp/mpv-dummy
Section: video
Priority: optional
Standards-Version: 3.9.2

Package: mpv
Version: 99:1.0.0-custom
Maintainer: Local Admin <admin@localhost>
Architecture: all
Description: Dummy package for custom mpv build
 This package prevents apt from installing the repository version of mpv,
 satisfying dependencies for other packages.
INNEREOF

    # ffmpeg dummy
    cat << 'INNEREOF' > /tmp/ffmpeg-dummy
Section: video
Priority: optional
Standards-Version: 3.9.2

Package: ffmpeg
Version: 99:7.0.0-custom
Maintainer: Local Admin <admin@localhost>
Architecture: all
Description: Dummy package for custom ffmpeg build
INNEREOF

    # vapoursynth dummy
    cat << 'INNEREOF' > /tmp/vapoursynth-dummy
Section: video
Priority: optional
Standards-Version: 3.9.2

Package: vapoursynth
Version: 99:65.0-custom
Maintainer: Local Admin <admin@localhost>
Architecture: all
Provides: libvapoursynth, libvapoursynth-dev, python3-vapoursynth
Description: Dummy package for custom vapoursynth build
INNEREOF

    pushd /tmp >/dev/null
    
    equivs-build mpv-dummy
    sudo dpkg -i mpv_1.0.0-custom_all.deb
    rm mpv-dummy mpv_1.0.0-custom_all.deb
    
    equivs-build ffmpeg-dummy
    sudo dpkg -i ffmpeg_7.0.0-custom_all.deb
    rm ffmpeg-dummy ffmpeg_7.0.0-custom_all.deb

    equivs-build vapoursynth-dummy
    sudo dpkg -i vapoursynth_65.0-custom_all.deb
    rm vapoursynth-dummy vapoursynth_65.0-custom_all.deb
    
    popd >/dev/null
}

finalize_installation() {
    log_step "Registering VapourSynth installation for the current user..."
    if command -v vapoursynth >/dev/null 2>&1; then
        vapoursynth register-install
    else
        log_err "vapoursynth command not found. Registration failed."
    fi

    log_step "Build and installation complete!"
}

install_dummy_packages
finalize_installation
