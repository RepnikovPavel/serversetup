#!/usr/bin/env bash
# Обновление Kimi Code CLI до последней версии.
# Официальный установщик идемпотентен: ставит/обновляет бинарник в ~/.kimi-code/bin,
# старую версию сохраняет как kimi.bak.
set -euo pipefail

curl -fsSL https://code.kimi.com/kimi-code/install.sh | bash
kimi --version
