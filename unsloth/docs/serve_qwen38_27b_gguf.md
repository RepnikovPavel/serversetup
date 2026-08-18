# Qwen3.8-27B GGUF: скачать и сервить

Переменные: `CONTAINER=unsloth-studio-cu128`, `PORT=48218`, `KEY=sk-unsloth-...`
(как получить ключ — `connect_agent_to_server.md`, шаг 1).

## 1. Скачать один квант

```sh
docker exec -e HF_HUB_DISABLE_XET=1 $CONTAINER /data/studio/unsloth_studio/bin/hf download unsloth/Qwen3.8-27B-GGUF --include "*Q4_K_M*"
```

Другой квант — заменить фильтр (вес ↑ = качество ↑; для 2×24 ГБ берите Q4_K_M / Q4_K_XL / Q5_K_M):

`"*Q2_K_XL*"` `"*IQ3_XXS*"` `"*Q4_K_M*"` `"*Q4_K_XL*"` `"*Q5_K_M*"` `"*Q6_K*"` `"*Q8_0*"`

## 2. Включить автозагрузку модели по первому запросу (один раз)

```sh
curl -s -X PUT http://127.0.0.1:$PORT/api/settings/openai-auto-switch -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d '{"enabled":true,"auto_unload_idle_seconds":1800}'
```

## 3. Проверить

```sh
curl -s http://127.0.0.1:$PORT/v1/models -H "Authorization: Bearer $KEY"
```

```sh
curl -s -X POST http://127.0.0.1:$PORT/v1/chat/completions -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d '{"model":"unsloth/Qwen3.8-27B-GGUF","messages":[{"role":"user","content":"2+2?"}],"max_tokens":32}'
```

Дальше: `free_gpu.md` (выгрузка), `connect_agent_to_server.md` (доступ с других машин).
