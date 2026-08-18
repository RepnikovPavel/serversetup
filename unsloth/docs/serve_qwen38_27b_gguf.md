# Qwen3.8-27B GGUF: скачать и сервить

Проще всего — один скрипт: `bash ../setup.sh` (качает UD-Q4_K_XL, включает
автозагрузку, создаёт ключ, прогоняет smoke-тест). Ниже — то же самое руками.

Переменные: `CONTAINER=unsloth-studio-cu128`, `PORT=48218`, `KEY=sk-unsloth-...`
(ключ: `connect_agent_to_server.md`, шаг 1).

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

## 3. Проверить

```sh
curl -s http://127.0.0.1:$PORT/v1/models -H "Authorization: Bearer $KEY"
```

```sh
curl -s -X POST http://127.0.0.1:$PORT/v1/chat/completions -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d '{"model":"unsloth/Qwen3.8-27B-GGUF","messages":[{"role":"user","content":"2+2?"}],"max_tokens":32}'
```

Или одной командой всё сразу: `bash ../tests/smoke.sh`
Дальше: `free_gpu.md` (выгрузка), `connect_agent_to_server.md` (доступ с других машин).
