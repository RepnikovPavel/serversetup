# Unsloth Studio — своя сборка в Docker

## Быстрый старт (один скрипт на сервере)

```sh
git clone https://github.com/RepnikovPavel/serversetup.git && cd serversetup/unsloth
```

```sh
UNSLOTH_HOST_DIR=/mnt/data1/unsloth_default bash setup.sh
```

Скрипт сам: поднимает контейнер, качает модель (`QUANT=UD-Q4_K_XL` по умолчанию),
включает автозагрузку (idle-unload 300 c), создаёт API-ключ и прогоняет
smoke-тест. Первая установка ~15 мин + время скачивания модели.

Если на целевой машине нет доступа к github.com — скопируйте папку `unsloth/`
любым способом (`rsync -a unsloth/ user@host:serversetup/unsloth/`, scp, флешка):
сборке нужны только файлы этой папки, плюс доступ машины к Docker Hub, PyPI и
huggingface.co.

## Переменные setup.sh (все необязательные)

| Переменная | Дефолт | Зачем |
|---|---|---|
| `UNSLOTH_HOST_DIR` | `/mnt/data1/unsloth_default` | Куда на хосте складывать venv, кэши моделей и чекпоинты. **Берите быстрый NVMe** (на сервере без отдельного data-диска — каталог на системном NVMe, напр. `/home/user/unsloth_default`). |
| `CUDA_VARIANT` | авто (по GPU) | `cu128` = Ada (RTX 40xx), `cu130` = Blackwell (RTX 50xx). Без значения `setup.sh` сам выбирает по compute capability (`nvidia-smi`); при ручном `docker compose up` задавайте явно. Должен быть Dockerfile.`$CUDA_VARIANT` в `docker/`. |
| `STUDIO_HOST_PORT` | `48218` | Порт Studio на хосте. У двух инстансов на одной машине — разные порты. |
| `MODEL_REPO` / `QUANT` | `unsloth/Qwen3.8-27B-GGUF` / `UD-Q4_K_XL` | Какую модель качать. |
| `UNSLOTH_LLAMA_CTX_SIZE` | `262144` | Контекст. На слабой GPU ставьте меньше (напр. 65536), иначе не влезет в VRAM. |
| `UNSLOTH_IDLE_UNLOAD_S` | `300` | Выгрузка модели по простою, секунд. |
| `UNSLOTH_STUDIO_PASSWORD` | `12345678` | Пароль админа Studio при первом старте (мин. 8 символов). |
| `HF_TOKEN` | пусто | Для gated-моделей. |

## Сетевые сетапы

- **Обычная LAN** (дом/офис без фильтрации): команды выше как есть.
- **Сеть с подменой TLS-сертификатов** (симптом: `invalid peer certificate: UnknownIssuer`):

  ```sh
  UNSLOTH_HOST_DIR=/mnt/data1/unsloth_default USE_LOCAL_CA=1 HF_HUB_DISABLE_XET=1 bash setup.sh
  ```
- **Порт закрыт фаерволом** — SSH-туннель, см. `docs/connect_agent_to_server.md`.

## Подключить агента на другом компьютере

```sh
bash setup.sh client <SERVER_IP> 48218 <API_KEY>
```

## Два инстанса: сервер + локалка (host vs server в OpenCode)

На сервере — Q4_K_XL, на локальной машине — та же Qwen3.8-27B, но в самом
компактном кванте и с KV q4_0: UD-IQ2_XXS (7.3 ГБ) + KV q4_0 (~2.3 ГБ) + буферы
≈ 10.8 ГБ — влезает в RTX 4070 Ti 12 ГБ с полным контекстом 256K (хватает на
файл ~213K токенов). У локального инстанса другой порт, свой каталог на NVMe:

```sh
# локалка (пример: RTX 4070 Ti 12 ГБ, cu128, порт 48219, диск /mnt/nvme)
UNSLOTH_HOST_DIR=/mnt/nvme/unsloth_local CUDA_VARIANT=cu128 STUDIO_HOST_PORT=48219 \
QUANT=UD-IQ2_XXS bash setup.sh

# KV q4_0 (без этого 256K не влезет в 12 ГБ) + перезагрузка модели:
KEY=$(cat out/agent_api_key)
curl -s -X PUT http://127.0.0.1:48219/api/settings/openai-auto-switch/overrides \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"model_id":"unsloth/Qwen3.8-27B-GGUF","kv_cache_dtype":"q4_0"}'
curl -s -X POST http://127.0.0.1:48219/api/inference/unload \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"model_path":"unsloth/Qwen3.8-27B-GGUF"}'
```

Затем на машине с OpenCode регистрируем ОБА провайдера (порядок не важен, конфиги
не затирают друг друга — у каждого свой ключ `provider`; id модели одинаковый,
различаются именно провайдеры):

