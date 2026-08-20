#!/usr/bin/env bash
set -Eeuo pipefail

readonly TMP_DIR=$(mktemp -d)
readonly VS_MLRT_REPO="https://github.com/AmusementClub/vs-mlrt.git"
readonly PLUGIN_DIR="/usr/local/lib/vapoursynth"

sudo apt-get update
sudo apt-get install -y build-essential cmake ninja-build git libonnx-dev libprotobuf-dev p7zip-full libvulkan-dev glslang-dev glslang-tools vulkan-tools libvulkan1

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
cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DNCNN_VULKAN=ON -DNCNN_SYSTEM_GLSLANG=ON -DNCNN_BUILD_EXAMPLES=OFF -DNCNN_BUILD_TOOLS=OFF -DNCNN_BUILD_TESTS=OFF -DCMAKE_INSTALL_PREFIX=/usr/local ..
ninja
sudo ninja install
cd ../..

echo "Compiling vs-mlrt vsncnn..."
wait $pid_mlrt
cd vs-mlrt/vsncnn

sed -i 's/find_package(protobuf REQUIRED CONFIG)/find_package(Protobuf REQUIRED)/' CMakeLists.txt

mkdir -p build && cd build
cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DVAPOURSYNTH_INCLUDE_DIRECTORY=/usr/local/include/vapoursynth ..
ninja

sudo cp -a *.so "${PLUGIN_DIR}/"

echo "Successfully installed vsncnn!"
