#!/bin/bash
# remove-yandex-browser.sh - Полное удаление Yandex Browser и репозитория

set -e  # Остановка при ошибках

echo "🗑️ Полное удаление Yandex Browser..."

# 1. Удаление пакетов Yandex Browser (если установлены)
echo "📦 Удаление пакетов..."
sudo apt purge yandex-browser-stable yandex-browser-beta 2>/dev/null || true
sudo apt purge yandex* 2>/dev/null || true
sudo apt autoremove --purge

# 2. Удаление репозитория
echo "📂 Удаление репозитория..."
sudo rm -f /etc/apt/sources.list.d/yandex-browser*.list
sudo rm -f /etc/apt/sources.list.d/yandex*.list

# 3. Удаление ключа GPG (если есть)
echo "🔑 Удаление GPG ключа..."
sudo rm -f /usr/share/keyrings/yandex* 2>/dev/null || true
sudo apt-key del "Yandex" 2>/dev/null || true

# 4. Очистка пользовательских данных
echo "👤 Очистка пользовательских данных..."
rm -rf ~/.config/yandex-browser* 2>/dev/null || true
rm -rf ~/.cache/yandex-browser* 2>/dev/null || true
rm -rf ~/.local/share/yandex-browser* 2>/dev/null || true

# 5. Обновление apt
echo "🔄 Обновление apt..."
sudo apt update

# 6. Проверка
echo "✅ Проверка удаления..."
if [ ! -f "/etc/apt/sources.list.d/yandex-browser.list" ]; then
    echo "✅ Репозиторий удален"
fi

if ! dpkg -l | grep -q yandex; then
    echo "✅ Пакеты удалены"
fi

echo "🎉 Yandex Browser полностью удален!"
echo "Проверьте: sudo apt update"
