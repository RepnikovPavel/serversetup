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
- Снапшот qwen35 (гибрид): ~158 МБ фиксированно (recurrent state) + ~65 КБ/токен.
  50K-токенная сессия ≈ 3.4 ГБ на диске — при TTL 3 суток следить за местом
  (`/mnt/data1` был заполнен на 92%).
- `--parallel 4` раньше резал контекст на слоты (61952/4 ≈ 15.5K на слот) —
  теперь 1 слот × 262144, параллелизм заменён очередью (admission FIFO, без
  таймаута ожидания по умолчанию) + KV-свопом. Ключ каждого пользователя =
  его сессия: общий ключ = общая сессия.
