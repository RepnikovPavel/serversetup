#!/bin/bash

# End-to-end скрипт для установки Docker на Ubuntu/Debian сервер
# Выполните как root или с sudo. Подходит для свежих версий Ubuntu (20.04+).

set -e  # Остановить при ошибке

echo "Обновление пакетов..."
apt-get update

echo "Установка зависимостей..."
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

echo "Добавление GPG-ключа Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "Добавление репозитория Docker..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "Обновление пакетов с Docker..."
apt-get update

echo "Установка Docker Engine..."
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "Запуск и активация сервиса Docker..."
systemctl start docker
systemctl enable docker

echo "Добавление текущего пользователя в группу docker (для запуска без sudo)..."
usermod -aG docker $SUDO_USER || usermod -aG docker $USER

echo "Проверка установки..."
docker --version
docker run hello-world

echo "Готово! Перелогиньтесь для применения группы docker."
echo "Для Docker Compose используйте: docker compose version" [web:1][web:3][web:5]
