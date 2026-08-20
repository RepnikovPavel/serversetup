# Qwen3.8-27B GGUF: скачать и сервить

Проще всего — один скрипт: `bash ../setup.sh` (качает UD-Q4_K_XL, включает
автозагрузку, создаёт ключ, прогоняет smoke-тест). Ниже — то же самое руками.

Переменные: `CONTAINER=unsloth-studio-cu128`, `PORT=48218`, `KEY=sk-unsloth-...`
(ключ: `connect_agent_to_server.md`, шаг 1).

## Как сервится модель (после фиксов 2026-08-20)

Пакет unsloth ставится из ветки `server-serving` форка
`github.com/RepnikovPavel/unsloth` (compose-переменная `UNSLOTH_PACKAGE_SPEC`).
Обновление пакета на работающем сервере: впинить коммит в spec
(`.../archive/<sha>.tar.gz`) — uv кэширует тарболл по URL — либо
`docker exec unsloth-studio-cu128 rm /data/studio/.unsloth_package_spec` и
рестарт контейнера. Поведение авто-загрузки по API задаётся env в `docker-compose.yml`:

- `UNSLOTH_LLAMA_CTX_SIZE=262144` — полный нативный контекст 256K. Явный контекст
  лоадер не урезает под VRAM одной карты: не хватает — закрепляет обе GPU
  (раньше молча влезало в GPU0 с контекстом ~62K).
- `UNSLOTH_LLAMA_N_PARALLEL=1` — один слот на весь контекст. Параллельных слотов
  нет, поэтому контекст НЕ делится между пользователями: запросы разных
  пользователей встают во встроенную FIFO-очередь admission.
- `UNSLOTH_LLAMA_GPU_IDS=` — пул GPU; пусто = все видимые.
- `UNSLOTH_KV_SESSIONS=1`, `UNSLOTH_KV_SESSION_TTL_S=259200` — per-user KV-кэш:
  когда слот переходит к другому API-ключу, KV предыдущего пользователя
  сбрасывается на диск (`cache/llama-slots/kvu-*.bin`), а снапшот нового —
  поднимается. Снапшоты живут 3 суток, протухшие удаляются. Один пользователь =
  один API-ключ: выдавайте каждому свой ключ (шаг 1 в
  `connect_agent_to_server.md`). Один и тот же пользователь подряд — без
  save/restore, накладных расходов нет.

Про 1M контекст: нативно модель держит 262144. YaRN-расширение до 1M
(`-c 1048576` + rope-scaling) на 2×24 ГБ не влезает в VRAM (KV ~84 ГБ в f16)
и уйдёт в CPU-offload с сильной просадкой скорости — поэтому по умолчанию
сервится 256K. Если очень надо: `UNSLOTH_LLAMA_CTX_SIZE=1048576` плюс
`llama_extra_args` с YaRN через per-model override
(`/api/settings/openai-auto-switch/overrides`) — на свой страх и риск.

Про CPU-инстанс: замерено на этом сервере (2× Xeon Gold 5218R, 40 потоков,
`-ngl 0`) — генерация **1.9 t/s** при пороге полезности 10 t/s. CPU-инстанс
не поднимаем: он только отнимет RAM-каналы у GPU-инференса.

## 1. Скачать квант (рекомендация Unsloth — UD-Q4_K_XL)

```sh
docker exec -e HF_HUB_DISABLE_XET=1 $CONTAINER /data/studio/unsloth_studio/bin/hf download unsloth/Qwen3.8-27B-GGUF --include "*UD-Q4_K_XL*"
```

UD-кванты — динамические, их и рекомендует Unsloth Studio (вес ↑ = качество ↑):

`"*UD-Q3_K_XL*"` `"*UD-Q4_K_XL*"` `"*UD-Q5_K_XL*"` `"*UD-Q6_K_XL*"` `"*UD-Q8_K_XL*"`
экстремально компактные: `"*UD-IQ2_XXS*"` `"*UD-IQ3_XXS*"`
классика (совместимость со старым llama.cpp): `"*Q4_K_M*"` `"*Q5_K_M*"` `"*Q6_K*"` `"*Q8_0*"`

Для 2×24 ГБ: UD-Q4_K_XL или UD-Q5_K_XL.

## 2. Включить автозагрузку модели по первому запросу (один раз)

```sh
curl -s -X PUT http://127.0.0.1:$PORT/api/settings/openai-auto-switch -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d '{"enabled":true,"auto_unload_idle_seconds":1800}'
```

Перед выгрузкой по idle KV активного пользователя сбрасывается в его снапшот —
после авто-поднятия модели кэш восстановится.

## 3. Проверить

```sh
curl -s http://127.0.0.1:$PORT/v1/models -H "Authorization: Bearer $KEY"
```

```sh
curl -s -X POST http://127.0.0.1:$PORT/v1/chat/completions -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d '{"model":"unsloth/Qwen3.8-27B-GGUF","messages":[{"role":"user","content":"2+2?"}],"max_tokens":32}'
```

Или одной командой всё сразу: `bash ../tests/smoke.sh` (проверяет в т.ч. что
контекст = 262144; с `CHECK_GPU=1` — что заняты обе GPU).
Дальше: `free_gpu.md` (выгрузка), `connect_agent_to_server.md` (доступ с других машин).
