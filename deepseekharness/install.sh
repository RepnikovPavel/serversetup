#!/bin/bash

# Установка DeepSeek Harness из исходников по официальной инструкции:
#   git clone -> pnpm install -> pnpm run build -> pnpm dsh web
#
# Скрипт сам ставит подходящее окружение, без которого инструкция падает:
#   - проект требует node ^22.19 || >=24 (системный node в Ubuntu старее);
#   - pnpm ставится через corepack ровно той версии, что в package.json
#     (packageManager), и НЕ зависит от системного /usr/bin/pnpm;
#   - nvm прописывается в ~/.bashrc, иначе в новых терминалах shell снова
#     найдет старый /usr/bin/node и (возможно битый) /usr/bin/pnpm;
#   - build-essential + python3 нужны node-gyp для нативной сборки node-pty.
#
# Идемпотентен: повторный запуск обновляет репозиторий и пересобирает.
#
# Использование:
#   bash install.sh [каталог]   # по умолчанию ~/deepseek-harness

set -euo pipefail

INSTALL_DIR="${1:-$HOME/deepseek-harness}"
REPO_URL="https://github.com/deepseek-ai/deepseek-harness.git"
NODE_MAJOR=24          # требование проекта: node ^22.19 || >=24
PNPM_VERSION=11.7.0    # из поля packageManager в package.json репозитория

echo "==> Системные зависимости (git, curl, компилятор для node-pty)..."
sudo apt-get update
sudo apt-get install -y git curl build-essential python3

echo "==> nvm..."
export NVM_DIR="$HOME/.nvm"
if [ ! -s "$NVM_DIR/nvm.sh" ]; then
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
fi
. "$NVM_DIR/nvm.sh"

# nvm должен загружаться в каждом новом терминале, иначе shell найдет
# системный /usr/bin/node старой версии (и возможный битый /usr/bin/pnpm).
if ! grep -q 'NVM_DIR' "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" <<'EOF'

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
EOF
  echo "    блок nvm добавлен в ~/.bashrc"
fi

echo "==> Node.js $NODE_MAJOR..."
nvm install "$NODE_MAJOR"
nvm alias default "$NODE_MAJOR"
node --version

echo "==> pnpm $PNPM_VERSION через corepack..."
corepack enable
corepack prepare "pnpm@$PNPM_VERSION" --activate
pnpm --version

echo "==> Репозиторий в $INSTALL_DIR..."
if [ -d "$INSTALL_DIR/.git" ]; then
  git -C "$INSTALL_DIR" pull --ff-only
else
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

echo "==> pnpm install (при медленной сети pnpm сам повторяет запросы)..."
pnpm -C "$INSTALL_DIR" install

echo "==> pnpm run build..."
pnpm -C "$INSTALL_DIR" run build

cat <<EOF

Готово. Запуск:
  cd $INSTALL_DIR
  pnpm dsh web        # Web UI: http://127.0.0.1:3080

Если node/pnpm не находятся в уже открытом терминале: source ~/.bashrc
Для работы агента нужен ключ DeepSeek API:
  echo 'DEEPSEEK_API_KEY=...' >> $INSTALL_DIR/.env
(или задайте его в настройках Web UI)
EOF
