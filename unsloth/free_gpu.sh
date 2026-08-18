#!/usr/bin/env bash
# free_gpu.sh — выгрузить модель и освободить VRAM. Ключи не нужны, запускать на сервере.
set -euo pipefail
CONTAINER="unsloth-studio-${CUDA_VARIANT:-cu128}"
docker exec "$CONTAINER" pkill -f llama-server || true
sleep 3
nvidia-smi --query-gpu=index,memory.used --format=csv,noheader
