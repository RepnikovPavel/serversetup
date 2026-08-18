# Unsloth Studio — своя сборка в Docker

Образ = базовая среда + завендоренный официальный `install.sh`. Сама установка
Studio идёт при первом `up` в `${UNSLOTH_HOST_DIR}/studio` (~10-20 минут,
смотреть `docker compose logs -f`), повторные запуски мгновенные.

## Быстрый старт

```sh
git clone https://github.com/RepnikovPavel/serversetup.git && cd serversetup/unsloth
```

```sh
UNSLOTH_HOST_DIR=/mnt/data1/unsloth_default CUDA_VARIANT=cu128 STUDIO_HOST_PORT=48218 UNSLOTH_STUDIO_PASSWORD=12345678 HF_TOKEN= docker compose up -d --build
```

UI: `http://<host>:48218`, логин `unsloth`, пароль из `UNSLOTH_STUDIO_PASSWORD`.
Для RTX 5090: `CUDA_VARIANT=cu130`. Переустановка: удалить `${UNSLOTH_HOST_DIR}/studio` и снова `up`.

```sh
docker compose down   # остановка; переменные не нужны
```

## Быстрый старт в сети с подменой TLS-сертификатов

Симптом: `invalid peer certificate: UnknownIssuer` в логах установки.

```sh
cp /usr/local/share/ca-certificates/*.crt docker/certs/
```

```sh
UNSLOTH_HOST_DIR=/mnt/data1/unsloth_default CUDA_VARIANT=cu128 STUDIO_HOST_PORT=48218 UNSLOTH_STUDIO_PASSWORD=12345678 HF_TOKEN= HF_HUB_DISABLE_XET=1 docker compose up -d --build
```

## Дальше

- `docs/serve_qwen38_27b_gguf.md` — скачать и сервить модель
- `docs/connect_agent_to_server.md` — подключить агента с другого компьютера
- `docs/free_gpu.md` — выгрузить модель из GPU без рестарта контейнера
- `notes/` — заметки разработчика (как устроено внутри)
