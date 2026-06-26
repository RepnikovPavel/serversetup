# Prometheus внутри контейнера работает от пользователя nobody (UID 65534)
sudo chown -R 65534:65534 /mnt/hdd1/monitoring/prometheus

# Grafana внутри контейнера работает от пользователя grafana (UID 472)
sudo chown -R 472:472 /mnt/hdd1/monitoring/grafana