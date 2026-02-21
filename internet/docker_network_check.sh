#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

CONTAINER=${1:-test-pip}
TEST_IMAGE="python:3.11-slim"

echo -e "${YELLOW}🔍 ДИАГНОСТИКА Docker сети для pip/Python extensions${NC}"

# 1. Проверка Docker daemon и базовой сети
echo -e "\n1️⃣ Docker статус и сети:"
docker info --format '{{.ServerVersion}} {{.DockerRootDir}}' || { echo -e "${RED}❌ Docker не запущен${NC}"; exit 1; }
docker network ls
docker network inspect bridge --format '{{json .IPAM.Config}}' | jq . 2>/dev/null || echo "jq не установлен, пропуск"

# 2. VPN/iptables на хосте (часто ломает Docker)
echo -e "\n2️⃣ Хост: VPN/Proxy/Маршруты:"
ip route | grep -E 'tun|wg|vpn|default' || echo "VPN не обнаружен"
sudo iptables -t nat -L -n | grep -i docker || echo "NAT Docker OK"
cat /etc/docker/daemon.json 2>/dev/null | grep -E 'dns|proxy' || echo "daemon.json без DNS/proxy"

# 3. Тест сети на хосте (PyPI/pip)
echo -e "\n3️⃣ Хост: доступ к PyPI:"
ping -c 3 8.8.8.8 >/dev/null && echo -e "${GREEN}✅ DNS/ping OK${NC}" || echo -e "${RED}❌ Нет интернета${NC}"
curl -s --connect-timeout 5 https://pypi.org/simple/pip/ | head -1 && echo -e "${GREEN}✅ PyPI HTTPS OK${NC}" || echo -e "${RED}❌ PyPI timeout/блок${NC}"
pip ping -v 2>&1 | grep -q "success" && echo -e "${GREEN}✅ pip index OK${NC}" || echo -e "${RED}❌ pip DNS/HTTPS fail${NC}"

# 4. Создать/проверить тестовый контейнер
docker rm -f $CONTAINER 2>/dev/null
docker run -d --name $CONTAINER --network bridge $TEST_IMAGE sleep 3600
sleep 2

# 5. Сеть контейнера
echo -e "\n4️⃣ Контейнер $CONTAINER: сеть:"
docker inspect $CONTAINER --format '{{json .NetworkSettings.Networks}}' | jq . 2>/dev/null || docker inspect $CONTAINER | grep IPAddress

# 6. Тест внутри контейнера
echo -e "\n5️⃣ Внутри контейнера:"
docker exec $CONTAINER sh -c "apt update -qq && apt install -y curl iputils-ping 2>/dev/null || apk add curl bind-tools"
docker exec $CONTAINER ping -c 3 8.8.8.8 && echo -e "${GREEN}✅ ping DNS OK${NC}" || echo -e "${RED}❌ Нет DNS в контейнере${NC}"
docker exec $CONTAINER curl -s --connect-timeout 10 https://pypi.org/simple/pip/ | head -1 && echo -e "${GREEN}✅ PyPI curl OK${NC}" || echo -e "${RED}❌ PyPI timeout в контейнере${NC}"
docker exec $CONTAINER python -c "import urllib.request; print(urllib.request.urlopen('https://pypi.org/simple/pip/', timeout=10).getcode())" 2>/dev/null && echo -e "${GREEN}✅ Python HTTPS OK${NC}" || echo -e "${RED}❌ Python urllib fail${NC}"

# 7. Тест pip install (маленький пакет)
echo -e "\n6️⃣ Pip тест:"
docker exec $CONTAINER pip install --user --no-cache-dir --timeout 30 requests --quiet && echo -e "${GREEN}✅ pip install OK${NC}" || echo -e "${RED}❌ pip install FAIL (сеть/блок)${NC}"

# 8. VS Code extensions тест (если это про них)
echo -e "\n7️⃣ VS Code extensions (marketplace):"
docker exec $CONTAINER curl -s --connect-timeout 10 https://marketplace.visualstudio.com/_apis/public/gallery/publishers/ms-python/vsextensions/python/2024.18.0/vspackage | head -1 && echo -e "${GREEN}✅ MS Python extension OK${NC}" || echo -e "${RED}❌ Marketplace блок (типично РФ/VPN)${NC}"

docker rm -f $CONTAINER
echo -e "\n✅ Диагностика завершена. Логи выше покажут проблему (DNS/PyPI/VPN)."
echo -e "${YELLOW}Фиксы: docker restart + /etc/docker/daemon.json с dns: ['8.8.8.8'], build --network=host или зеркало pip -i https://pypi.tuna.tsinghua.edu.cn/simple/${NC}" [web:22][cite:4][web:11]
