# Сервинг-ветка форка unsloth (server-serving)

Дата: 2026-08-20, автор изменений: kimi-code (Moonshot AI).

## Что и где

Форк: `github.com/RepnikovPavel/unsloth`, ветка `server-serving`, основана на
коммите релиза `2026.8.18` (тот код, что ставится из PyPI в контейнер).
Деплой: `UNSLOTH_PACKAGE_SPEC` в `docker-compose.yml` → entrypoint ставит
тарболл поверх PyPI-пакета (`--no-deps`, с сохранением `frontend/dist` и
`oxc-validator/node_modules` — в git-тарболле их нет, без них Studio падает с
"frontend build not found"). Маркер `/data/studio/.unsloth_package_spec`
не даёт переустанавливать на каждый старт.

Изменения ветки:

1. `studio/backend/core/inference/kv_sessions.py` — per-user KV-сессии
   (`UNSLOTH_KV_SESSIONS=1`): при смене API-ключа на единственном слоте KV
   уходящего пользователя сбрасывается через `/slots/0?action=save`, входящего
   — поднимается (`restore`). Имя файла `kvu-<sha256(token|model)[:24]>.bin` в
   `--slot-save-path`. TTL: `UNSLOTH_KV_SESSION_TTL_S` (дефолт 3 суток), протухшие
   удаляются при sweep. Хуки: оба admission-хелпера в `routes/inference.py`
   (все OpenAI/Anthropic-совместимые ручки), flush перед idle-выгрузкой
   (`llama_keepwarm.py`) и перед ручным `/unload`. Любая ошибка save/restore =
   холодный prefill, запрос не падает.
2. `env_serving_load_kwargs` в `utils/openai_auto_switch_settings.py`:
   `UNSLOTH_LLAMA_CTX_SIZE` / `UNSLOTH_LLAMA_N_PARALLEL` / `UNSLOTH_LLAMA_GPU_IDS`
   как дефолты авто-загрузки по API (ниже per-model override). Явный ctx лоадер
   не режет — при нехватке одной GPU пиннит обе (`_select_gpus_split_aware`).
3. Тесты: `studio/backend/tests/test_kv_sessions.py`.

Обновление 2026-08-20 (коммиты `9ad9fe3b4`, `6fe3de414`):

4. **kv_sessions пропускает дисковый своп для гибридных/recurrent моделей**
   (`LlamaCppBackend._hybrid_recurrent()` — по ssm-метаданным GGUF, слоям с
   kv_heads=0 или списку архитектур). Причина — баг апстрима
   [ggml-org/llama.cpp#25913](https://github.com/ggml-org/llama.cpp/issues/25913):
   в save-файл не пишутся context checkpoints, поэтому после `restore` слот
   всегда уходит в полный re-prefill (проверено на живом сервере: restore
   «успешен», но eval идёт по всем 216К токенам). Для таких моделей
   переключение пользователей обслуживает встроенный prompt cache llama-server
   (PR #16391) — он хранит чекпоинты и даёт настоящий cache hit.
5. `UNSLOTH_LLAMA_CACHE_RAM_MIB` → `--cache-ram N` (через
   `parse_cache_ram_env` в `llama_server_args.py`, эмиссия в `load_model` под
   capability `supports_cache_ram`). Дефолт апстрима 8192 МиБ не вмещает сессию
   ~200K токенов (14-19 ГиБ с чекпоинтами) — на сервере ставим 131072.

## Замеры переключения пользователей (`tests/bench_kv_switch.py`)

Сервер: 2× RTX 4090, qwen35-27B UD-Q4_K_XL, ctx 262144, 1 слот. До фикса
(дисковый своп, снапшоты на HDD `/mnt/data1`):

| контекст | warm turn | switch (своп) | overhead | снапшот на юзера |
|---|---|---|---|---|
| ~13.6K токенов | 3.6 c | 6.5 c | ~2.9 c | ~1.05 ГБ |
| ~54K токенов | 13.9 c | 26.7 c | ~12.8 c | ~3.7 ГБ |
| ~216K токенов | 80.5 c | 160.6 c | ~80 c | ~14.4 ГБ |

Ключевое: switch ≈ cold prefill — после restore шёл ПОЛНЫЙ re-prefill всего
контекста (216К токенов ≈ 137 c при ~1580 t/s), т.е. дисковый снапшот не давал
cache hit вообще (баг #25913 выше), а только добавлял save/restore поверх.

После фикса (prompt cache в RAM, проверено на Qwen3.5-0.8B, тот же arch qwen35):
возврат пользователя к диалогу ~3.3K токенов = **6 токенов eval, ~120 мс**
(`found better prompt f_keep=0.999` + restore context checkpoint). Гранулярность
— шаг чекпоинтов (`--checkpoint-min-step`, дефолт 8192 токена): досчёт хвоста
между чекпоинтом и концом диалога, максимум ~8K токенов.

Куда сбрасывается кэш: для чисто-attention моделей — на диск,
`$UNSLOTH_HOST_DIR/studio/cache/llama-slots/kvu-<sha256(api_key|model)[:24]>.bin`
(TTL 3 суток); для гибридных — в RAM llama-server (prompt cache,
`--cache-ram`), переживает смену пользователей, но не перезапуск/выгрузку модели.

## Подводные камни, в которые уже наступлены

- uv кэширует тарболл по URL: обновление той же ветки по тому же URL может
  поставить СТАРЫЙ код. Пин коммита в spec (`archive/<sha>.tar.gz`) или
  `rm /data/studio/.unsloth_package_spec` + restart. В entrypoint добавлен
  `--refresh-package unsloth`, но на commit-pin полагаться надёжнее.
- Переустановка пакета сносит `studio/frontend/dist` (её нет в репо) —
  entrypoint сохраняет/возвращает. Если Studio падает с "frontend build not
  found" — проверить этот шаг.
- llama.cpp из контейнера (prebuilt от Unsloth, build 10472) уже умеет всё
  нужное: `--slot-save-path`, `/slots?action=save|restore`, tensor split.
  Форк llama.cpp менять не потребовалось.
- Снапшот qwen35 (гибрид) был бы ~158 МБ фиксированно (recurrent state) +
  ~65 КБ/токен — но для гибридных дисковый своп отключён (см. выше), кэш живёт
  в RAM (`--cache-ram`). Дисковые kvu-*.bin пишутся только для чисто-attention
  моделей.
- `--parallel 4` раньше резал контекст на слоты (61952/4 ≈ 15.5K на слот) —
  теперь 1 слот × 262144, параллелизм заменён очередью (admission FIFO, без
  таймаута ожидания по умолчанию) + per-user кэшем (RAM для гибридных, диск
  для attention). Ключ каждого пользователя = его сессия: общий ключ = общая
  сессия.
