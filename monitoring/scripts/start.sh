#!/bin/bash
# Переходим в корень репозитория (на один уровень выше папки scripts)
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"

# На всякий случай проверяем наличие папок на HDD
mkdir -p /mnt/hdd1/monitoring/prometheus
mkdir -p /mnt/hdd1/monitoring/grafana

echo "Запуск мониторинга из $REPO_DIR..."
docker compose up -d

if [ $? -eq 0 ]; then
    echo "✅ Готово!"
    echo "Prometheus: http://localhost:9090"
    echo "Grafana:    http://localhost:3000"
else
    echo "❌ Ошибка запуска."
fi