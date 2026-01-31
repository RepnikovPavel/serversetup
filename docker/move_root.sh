#!/bin/bash
# docker-restore-root.sh — ВОССТАНАВЛИВАЕТ Docker root на /mnt/nvme/docker/

echo "🔧 Восстанавливаем Docker root на /mnt/nvme/docker/..."

# 1. Останавливаем Docker
sudo systemctl stop docker docker.socket containerd

# 2. Backup текущего состояния
sudo mv /etc/docker/daemon.json /etc/docker/daemon.json.bak 2>/dev/null || true

# 3. Настраиваем daemon.json с ПРАВИЛЬНЫМ путем
sudo tee /etc/docker/daemon.json > /dev/null << EOF
{
  "data-root": "/mnt/nvme/docker",
  "dns": ["8.8.8.8", "1.1.1.1"],
  "dns-search": [],
  "exec-opts": ["native.cgroupdriver=systemd"]
}
EOF

# 4. Проверяем права на директорию
sudo chown root:root /mnt/nvme/docker
sudo chmod 755 /mnt/nvme/docker

# 5. Если в /var/lib/docker есть данные — переносим
if [ -d "/var/lib/docker" ] && [ "$(ls -A /var/lib/docker)" ]; then
    echo "🔄 Переносим данные из /var/lib/docker..."
    sudo rsync -av --progress /var/lib/docker/ /mnt/nvme/docker/
fi

# 6. Удаляем сломанную ссылку (если есть)
sudo rm -rf /var/lib/docker

# 7. Создаём symlink для совместимости
sudo ln -sfn /mnt/nvme/docker /var/lib/docker

# 8. Перезапуск Docker
sudo systemctl daemon-reload
sudo systemctl start docker
sleep 5

# 9. ПРОВЕРКА
echo "✅ ПРОВЕРКА:"
docker info | grep "Docker Root Dir"
docker image ls

echo "🎉 Docker root настроен на /mnt/nvme/docker/!"