```sh
bash setup.sh client <SERVER_IP> 48218 <SERVER_KEY> "<DISPLAY_СЕРВЕРА>"     # provider "server"
PROVIDER=host bash setup.sh client 127.0.0.1 48219 <HOST_KEY> "<DISPLAY_ЛОКАЛКИ>"  # provider "host"
```

В пикере моделей OpenCode они видны как `server/…` и `host/…` с говорящими
именами (квант, объём, контекст). Скрипт пишет в существующий
`~/.config/opencode/opencode.json` или `opencode.jsonc` (комментарии сохраняться
не обязаны, провайдеры не перетираются).

## Ручной запуск через compose (если нужно без скрипта)

```sh
UNSLOTH_HOST_DIR=/mnt/data1/unsloth_default CUDA_VARIANT=cu128 STUDIO_HOST_PORT=48218 UNSLOTH_STUDIO_PASSWORD=12345678 HF_TOKEN= docker compose up -d --build
```

```sh
docker compose down   # остановка; переменные не нужны
```

UI: `http://<host>:48218`, логин `unsloth`, пароль из `UNSLOTH_STUDIO_PASSWORD`.

## Сервинг для агентов (по умолчанию включён)

Пакет unsloth ставится из ветки `server-serving` форка
[RepnikovPavel/unsloth](https://github.com/RepnikovPavel/unsloth) (переменная
`UNSLOTH_PACKAGE_SPEC` в compose; пусто = стоковый PyPI). Что это даёт:

- полный контекст 256K (`UNSLOTH_LLAMA_CTX_SIZE=262144`), модель закрепляет
  обе GPU, а не влезает в одну с урезанным контекстом;
- один слот (`UNSLOTH_LLAMA_N_PARALLEL=1`): контекст не режется между
  пользователями, запросы ждут в FIFO-очереди;
- per-user KV-кэш по API-ключам со снапшотами на диск, TTL 3 суток
  (`UNSLOTH_KV_SESSIONS=1`, `UNSLOTH_KV_SESSION_TTL_S=259200`);
- thinking-режим модели: дефолт при загрузке `UNSLOTH_LLAMA_REASONING_EFFORT`
  (none|low|medium|high|xhigh), на лету — per-request `reasoning_effort`
  (в OpenCode — variants в пикере модели, см. `docs/connect_agent_to_server.md`).

Подробности: `docs/serve_qwen38_27b_gguf.md`.

## OpenCode CLI: чат, агенты, сессии, разрешения

Кратко по юзкейсам CLI (полный туториал — `docs/opencodecli/README.md`):

- **чаттинг**: `opencode run -m server/unsloth/Qwen3.8-27B-GGUF "вопрос"`
  (`--variant off` выключает thinking, `--format json` — для скриптов,
  `-f file` — приложить файл);
- **агентные задачи**: тот же `run` в каталоге проекта — агент `build` сам
  правит файлы и запускает команды; `--agent plan` — read-only; `--auto` —
  без интерактивных вопросов (для CI);
- **сессии программно**: `opencode session list/delete`, продолжение
  `run -c` / `run -s <ID>` / `--fork`, экспорт `opencode export <ID>`;
- **разрешения программно**: секция `permission` в `opencode.json`
  (`allow`/`ask`/`deny` по инструментам и паттернам bash-команд,
  `external_directory` запирает агента в проекте) + флаг `--auto`;
- **headless**: `opencode serve --port 4096` поднимает HTTP API
  (`POST /session`, `POST /session/<ID>/message`), TUI подключается через
  `opencode attach`.

Важно: `-m` принимает ID модели `provider/model` (см. `opencode models`),
а не её отображаемое имя — иначе `UnknownError`.

## Дальше

- `docs/serve_qwen38_27b_gguf.md` — кванты и сервинг руками
- `docs/connect_agent_to_server.md` — OpenCode/Aider/Cline, SSH-туннель
- `docs/vscode_autocomplete.md` — автодополнение в VSCode (почему не llama.vscode,
  mortar/Continue через `/v1/completions` с FIM-шаблоном)
- `docs/opencodecli/README.md` — туториал по OpenCode CLI: чат, агентные
  задачи, сессии и разрешения программно, headless HTTP API
- `docs/free_gpu.md` — освободить GPU (`bash free_gpu.sh`)
- `tests/` — `smoke.sh` (ручки и модель), `agents.sh` (реальные агенты),
  `bench_kv_switch.py` (цена переключения KV между пользователями)
- `notes/` — заметки разработчика (в т.ч. `host_driver_update.md` — что делать,
  когда на хосте обновили NVIDIA-драйвер без ребута и новые GPU-контейнеры не стартуют)
