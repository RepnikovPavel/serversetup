#!/bin/bash
# Автоматическая end2end настройка NVIDIA Container Toolkit для Docker (Ubuntu/Debian)

set -e  # Остановка при ошибке

echo "=== Проверка NVIDIA драйверов ==="
nvidia-smi || { echo "❌ NVIDIA драйверы не работают! Установите сначала."; exit 1; }

echo "=== Установка NVIDIA Container Toolkit ==="
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit

echo "=== Настройка Docker runtime ==="
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# echo "=== Тест GPU в Docker ==="
# docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi

echo "✅ NVIDIA Container Toolkit настроен! Используйте --gpus all в docker run."
echo "💡 Добавьте себя в группу docker (перелогиньтесь после): sudo usermod -aG docker $USER"
