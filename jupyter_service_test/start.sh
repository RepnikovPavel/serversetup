#!/usr/bin/env bash
set -euo pipefail

# Захардкоженный путь с использованием ~
WORKSPACE=~/jupyter_test
mkdir -p "$WORKSPACE"

export WORKSPACE
export CONTAINER_NAME="${CONTAINER_NAME:-jupyter-gpu-$(hostname)-$(date +%Y%m%d%H%M%S)}"

# Создаем папку workspace, если её нет
mkdir -p "$WORKSPACE"

docker compose -f docker-compose.yml up -d --build