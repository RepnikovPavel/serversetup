#!/usr/bin/env bash
# Сборка патченого llama-server (форк RepnikovPavel/llama.cpp, ветка deepbench)
# внутри docker-образа с nvcc. Хост остаётся чистым (cmake докачивается в контейнер).
set -euo pipefail

LLAMA_FORK_DIR=${LLAMA_FORK_DIR:-$HOME/deepbench/llama.cpp}
BUILD_HOST_DIR=${BUILD_HOST_DIR:-/mnt/data1/PMRepnikov/deepbench_build}
DEBUG_IMAGE=${DEBUG_IMAGE:-unsloth-studio-custom:cu128}
BUILD_JOBS=${BUILD_JOBS:-32}   # сервер общий — не все 80 ядер
CUDA_ARCHS=${CUDA_ARCHS:-89}   # sm_89 = RTX 4090

[ -d "$LLAMA_FORK_DIR/src" ] || { echo "нет клона форка в $LLAMA_FORK_DIR (см. README)"; exit 1; }
mkdir -p "$BUILD_HOST_DIR"

docker rm -f llama-dbg-build >/dev/null 2>&1 || true
docker run -d --name llama-dbg-build --entrypoint bash \
    -v "$LLAMA_FORK_DIR:/deepbench/llama.cpp" \
    -v "$BUILD_HOST_DIR:/build" \
    "$DEBUG_IMAGE" -c "sleep infinity" >/dev/null

# cmake в образе нет — ставим бинарный tarball (без python/pip)
docker exec llama-dbg-build bash -c '
    if ! command -v cmake >/dev/null; then
        cd /tmp && curl -fsSL -o cmake.tar.gz \
            https://github.com/Kitware/CMake/releases/download/v3.30.5/cmake-3.30.5-linux-x86_64.tar.gz \
        && tar xzf cmake.tar.gz -C /opt \
        && ln -sf /opt/cmake-3.30.5-linux-x86_64/bin/cmake /usr/local/bin/cmake
    fi
    cmake --version | head -1'

docker exec llama-dbg-build bash -c "
    cmake -S /deepbench/llama.cpp -B /build/llama-cuda \
        -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=$CUDA_ARCHS \
        -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF \
        -DCMAKE_BUILD_TYPE=Release &&
    cmake --build /build/llama-cuda --target llama-server -j $BUILD_JOBS"

echo "OK: $BUILD_HOST_DIR/llama-cuda/bin/llama-server"
