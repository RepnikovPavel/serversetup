#!/bin/bash
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"

echo "Остановка мониторинга..."
docker compose down

if [ $? -eq 0 ]; then
    echo "✅ Остановлено. Данные на /mnt/hdd1/monitoring не тронуты."
else
    echo "❌ Ошибка остановки."
fi