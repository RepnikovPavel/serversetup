# Unsloth Studio — своя сборка в Docker

## Быстрый старт (один скрипт на сервере)

```sh
git clone https://github.com/RepnikovPavel/serversetup.git && cd serversetup/unsloth
```

```sh
UNSLOTH_HOST_DIR=/mnt/data1/unsloth_default bash setup.sh
```

Скрипт сам: поднимает контейнер, качает модель (`QUANT=UD-Q4_K_XL` по умолчанию),
включает автозагрузку, создаёт API-ключ и прогоняет smoke-тест. Первая установка ~15 мин
+ время скачивания модели.

Сеть с подменой TLS-сертификатов (симптом: `invalid peer certificate: UnknownIssuer`):

```sh
UNSLOTH_HOST_DIR=/mnt/data1/unsloth_default USE_LOCAL_CA=1 HF_HUB_DISABLE_XET=1 bash setup.sh
```

## Подключить агента на другом компьютере

```sh
bash setup.sh client <SERVER_IP> 48218 <API_KEY>
```

## Ручной запуск через compose (если нужно без скрипта)

```sh
UNSLOTH_HOST_DIR=/mnt/data1/unsloth_default CUDA_VARIANT=cu128 STUDIO_HOST_PORT=48218 UNSLOTH_STUDIO_PASSWORD=12345678 HF_TOKEN= docker compose up -d --build
```

```sh
docker compose down   # остановка; переменные не нужны
```

UI: `http://<host>:48218`, логин `unsloth`, пароль из `UNSLOTH_STUDIO_PASSWORD`.
Для RTX 5090: `CUDA_VARIANT=cu130`.

## Дальше

- `docs/serve_qwen38_27b_gguf.md` — кванты и сервинг руками
- `docs/connect_agent_to_server.md` — OpenCode/Aider/Cline, SSH-туннель
- `docs/free_gpu.md` — освободить GPU (`bash free_gpu.sh`)
- `tests/` — `smoke.sh` (ручки и модель), `agents.sh` (реальные агенты)
- `notes/` — заметки разработчика
