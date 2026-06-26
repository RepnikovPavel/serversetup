#!/bin/bash

echo "Создание директорий на HDD..."
sudo mkdir -p /mnt/hdd1/monitoring/prometheus
sudo mkdir -p /mnt/hdd1/monitoring/grafana

echo "Настройка прав для Prometheus (UID 65534)..."
sudo chown -R 65534:65534 /mnt/hdd1/monitoring/prometheus

echo "Настройка прав для Grafana (UID 472)..."
sudo chown -R 472:472 /mnt/hdd1/monitoring/grafana

echo "✅ Готово! Папки созданы и права выданы."