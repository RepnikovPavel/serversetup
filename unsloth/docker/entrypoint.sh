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

# UNSLOTH_HOST_DIR не задан при up — тома примонтированы из заглушки
# /nonexistent (см. docker-compose.yml), работать нельзя: падаем явно.
if [ -z "${UNSLOTH_HOST_DIR:-}" ]; then
    echo "ОШИБКА: не задан UNSLOTH_HOST_DIR." >&2
    echo "Запуск: UNSLOTH_HOST_DIR=/mnt/data1/unsloth_default docker compose up -d --build" >&2
    echo "(остановке переменные не нужны: docker compose down)" >&2
    exit 1
fi

if [ ! -x "$STUDIO_HOME/bin/unsloth" ]; then
    echo "=============================================================="
    echo " Первый запуск: установка Unsloth Studio в $STUDIO_HOME"
    echo " (venv + torch ${UNSLOTH_TORCH_INDEX_FAMILY:-auto} + llama.cpp, займёт время)"
    echo "=============================================================="
    UNSLOTH_SKIP_AUTOSTART=1 UNSLOTH_PYTHON=3.12 sh /opt/unsloth-install/install.sh
fi

# Пакет unsloth из форка (тарболл ветки с сервинг-фиксами) поверх PyPI-релиза.
# Маркер защищает от переустановки на каждый старт; смена spec = одна переустановка.
# Обновление той же ветки: удалить маркер (/data/studio/.unsloth_package_spec) и рестарт.
# --no-deps: ветка держится на коде установленного релиза, набор зависимостей тот же,
# а трогать torch/torchvision в работающем venv нельзя.
if [ -n "${UNSLOTH_PACKAGE_SPEC:-}" ]; then
    MARKER="$STUDIO_HOME/.unsloth_package_spec"
    if [ "$(cat "$MARKER" 2>/dev/null)" != "$UNSLOTH_PACKAGE_SPEC" ]; then
        echo "Установка пакета unsloth из: $UNSLOTH_PACKAGE_SPEC"
        SP="$STUDIO_HOME/unsloth_studio/lib/python3.12/site-packages"
        TMPD=$(mktemp -d)
        # В git-тарболле нет сборных артефактов релиза (frontend/dist, prebuilt
        # oxc-validator) — без них Studio падает с "frontend build not found".
        # Сохраняем от PyPI-пакета и возвращаем после установки.
        for d in "studio/frontend/dist" "studio/backend/core/data_recipe/oxc-validator/node_modules"; do
            if [ -d "$SP/$d" ]; then
                mkdir -p "$TMPD/$(dirname "$d")"
                cp -a "$SP/$d" "$TMPD/$d"
            fi
        done
        if uv pip install --python "$STUDIO_HOME/unsloth_studio/bin/python" --no-deps --refresh-package unsloth "$UNSLOTH_PACKAGE_SPEC"; then
            for d in "studio/frontend/dist" "studio/backend/core/data_recipe/oxc-validator/node_modules"; do
                if [ ! -d "$SP/$d" ] && [ -d "$TMPD/$d" ]; then
                    mkdir -p "$SP/$(dirname "$d")"
                    cp -a "$TMPD/$d" "$SP/$d"
                fi
            done
            echo "$UNSLOTH_PACKAGE_SPEC" > "$MARKER"
            rm -rf "$TMPD"
        else
            rm -rf "$TMPD"
            echo "ОШИБКА: не удалось установить $UNSLOTH_PACKAGE_SPEC" >&2
            echo "Очистите переменную UNSLOTH_PACKAGE_SPEC для отката на PyPI-релиз." >&2
            exit 1
        fi
    fi
fi

export PATH="$STUDIO_HOME/bin:$PATH"

# Лаунчер unsloth (с ~2026.8.7) трактует UNSLOTH_STUDIO_PASSWORD как --password
# и ПАДАЕТ на старте, если пароль уже инициализирован ("--password only sets the
# initial password"). Пароль нужен только при самом первом запуске — когда auth.db
# ещё нет. После инициализации переменную убираем, иначе контейнер уходит в
# restart-луп.
if [ -f "$STUDIO_HOME/auth/auth.db" ] && [ -n "${UNSLOTH_STUDIO_PASSWORD:-}" ]; then
    echo "auth.db уже есть — UNSLOTH_STUDIO_PASSWORD игнорируется (смена пароля: UI или unsloth studio reset-password)"
    unset UNSLOTH_STUDIO_PASSWORD
fi

# Studio слушает на всех интерфейсах — снаружи пробрасывается порт хоста.
exec unsloth studio -H 0.0.0.0 -p "${STUDIO_PORT:-8000}"
