#!/usr/bin/env bash
# Остановка debug llama-server. Stock Studio этот скрипт НЕ поднимает:
# docker start unsloth-studio-cu128
set -euo pipefail
docker rm -f llama-dbg-run >/dev/null 2>&1 || true
echo "debug-сервер остановлен"
