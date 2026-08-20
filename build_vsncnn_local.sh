#!/usr/bin/env bash
set -Eeuo pipefail

readonly TMP_DIR=$(mktemp -d)
readonly VS_MLRT_REPO="https://github.com/AmusementClub/vs-mlrt.git"
readonly LOCAL_PLUGIN_DIR="/home/tay/.config/mpv/vs-plugins"

mkdir -p "${LOCAL_PLUGIN_DIR}"
cd "${TMP_DIR}"

echo "Cloning repositories concurrently..."
git clone --depth 1 https://github.com/Tencent/ncnn.git &
pid_ncnn=$!
git clone --recursive "${VS_MLRT_REPO}" vs-mlrt &
pid_mlrt=$!

wait $pid_ncnn
echo "Compiling ncnn..."
cd ncnn
git submodule update --init
mkdir -p build && cd build
cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DNCNN_VULKAN=ON -DNCNN_SYSTEM_GLSLANG=OFF -DNCNN_BUILD_EXAMPLES=OFF -DNCNN_BUILD_TOOLS=OFF -DNCNN_BUILD_TESTS=OFF -DCMAKE_INSTALL_PREFIX="${TMP_DIR}/ncnn_install" ..
ninja
ninja install
cd ../..

echo "Compiling vs-mlrt vsncnn..."
wait $pid_mlrt
cd vs-mlrt/vsncnn

sed -i 's/find_package(protobuf REQUIRED CONFIG)/find_package(Protobuf REQUIRED)/' CMakeLists.txt

mkdir -p build && cd build
cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DVAPOURSYNTH_INCLUDE_DIRECTORY=/usr/local/include/vapoursynth -Dncnn_DIR="${TMP_DIR}/ncnn_install/lib/cmake/ncnn" ..
ninja

cp -a *.so "${LOCAL_PLUGIN_DIR}/"

echo "Successfully installed vsncnn to ${LOCAL_PLUGIN_DIR}!"
