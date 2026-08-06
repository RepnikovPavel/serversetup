#!/usr/bin/env bash
# Точка входа контейнера Unsloth Studio.
#
# При ПЕРВОМ запуске (когда $UNSLOTH_STUDIO_HOME/bin/unsloth ещё нет)
# ставит Studio в $UNSLOTH_STUDIO_HOME — это смонтированный том на хостовом
# диске, поэтому вся тяжёлая установка (venv, torch, llama.cpp) лежит там,
# а не в overlay докера. Повторные запуски идут сразу к старту Studio.
set -e

STUDIO_HOME="${UNSLOTH_STUDIO_HOME:-/data/studio}"
export UNSLOTH_STUDIO_HOME="$STUDIO_HOME"

if [ ! -x "$STUDIO_HOME/bin/unsloth" ]; then
    echo "=============================================================="
    echo " Первый запуск: установка Unsloth Studio в $STUDIO_HOME"
    echo " (venv + torch ${UNSLOTH_TORCH_INDEX_FAMILY:-auto} + llama.cpp, займёт время)"
    echo "=============================================================="
    UNSLOTH_SKIP_AUTOSTART=1 UNSLOTH_PYTHON=3.12 sh /opt/unsloth-install/install.sh
fi

export PATH="$STUDIO_HOME/bin:$PATH"

# Studio слушает на всех интерфейсах — снаружи пробрасывается порт хоста.
exec unsloth studio -H 0.0.0.0 -p "${STUDIO_PORT:-8000}"
