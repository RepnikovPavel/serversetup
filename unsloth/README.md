# Unsloth Studio — своя сборка в Docker

Свой образ Unsloth Studio через официальный `install.sh` (https://unsloth.ai/install.sh),
без использования готового образа `unsloth/unsloth`. Контейнер privileged, внутри root —
проблем с sudo у установщика нет.

## Структура

```
unsloth/
├── docker-compose.yml      # запуск, пути пробрасываются переменными при up
├── .env.example            # шаблон переменных (скопировать в .env)
├── docker/
│   ├── Dockerfile.cu128    # RTX 4090, CUDA 12.8, torch cu128
│   ├── Dockerfile.cu130    # RTX 5090 (Blackwell), CUDA 13, torch cu130
│   ├── install.sh          # заvendorенный официальный установщик Unsloth Studio
│   └── entrypoint.sh       # запуск `unsloth studio -H 0.0.0.0 -p 8000`
└── README.md
```

`install.sh` лежит в репо намеренно: unsloth.ai недоступен из части сетей (IPv6-only DNS),
плюс сборка воспроизводима. Обновить до свежей версии:
`curl -fsSL https://unsloth.ai/install.sh -o docker/install.sh` и пересобрать образ.

## Быстрый старт

```sh
cd unsloth

# путь до данных на хосте передаётся аргументом в момент запуска
UNSLOTH_HOST_DIR=/mnt/data1/unsloth docker compose up -d --build

# под 5090 / CUDA 13:
UNSLOTH_HOST_DIR=/mnt/hdd1/unsloth_default CUDA_VARIANT=cu130 UNSLOTH_STUDIO_PASSWORD=12345678 STUDIO_HOST_PORT=48218 HF_TOKEN=... docker compose up -d --build
```

После запуска Studio доступна на `http://<host>:${STUDIO_HOST_PORT:-8000}`.
Логин `unsloth`, пароль при первом старте — из `UNSLOTH_STUDIO_PASSWORD` (по умолчанию `12345678`,
Studio требует минимум 8 символов).
Смена пароля: в настройках UI или `docker exec <container> unsloth studio reset-password` (сгенерирует случайный).

Либо один раз заполнить `.env` (см. `.env.example`) и запускать просто `docker compose up -d --build`.

## Что куда монтируется

Внутрь контейнера пробрасывается `${UNSLOTH_HOST_DIR}`:

| Хост                            | Контейнер         | Назначение                          |
|---------------------------------|-------------------|-------------------------------------|
| `${UNSLOTH_HOST_DIR}/studio`    | `/data/studio`    | сама установка Studio (venv, torch, llama.cpp) |
| `${UNSLOTH_HOST_DIR}/uv_cache`  | `/data/uv_cache`  | кэш uv для переустановок/обновлений |
| `${UNSLOTH_HOST_DIR}/hf_cache`  | `/data/hf_cache`  | HF-кэш моделей (`HF_HOME`)          |
| `${UNSLOTH_HOST_DIR}/work`      | `/data/work`      | датасеты, чекпоинты, экспорты       |

Образ содержит только базовую среду (CUDA, python, uv) и установщик.
**Установка Studio происходит при первом `up`** в смонтированный `studio/` на хостовом
диске (занимает ~10-20 минут, видно в `docker compose logs -f`), повторные запуски — мгновенные.
Переустановка/обновление: удалить `${UNSLOTH_HOST_DIR}/studio` и перезапустить,
либо `docker exec <container> unsloth studio update`.

## Корпоративная сеть с TLS-инспекцией (SSL inspection)

Симптом: на домашней машине ставится, на рабочей — нет; в логах
(`docker compose logs -f`) при установке torch/моделей:

```
error: Failed to fetch: `https://download.pytorch.org/whl/cu128/...`
Caused by: invalid peer certificate: UnknownIssuer
```

Причина: корпоративный прокси подменяет TLS-сертификаты, а в образе нет
корневого CA вашей сети. Решение (один раз):

```sh
# 1. скопировать корпоративный CA с хоста в проект (имена файлов произвольные, *.crt)
cp /usr/local/share/ca-certificates/*.crt unsloth/docker/certs/
# 2. пересобрать и поднять как обычно
UNSLOTH_HOST_DIR=/mnt/data1/unsloth docker compose up -d --build
```

Подробности: `docker/certs/README.md`. Файлы `*.crt` в этой папке не коммитятся
(в .gitignore) — в них имена вашей организации.

## Важные детали

- **Пин torch:** на этапе `docker build` GPU недоступен, авто-детект CUDA в install.sh
  подменяется явно через `UNSLOTH_TORCH_INDEX_FAMILY` (cu128 / cu130) в соответствующем Dockerfile.
- **Новый вариант GPU/CUDA:** скопировать `docker/Dockerfile.cuXXX`, поменять базовый
  `FROM nvidia/cuda:...` и `UNSLOTH_TORCH_INDEX_FAMILY`, собрать с `CUDA_VARIANT=cuXXX`.
- **Без torch** (только запуск GGUF, образ заметно легче): добавить `UNSLOTH_NO_TORCH=1`
  в команду install.sh внутри Dockerfile.
- **HF_TOKEN** нужен только для gated-моделей; публичные GGUF качаются без него.
- Скачать модель без GUI: `docker exec unsloth-studio-cu128 hf download <repo> --include "<фильтр>"` —
  Studio подхватит её из общего кэша автоматически.
