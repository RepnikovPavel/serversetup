#!/bin/bash

# Путь к Dockerfile
DOCKERFILE_PATH=docker/DockerFileCu130

# Имя образа
IMAGE_NAME=cuda130

echo "Собираем Docker-образ $IMAGE_NAME из $DOCKERFILE_PATH..."

docker build --progress=plain -f $DOCKERFILE_PATH -t $IMAGE_NAME .

if [ $? -eq 0 ]; then
    echo "Сборка завершена успешно."
else
    echo "Ошибка при сборке образа."
fi
