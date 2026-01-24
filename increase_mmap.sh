#!/bin/bash

# Скрипт для постоянной установки vm.max_map_count=262144
TARGET_VALUE=262144
CONFIG_FILE="/etc/sysctl.conf"

# Проверка root прав
if [[ $EUID -ne 0 ]]; then
   echo "Запустите скрипт с sudo: sudo $0"
   exit 1
fi

echo "=== Установка vm.max_map_count=$TARGET_VALUE ==="

# Проверка текущего значения
CURRENT_VALUE=$(sysctl -n vm.max_map_count 2>/dev/null || cat /proc/sys/vm/max_map_count 2>/dev/null)
echo "Текущее значение: $CURRENT_VALUE"

# Удаляем старые строки с vm.max_map_count (если есть)
if grep -q "^vm\.max_map_count" "$CONFIG_FILE" 2>/dev/null; then
    echo "Удаляем существующие строки vm.max_map_count..."
    sudo sed -i '/^vm\.max_map_count/d' "$CONFIG_FILE"
fi

# Добавляем новую строку
echo "Добавляем vm.max_map_count=$TARGET_VALUE в $CONFIG_FILE"
echo "vm.max_map_count=$TARGET_VALUE" >> "$CONFIG_FILE"

# Применяем изменения
echo "Применяем изменения..."
sysctl -p /etc/sysctl.conf

# Проверяем результат
NEW_VALUE=$(sysctl -n vm.max_map_count)
echo "Новое значение: $NEW_VALUE"

if [[ "$NEW_VALUE" == "$TARGET_VALUE" ]]; then
    echo "✅ Успех! vm.max_map_count=$TARGET_VALUE установлен постоянно."
    echo "Настройка сохранится после перезагрузки."
else
    echo "❌ Ошибка! Значение не установилось: $NEW_VALUE"
    exit 1
fi
