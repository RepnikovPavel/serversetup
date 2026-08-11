#!/usr/bin/env bash
# Профилировочный запуск patched llama-server под nsys (pinned версия) на сервере 2x4090.
#
#   ./profile.sh start     # поднять сервер под nsys (ждёт готовности)
#   ./profile.sh bench     # прогнать бенчмарк-промпт (MAX_TOKENS, default 2048)
#   ./profile.sh stop      # корректно финализировать профиль (anchored kill!)
#   ./profile.sh fetch DIR # забрать .nsys-rep + trace.jsonl на localhost в DIR
#
# env: DSB_SSH (user@host сервера), DSB_BUILD_DIR, DSB_RUN_DIR — см. ~/.deepseekbench_env
set -euo pipefail

DSB_SSH=${DSB_SSH:?задай DSB_SSH (user@host сервера 2x4090), см. ~/.deepseekbench_env}
DSB_BUILD_DIR=${DSB_BUILD_DIR:-/mnt/data1/deepbench/build}
DSB_RUN_DIR=${DSB_RUN_DIR:-/mnt/data1/deepbench/run}
UNSLOTH_HOST_DIR=${UNSLOTH_HOST_DIR:-/mnt/data1/unsloth}
PROF_IMAGE=${PROF_IMAGE:-unsloth-debug-prof:nsys2025.6.3.541}
DEBUG_PORT=${DEBUG_PORT:-18222}
MAX_TOKENS=${MAX_TOKENS:-2048}
CTX=${CTX:-4096}
CONTAINER=llama-dbg-prof
MODEL_GGUF=${MODEL_GGUF:-/data/hf_cache/hub/models--unsloth--DeepSeek-V4-Flash-0731-GGUF/snapshots/ca7936e6ef3f287be84cc748cb1870725c16d99a/UD-Q4_K_XL/DeepSeek-V4-Flash-0731-UD-Q4_K_XL-00001-of-00005.gguf}

CMD=${1:?usage: profile.sh start|bench|stop|fetch}

case "$CMD" in
start)
    # образ с pinned nsys (собрать один раз: docker build -f Dockerfile.prof .)
    ssh "$DSB_SSH" "docker image inspect $PROF_IMAGE >/dev/null 2>&1 || { echo 'сначала: docker build -t $PROF_IMAGE -f Dockerfile.prof .' >&2; exit 1; }"
    # LLAMA_DEBUG_EXPERT_TRACE включён — трасса роутинга пишется параллельно профилю.
    # OP_COUNT специально выключен: его per-batch sync искажает GPU-таймлайн.
    ssh "$DSB_SSH" "docker rm -f $CONTAINER >/dev/null 2>&1; docker run -d --name $CONTAINER --gpus all --cap-add SYS_PTRACE --entrypoint bash \
        -v $UNSLOTH_HOST_DIR/hf_cache:/data/hf_cache:ro \
        -v $DSB_BUILD_DIR:/build -v $DSB_RUN_DIR:/dbg \
        -p $DEBUG_PORT:8080 \
        -e LLAMA_DEBUG_EXPERT_TRACE=/dbg/trace.jsonl \
        $PROF_IMAGE -c 'sleep infinity' >/dev/null \
     && docker exec -d $CONTAINER bash -c '"$(echo /opt/nvidia/nsight-systems/*/target-linux-x64/nsys)" profile -t cuda --cuda-graph-trace=node --sample=none --cpuctxsw=none \
        -o /dbg/deepseek_profile --force-overwrite true \
        /build/llama-cuda-lineinfo/bin/llama-server \
        -m $MODEL_GGUF --host 0.0.0.0 --port 8080 --alias deepseek-prof \
        -c $CTX --parallel 1 --flash-attn on --fit on --jinja --load-mode none > /dbg/server-prof.log 2>&1'"
    echo "загрузка модели ~2 мин; жду готовности..."
    until ssh "$DSB_SSH" "curl -s -m 3 http://127.0.0.1:$DEBUG_PORT/health | grep -q '\"ok\"'" 2>/dev/null; do sleep 10; done
    echo "READY: http://$DSB_SSH#:$DEBUG_PORT (порт $DEBUG_PORT на сервере)"
    ;;
bench)
    ssh "$DSB_SSH" "cd ~/deepbench/deepseekbench && SERVER=http://127.0.0.1:$DEBUG_PORT MAX_TOKENS=$MAX_TOKENS OUT_DIR=$DSB_RUN_DIR/results bash bench/run_benchmark.sh"
    ;;
stop)
    # ВАЖНО: anchored pgrep — обычный 'pkill -f llama-server' матчит и обёртку nsys
    # (её cmdline содержит путь к llama-server) и профиль теряется незаписанным.
    ssh "$DSB_SSH" "docker exec $CONTAINER bash -c 'kill -TERM \$(pgrep -f \"^/build/llama-cuda-lineinfo/bin/llama-server\")'"
    echo "жду финализации nsys (до 3 мин на длинном трейсе)..."
    for i in $(seq 1 18); do
        ssh "$DSB_SSH" "docker exec $CONTAINER bash -c 'pgrep -x nsys >/dev/null'" 2>/dev/null || break
        sleep 10
    done
    ssh "$DSB_SSH" "ls -la $DSB_RUN_DIR/*.nsys-rep $DSB_RUN_DIR/trace.jsonl"
    ;;
fetch)
    OUT=${2:-~/profile/deepseek/latest}
    mkdir -p "$OUT"
    scp "$DSB_SSH:$DSB_RUN_DIR/deepseek_profile.nsys-rep" "$DSB_SSH:$DSB_RUN_DIR/trace.jsonl" "$OUT/"
    echo "забрано в $OUT; визуализация экспертов:"
    echo "  python3 ~/deepseekbench/bench/visualize_experts.py --trace $OUT/trace.jsonl --out $OUT/expert_graph.html"
    ;;
*) echo "unknown: $CMD (start|bench|stop|fetch)"; exit 1;;
esac
