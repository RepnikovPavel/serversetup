#!/bin/bash
# fix-apt-errors.sh - Автоматическое исправление ошибок apt-get update (Ubuntu 22.04 Jammy)

set -e  # Остановка при ошибках

echo "🔧 Исправление ошибок apt-get update..."

# 1. Фикс GPG ключей для VSCode (NO_PUBKEY EB3E94ADBE1229CF)
echo "📥 Обновление ключа Microsoft VSCode..."
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | \
    gpg --dearmor | sudo tee /usr/share/keyrings/microsoft-archive-keyring.gpg >/dev/null
echo "deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/microsoft-archive-keyring.gpg] \
    https://packages.microsoft.com/repos/vscode stable main" | \
    sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null

# 2. Фикс MiKTeX истекший ключ
echo "🗑️ Удаление проблемного MiKTeX репозитория..."
sudo rm -f /etc/apt/sources.list.d/miktex*.list

# 3. Перемещение проблемных NVIDIA репозиториев (legacy keys)
echo "🔄 Переконфигурация NVIDIA репозиториев..."
sudo rm -f /etc/apt/sources.list.d/nvidia-docker*.list
sudo rm -f /etc/apt/sources.list.d/libnvidia-container*.list
sudo rm -f /etc/apt/sources.list.d/nvidia-container-runtime*.list

# 4. Очистка legacy keyring warnings (опционально)
echo "🧹 Очистка устаревших ключей..."
sudo apt-key del 277A7293F59E4889 2>/dev/null || true  # MiKTeX
sudo apt-key list | grep -q "legacy" && echo "Legacy keys найдены, но продолжаем..."

# 5. Обновление кэша и проверка
echo "🔄 Финальное обновление apt..."
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*
sudo apt-get update

echo "✅ Ошибки apt-get update исправлены!"
echo "Проверьте: sudo apt-get update"
