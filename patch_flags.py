with open('build_mpv_vapoursynth.sh', 'r') as f:
    content = f.read()

import re

# We need to replace spaces with newlines in gpu_flags strings
content = re.sub(r'gpu_flags="--enable-vaapi --disable-amf --disable-nvenc --disable-cuvid --disable-ffnvcodec"',
                 'gpu_flags="--enable-vaapi\\n--disable-amf\\n--disable-nvenc\\n--disable-cuvid\\n--disable-ffnvcodec"', content)
content = re.sub(r'gpu_flags="--enable-nvenc --enable-cuvid --enable-ffnvcodec --disable-vaapi --disable-amf"',
                 'gpu_flags="--enable-nvenc\\n--enable-cuvid\\n--enable-ffnvcodec\\n--disable-vaapi\\n--disable-amf"', content)
content = re.sub(r'gpu_flags="--enable-amf --enable-vaapi --disable-nvenc --disable-cuvid --disable-ffnvcodec"',
                 'gpu_flags="--enable-amf\\n--enable-vaapi\\n--disable-nvenc\\n--disable-cuvid\\n--disable-ffnvcodec"', content)
content = re.sub(r'gpu_flags="--disable-amf --disable-nvenc --disable-cuvid --disable-ffnvcodec"',
                 'gpu_flags="--disable-amf\\n--disable-nvenc\\n--disable-cuvid\\n--disable-ffnvcodec"', content)

# Change how it's printed so newlines actually work
content = content.replace('${gpu_flags}', '$(echo -e "$gpu_flags")')

with open('build_mpv_vapoursynth.sh', 'w') as f:
    f.write(content)
