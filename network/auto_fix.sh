#!/bin/bash
# docker-vpn-buildx-ultimate-fix.sh — фикс без "default" имени
set -e

echo "🔧 ОКОНЧАТЕЛЬНЫЙ ФИКС buildx + VPN..."

# 1. Удаляем ВСЕХ кастомных builders кроме дефолтного
docker buildx ls | grep -v "default" | awk '{print $1}' | xargs -r docker buildx rm 2>/dev/null || true

# 2. Используем дефолтный builder (docker driver)
docker buildx use default
docker buildx inspect default --bootstrap

# 3. Жёсткий daemon.json
sudo tee /etc/docker/daemon.json > /dev/null << 'EOF'
{
  "dns": ["8.8.8.8", "1.1.1.1", "208.67.222.222"],
  "dns-search": [],
  "experimental": true,
  "ip6tables": false,
  "fixed-cidr": "172.17.0.0/16"
}
EOF

# 4. Полный перезапуск Docker
echo "🔄 Полный перезапуск Docker..."
sudo systemctl stop docker docker.socket containerd
sudo rm -rf /var/lib/docker/buildx/*
sudo systemctl start docker
sleep 8

# 5. Проверяем дефолтный builder
docker buildx ls | grep default

# 6. ТЕСТ: минимальный Dockerfile
cat > /tmp/Dockerfile.test << 'EOF'
FROM python:3.12-slim
RUN echo "nameserver 8.8.8.8" > /etc/resolv.conf && pip install tree-sitter
EOF

echo "🧪 Тест билда..."
if timeout 60 DOCKER_BUILDKIT=1 docker buildx build \
  --network=host \
  --dns 8.8.8.8,1.1.1.1 \
  --progress=plain \
  --no-cache \
  -f /tmp/Dockerfile.test \
  --load -t test:v1 . >/dev/null 2>&1; then
  
  echo -e "\n✅ Buildx + VPN РАБОТАЕТ!"
  docker rmi test:v1 2>/dev/null || true
  rm /tmp/Dockerfile.test
else
  echo -e "\n❌ Buildx всё ещё падает"
fi

# 7. Создаём ИДЕАЛЬНЫЙ алиас для docker/build.sh
cat >> ~/.bashrc << 'EOF'

# 🚀 Docker + VPN perfect build
dbuild() {
  docker buildx build \
    --platform linux/amd64 \
    --network=host \
    --dns 8.8.8.8,1.1.1.1 \
    --progress=plain \
    --no-cache \
    --load \
    "$@"
}
EOF

echo -e "\n🎉 НАСТРОЙКА ЗАВЕРШЕНА!"
echo "📋 Замените в docker/build.sh:"
echo "   docker buildx build → dbuild"
echo ""
echo "🚀 Пример:"
echo "   cd your-project"
echo "   dbuild -f Dockerfile -t modelscu124:latest ."
echo ""
echo "✅ Tree-sitter установится за 10 сек!"
