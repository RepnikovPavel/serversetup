# Освободить GPU

## 1. На сервере — одной командой, ключи не нужны

```sh
bash free_gpu.sh
```

## 2. Проверить

```sh
nvidia-smi --query-gpu=memory.used --format=csv,noheader
```

## 3. Издалека по API (нужен ключ)

```sh
curl -s -X POST http://<SERVER_IP>:<PORT>/api/inference/unload -H "Authorization: Bearer <API_KEY>" -H "Content-Type: application/json" -d '{"model_path":"unsloth/Qwen3.8-27B-GGUF"}'
```

Автовыгрузка по простою (30 мин) уже включена скриптом `setup.sh`
(`auto_unload_idle_seconds=1800`).
