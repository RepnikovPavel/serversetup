# Unsloth Studio — debug-инференс (deepbench)

Запуск **патченого llama-server** (форк [RepnikovPavel/llama.cpp](https://github.com/RepnikovPavel/llama.cpp),
ветка `deepbench`) поверх той же модели, что использует stock `unsloth/` —
без изменения рабочей установки Studio.

Патч добавляет (всё выключено по умолчанию, включается env-переменными):

- `LLAMA_DEBUG_OP_COUNT=1` — подсчёт операций (mults/adds/other) по типам ggml-операций и бэкендам (CPU/CUDA0/CUDA1)
- `LLAMA_DEBUG_EXPERT_TRACE=/path/trace.jsonl` — трассировка MoE-роутинга (какие эксперты выбраны на каждом слое на каждый токен)
- `GET /debug/stats`, `POST /debug/stats/reset` — чтение/сброс счётчиков

Сбор статистики и расчёт вычислительной эффективности — репозиторий
[RepnikovPavel/deepseekbench](https://github.com/RepnikovPavel/deepseekbench) (`bench/`).

## Структура

```
unsloth_debug/
├── build.sh   # сборка патченого llama-server в docker (CUDA, sm_89)
├── run.sh     # запуск debug llama-server (останавливает stock Studio!)
├── stop.sh    # остановка debug-сервера
└── README.md
```

## Переменные (build.sh и run.sh)

| Переменная | Default | Назначение |
|---|---|---|
| `LLAMA_FORK_DIR` | `~/deepbench/llama.cpp` | локальный клон форка (ветка deepbench) |
| `BUILD_HOST_DIR` | `/mnt/data1/deepbench/build` | куда собирать (не на root-разделе — он маленький) |
| `RUN_HOST_DIR` | `/mnt/data1/deepbench/run` | логи и trace.jsonl |
| `UNSLOTH_HOST_DIR` | `/mnt/data1/unsloth` | hf_cache с моделями (как у stock) |
| `DEBUG_IMAGE` | `unsloth-studio-custom:cu128` | образ с nvcc (собирается в `unsloth/`) |
| `DEBUG_PORT` | `18222` | хост-порт debug llama-server |
| `MODEL_GGUF` | см. run.sh | путь к первому шарду GGUF внутри контейнера |

## Порядок действий

```sh
# 1. клон форка (один раз)
mkdir -p ~/deepbench && cd ~/deepbench
git clone --depth 1 --branch deepbench https://github.com/RepnikovPavel/llama.cpp.git

# 2. сборка (10-30 мин, в контейнере с nvcc; root-раздел не трогаем)
cd serversetup/unsloth_debug
./build.sh

# 3. запуск (ВНИМАНИЕ: останавливает контейнер unsloth-studio-cu128 — GPU одни)
./run.sh        # модель грузится ~2 мин, лог: $RUN_HOST_DIR/server.log

# 4. бенчмарк и сбор статистики (см. deepseekbench/README.md)
SERVER=http://127.0.0.1:18222 bench/run_benchmark.sh
python3 bench/collect.py --server http://127.0.0.1:18222 ...

# 5. вернуть stock Studio
./stop.sh && docker start unsloth-studio-cu128
```

## Почему отдельно от Studio

Studio сама поднимает llama-server со своими флагами (`--fit on` и т.д.) и
перезапускает его при падении — для отладки это мешает. Здесь llama-server
запускается напрямую с явными флагами, а env `LLAMA_DEBUG_*` пробрасываются
в контейнер. Stock-установка (`/data/studio`) не модифицируется вообще.
