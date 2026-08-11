#!/usr/bin/env bash
# Source-level профилировка patched llama-server через Nsight Compute (ncu) на сервере 2x4090.
# Даёт то, чего нет в nsys: SASS, per-instruction sampling, memory workload counters.
#
#   ./profile_ncu.sh start     # поднять сервер под ncu (ждёт готовности)
#   ./profile_ncu.sh bench     # прогнать короткий промпт (MAX_TOKENS, default 32)
#   ./profile_ncu.sh stop      # финализировать .ncu-rep (anchored kill, как в profile.sh!)
#   ./profile_ncu.sh fetch DIR # забрать .ncu-rep на localhost в DIR
#
# env: DSB_SSH, DSB_BUILD_DIR, DSB_RUN_DIR — см. ~/.deepseekbench_env
# NCU_LAUNCHES — сколько kernel launches профилировать (default 24).
#
# ВАЖНО: контейнеру нужен --privileged (CAP_SYS_ADMIN в init userns) —
# иначе драйвер не даёт доступ к GPU performance counters (ERR_NVGPUCTRPERM).
set -euo pipefail

DSB_SSH=${DSB_SSH:?задай DSB_SSH (user@host сервера 2x4090), см. ~/.deepseekbench_env}
DSB_BUILD_DIR=${DSB_BUILD_DIR:-/mnt/data1/deepbench/build}
DSB_RUN_DIR=${DSB_RUN_DIR:-/mnt/data1/deepbench/run}
UNSLOTH_HOST_DIR=${UNSLOTH_HOST_DIR:-/mnt/data1/unsloth}
PROF_IMAGE=${PROF_IMAGE:-unsloth-debug-prof:nsys2025.6.3.541}
DEBUG_PORT=${DEBUG_PORT:-18222}
MAX_TOKENS=${MAX_TOKENS:-32}
CTX=${CTX:-4096}
NCU_LAUNCHES=${NCU_LAUNCHES:-24}
NCU_KERNELS=${NCU_KERNELS:-regex:mul_mat}
CONTAINER=llama-dbg-ncu
# DeepSeek-V4-Flash UD-IQ3_XXS (~104 ГБ) — меньшая квантизация. Грузим с
# --load-mode none (модель честно занимает RAM, без mmap page-cache) — для
# 104 ГБ это безопасно (сервер 251 ГБ). Урок 2026-08-07: Q4_K_XL (144 ГБ) с
# --load-mode none уронил сервер (OOM/SIGKILL) — с полной моделью флаг не
# использовать. Шарды: $DSB_RUN_DIR/models/IQ3_XXS (00001-00003 — симлинки в
# hf_cache, 00004 докачан отдельно). Q4_K_XL задавать явно через MODEL_GGUF=...
MODEL_GGUF=${MODEL_GGUF:-/dbg/models/IQ3_XXS/DeepSeek-V4-Flash-0731-UD-IQ3_XXS-00001-of-00004.gguf}

CMD=${1:?usage: profile_ncu.sh start|bench|stop|fetch}

case "$CMD" in
start)
    ssh "$DSB_SSH" "docker image inspect $PROF_IMAGE >/dev/null 2>&1 || { echo 'нет образа $PROF_IMAGE' >&2; exit 1; }"
    # --privileged: без CAP_SYS_ADMIN драйвер отдаёт ERR_NVGPUCTRPERM (счётчики недоступны)
    ssh "$DSB_SSH" "docker rm -f $CONTAINER >/dev/null 2>&1; docker run -d --name $CONTAINER --privileged --gpus all --entrypoint bash \
        -v $UNSLOTH_HOST_DIR/hf_cache:/data/hf_cache:ro \
        -v $DSB_BUILD_DIR:/build -v $DSB_RUN_DIR:/dbg \
        -p $DEBUG_PORT:8080 \
        $PROF_IMAGE -c 'sleep infinity' >/dev/null \
     && docker exec -d $CONTAINER bash -c 'ncu --target-processes all \
        -o /dbg/deepseek_ncu --force-overwrite \
        --kernel-name-base demangled --kernel-name \"$NCU_KERNELS\" \
        --launch-count $NCU_LAUNCHES --set full \
        /build/llama-cuda-lineinfo/bin/llama-server \
        -m $MODEL_GGUF --host 0.0.0.0 --port 8080 --alias deepseek-ncu \
        -c $CTX --parallel 1 --flash-attn on --fit on --jinja --load-mode none > /dbg/server-ncu.log 2>&1'"
    echo "загрузка модели (--load-mode none: 104 ГБ честно в RAM — ждать дольше обычного)..."
    until ssh "$DSB_SSH" "curl -s -m 3 http://127.0.0.1:$DEBUG_PORT/health | grep -q '\"ok\"'" 2>/dev/null; do sleep 15; done
    echo "READY: порт $DEBUG_PORT на сервере"
    ;;
bench)
    ssh "$DSB_SSH" "cd ~/deepbench/deepseekbench && SERVER=http://127.0.0.1:$DEBUG_PORT MAX_TOKENS=$MAX_TOKENS OUT_DIR=$DSB_RUN_DIR/results bash bench/run_benchmark.sh"
    ;;
stop)
    # anchored pgrep — см. profile.sh, та же ловушка с cmdline обёртки
    ssh "$DSB_SSH" "docker exec $CONTAINER bash -c 'kill -TERM \$(pgrep -f \"^/build/llama-cuda-lineinfo/bin/llama-server\")'"
    echo "жду финализации ncu..."
    for i in $(seq 1 24); do
        ssh "$DSB_SSH" "docker exec $CONTAINER bash -c 'pgrep -x ncu >/dev/null'" 2>/dev/null || break
        sleep 10
    done
    ssh "$DSB_SSH" "ls -la $DSB_RUN_DIR/*.ncu-rep"
    ;;
fetch)
    OUT=${2:-~/profile/deepseek/latest}
    mkdir -p "$OUT"
    scp "$DSB_SSH:$DSB_RUN_DIR/deepseek_ncu.ncu-rep" "$OUT/"
    echo "забрано в $OUT; просмотр: ./docker/ncu-ui.sh $OUT/deepseek_ncu.ncu-rep"
    ;;
*) echo "unknown: $CMD (start|bench|stop|fetch)"; exit 1;;
esac
