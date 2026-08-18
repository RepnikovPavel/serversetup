# Выгрузка модели из памяти/GPU без перезапуска контейнера

Studio держит модель в subprocess `llama-server` (для GGUF) и умеет его гасить
по API — контейнер перезапускать не нужно.

## 1. Явная выгрузка через API

```sh
curl -s -X POST http://127.0.0.1:<STUDIO_HOST_PORT>/api/inference/unload \
  -H "Authorization: Bearer <API_KEY>" -H "Content-Type: application/json" \
  -d '{"model_path": "<MODEL_ID>"}'
```

(`<MODEL_ID>` — как в `/v1/models`. Ручка существует и как `/v1/unload`.)

Проверка, что VRAM освободилась:

```sh
nvidia-smi --query-gpu=memory.used --format=csv,noheader
```

## 2. Авто-выгрузка по простою (idle TTL)

В настройках Studio есть авто-выгрузка по таймауту простоя
(`auto_unload_idle_seconds`, плюс флаги `auto_unload_keep_kv`, `auto_unload_api_only`).
UI: Settings → Inference. Через API:

```sh
curl -s -X PATCH http://127.0.0.1:<STUDIO_HOST_PORT>/api/settings \
  -H "Authorization: Bearer <API_KEY>" -H "Content-Type: application/json" \
  -d '{"auto_unload_idle_seconds": 600}'
```

## 3. Жёсткий запасной вариант

```sh
# убить только llama-server внутри контейнера (Studio переживёт)
docker exec <CONTAINER> pkill -f llama-server
```

Крайний случай — `docker restart <CONTAINER>`: установка и модели на хостовом
диске, перезапуск занимает секунды.
