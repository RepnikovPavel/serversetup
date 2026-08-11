#!/usr/bin/env bash
# Запуск патченого (deepbench) llama-server с DeepSeek-V4-Flash-0731 UD-Q4_K_XL.
# ОСТАНАВЛИВАЕТ stock Studio (unsloth-studio-cu128) — GPU и VRAM нужны целиком.
# Вернуть stock: ./stop.sh && docker start unsloth-studio-cu128
set -euo pipefail

BUILD_HOST_DIR=${BUILD_HOST_DIR:-/mnt/data1/deepbench/build}
RUN_HOST_DIR=${RUN_HOST_DIR:-/mnt/data1/deepbench/run}
UNSLOTH_HOST_DIR=${UNSLOTH_HOST_DIR:-/mnt/data1/unsloth}
DEBUG_IMAGE=${DEBUG_IMAGE:-unsloth-studio-custom:cu128}
DEBUG_PORT=${DEBUG_PORT:-18222}
CTX=${CTX:-4096}
STUDIO_CONTAINER=${STUDIO_CONTAINER:-unsloth-studio-cu128}

MODEL_GGUF=${MODEL_GGUF:-/data/hf_cache/hub/models--unsloth--DeepSeek-V4-Flash-0731-GGUF/snapshots/ca7936e6ef3f287be84cc748cb1870725c16d99a/UD-Q4_K_XL/DeepSeek-V4-Flash-0731-UD-Q4_K_XL-00001-of-00005.gguf}

[ -x "$BUILD_HOST_DIR/llama-cuda/bin/llama-server" ] || { echo "сначала ./build.sh"; exit 1; }
mkdir -p "$RUN_HOST_DIR"

# debug-серверу нужны обе карты — останавливаем Studio, если крутится
if [ "$(docker inspect -f '{{.State.Running}}' "$STUDIO_CONTAINER" 2>/dev/null)" = "true" ]; then
    echo "останавливаю $STUDIO_CONTAINER (вернуть: docker start $STUDIO_CONTAINER)"
    docker stop "$STUDIO_CONTAINER" >/dev/null
fi

docker rm -f llama-dbg-run >/dev/null 2>&1 || true
docker run -d --name llama-dbg-run --gpus all --entrypoint bash \
    -v "$UNSLOTH_HOST_DIR/hf_cache:/data/hf_cache:ro" \
    -v "$BUILD_HOST_DIR:/build" \
    -v "$RUN_HOST_DIR:/dbg" \
    -p "$DEBUG_PORT:8080" \
    -e LLAMA_DEBUG_OP_COUNT=1 \
    -e LLAMA_DEBUG_EXPERT_TRACE=/dbg/trace.jsonl \
    "$DEBUG_IMAGE" -c "sleep infinity" >/dev/null

docker exec -d llama-dbg-run bash -c "
    /build/llama-cuda/bin/llama-server \
        -m '$MODEL_GGUF' \
        --port 8080 --alias deepseek-debug \
        --host 0.0.0.0 --port 8080 --alias deepseek-debug \
        -c $CTX --parallel 1 --flash-attn on --fit on --jinja --load-mode none \
        > /dbg/server.log 2>&1"

echo "запущен: http://127.0.0.1:$DEBUG_PORT  (лог: $RUN_HOST_DIR/server.log)"
echo "загрузка модели ~2 мин: tail -f $RUN_HOST_DIR/server.log"
