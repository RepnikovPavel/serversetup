#!/bin/bash
# docker-vpn-fixer.sh — ТОЧНАЯ диагностика + РЕШЕНИЕ одним скриптом
set -e

echo "🚨 АВТОФИКС Docker + VPN проблем"
echo "================================="

# Цвета
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' NC='\033[0m'

# 1. ПРЯМАЯ ДИАГНОСТИКА
echo "🔍 ЧТО СЛОМАНО:"
docker run --rm alpine cat /etc/resolv.conf > /tmp/docker_resolv.conf 2>/dev/null || echo "TIMEOUT" > /tmp/docker_resolv.conf

if grep -q "127.0.0.53" /tmp/docker_resolv.conf 2>/dev/null; then
    echo -e "${RED}❌ ПРИЧИНА #1: systemd-resolved (127.0.0.53) ломает Docker${NC}"
    FIX1="daemon.json dns"
elif ! docker run --rm alpine nslookup pypi.org >/dev/null 2>&1; then
    echo -e "${RED}❌ ПРИЧИНА #2: Docker DNS не резолвит домены${NC}"
    FIX1="daemon.json dns"
else
    echo -e "${GREEN}✅ DNS конфигурация OK${NC}"
    FIX1=""
fi

# 2. VPN ROUTING КОНФЛИКТ
HOST_GW=$(ip route show default | head -1 | awk '{print $3}')
DOCKER_GW=$(docker network inspect bridge -f '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null)

if [[ "$HOST_GW" == "$DOCKER_GW" ]]; then
    echo -e "${RED}❌ ПРИЧИНА #3: Конфликт шлюзов $HOST_GW${NC}"
    FIX2="iptables"
else
    echo -e "${GREEN}✅ Маршрутизация OK${NC}"
    FIX2=""
fi

# 3. PIP BUILD ТЕСТ
if timeout 20 docker run --rm python:3.12-slim pip install tree-sitter --dry-run >/dev/null 2>&1; then
    echo -e "${GREEN}✅ PIP работает${NC}"
else
    echo -e "${RED}❌ ПРИЧИНА #4: pip install падает${NC}"
    FIX3="build args"
fi

echo ""
echo "🔧 ФИКСИМ (${FIX1} ${FIX2} ${FIX3})..."

# ================================
# 4. АВТОФИКС

# Фикс #1: Docker daemon DNS
echo '{"dns":["8.8.8.8","1.1.1.1"],"fixed-cidr":"172.17.0.0/16"}' | sudo tee /etc/docker/daemon.json >/dev/null

# Фикс #2: iptables для docker0
sudo iptables -D INPUT -i docker0 -j ACCEPT 2>/dev/null || true
sudo iptables -I INPUT 1 -i docker0 -j ACCEPT
sudo iptables -I INPUT 2 -i docker0 -p udp --dport 53 -j ACCEPT

# Фикс #3: Docker restart
echo "🔄 Перезапуск Docker..."
sudo systemctl stop docker docker.socket containerd 2>/dev/null || true
sleep 2
sudo systemctl start docker
sleep 5

# 5. ВЕРИФИКАЦИЯ
echo "✅ ПРОВЕРКА ФИКСА:"
if docker run --rm alpine nslookup pypi.org >/dev/null 2>&1; then
    echo -e "${GREEN}✅ DNS РАБОТАЕТ${NC}"
else
    echo -e "${RED}❌ DNS всё ещё сломан${NC}"
    echo "🔧 Дополнительно:"
    echo "docker buildx build --network=host --dns 8.8.8.8 ..."
    exit 1
fi

if timeout 20 docker run --rm python:3.12-slim pip install tree-sitter --dry-run >/dev/null 2>&1; then
    echo -e "${GREEN}✅ PIP РАБОТАЕТ${NC}"
    echo -e "${GREEN}🎉 ВСЁ ОК!${NC}"
else
    echo -e "${YELLOW}⚠️  Используйте: --network=host --dns 8.8.8.8${NC}"
fi

echo ""
echo "🚀 НОВЫЕ КОМАНДЫ для docker/build.sh:"
echo "dbuild() { docker buildx build --network=host --dns 8.8.8.8,1.1.1.1 \$@; }"
echo 'echo "dbuild . -t your-image" >> ~/.bashrc'
