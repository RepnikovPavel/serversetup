#!/bin/bash
# fix-vscode-duplicate-repos.sh - Удаление дублирующихся VSCode репозиториев (Ubuntu 22.04 Jammy)

set -e  # Остановка при ошибках

echo "🔧 Исправление дублирующихся VSCode репозиториев..."

# 1. Проверка существующих файлов
echo "📋 Проверка репозиториев VSCode:"
ls -la /etc/apt/sources.list.d/ | grep -i vscode || echo "Файлы VSCode не найдены"

# 2. Удаление дублирующихся VSCode репозиториев
echo "🗑️ Удаление старых/дублирующихся файлов..."
sudo rm -f /etc/apt/sources.list.d/archive_uri-https_packages_microsoft_com_repos_vscode-jammy.list
sudo rm -f /etc/apt/sources.list.d/vscode.list

# 3. Создание единого правильного VSCode репозитория
echo "📥 Создание правильного VSCode репозитория..."
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | \
    gpg --dearmor | sudo tee /usr/share/keyrings/microsoft-vscode-keyring.gpg >/dev/null

echo "deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/microsoft-vscode-keyring.gpg] \
    https://packages.microsoft.com/repos/vscode stable main" | \
    sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null

# 4. Очистка кэша и обновление
echo "🔄 Очистка кэша и обновление..."
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*
sudo apt-get update

# 5. Проверка результата
echo "✅ Проверка результата:"
if sudo apt-get update 2>&1 | grep -q "configured multiple times"; then
    echo "❌ Предупреждения о дубликатах всё ещё присутствуют!"
    ls -la /etc/apt/sources.list.d/ | grep -i vscode
else
    echo "✅ Дублирующиеся репозитории успешно удалены!"
fi

echo "📋 Текущие VSCode файлы:"
ls -la /etc/apt/sources.list.d/ | grep -i vscode || echo "VSCode репозитории настроены корректно"
