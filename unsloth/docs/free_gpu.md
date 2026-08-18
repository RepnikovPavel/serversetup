# Освободить GPU без рестарта контейнера

## 1. Выгрузить модель

```sh
curl -s -X POST http://127.0.0.1:<PORT>/api/inference/unload -H "Authorization: Bearer <API_KEY>" -H "Content-Type: application/json" -d '{"model_path":"unsloth/Qwen3.8-27B-GGUF"}'
```

## 2. Проверить VRAM

```sh
nvidia-smi --query-gpu=memory.used --format=csv,noheader
```

## 3. Если не помогло

```sh
docker exec unsloth-studio-cu128 pkill -f llama-server
```

Автовыгрузка по простою: `serve_qwen38_27b_gguf.md`, шаг 2 (`auto_unload_idle_seconds`).
