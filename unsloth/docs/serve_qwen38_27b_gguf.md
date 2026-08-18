# Сервинг Qwen3.8-27B (GGUF, Unsloth) — компактная инструкция

Проверено на живом стенде 2026-08-18 (kimi-code). Предусловие: стек поднят
(`../README.md`), контейнер `<CONTAINER>` (`unsloth-studio-cu128` или `-cu130`) работает,
Studio отвечает на `http://<SERVER_IP>:<STUDIO_HOST_PORT>`. Команды однострочные,
в порядке выполнения. Все `docker exec` — с сервера.

Переменные, используемые ниже:

```sh
CONTAINER=unsloth-studio-cu128; PORT=<STUDIO_HOST_PORT>; KEY=<API_KEY>   # подставить свои
```

## 1. Скачать модель (ровно один квант за раз)

HF-CLI внутри контейнера живёт в venv Studio: `/data/studio/unsloth_studio/bin/hf`
(голый `hf` в `docker exec` не найдётся — PATH entrypoint'а туда не пробрасывается).
Качать в фоне, ~16 ГБ для Q4_K_M:

```sh
docker exec $CONTAINER /data/studio/unsloth_studio/bin/hf download unsloth/Qwen3.8-27B-GGUF --include "*Q4_K_M*"
```

За корпоративным TLS-инспектором добавьте `-e HF_HUB_DISABLE_XET=1` к `docker exec`
(иначе xet падает с `File reconstruction error: CAS Client Error`; для загрузок из UI
Studio та же переменная выставляется в compose, см. `../.env.example`):

Другие кванты (по возрастанию веса/качества; точные размеры — на странице репозитория):

```sh
docker exec $CONTAINER /data/studio/unsloth_studio/bin/hf download unsloth/Qwen3.8-27B-GGUF --include "*Q2_K_XL*"   # минимум VRAM, заметная потеря качества
docker exec $CONTAINER /data/studio/unsloth_studio/bin/hf download unsloth/Qwen3.8-27B-GGUF --include "*IQ3_XXS*"   # очень компактно, рискованно
docker exec $CONTAINER /data/studio/unsloth_studio/bin/hf download unsloth/Qwen3.8-27B-GGUF --include "*Q4_K_XL*"   # dynamic-квант Unsloth, лучше Q4_K_M
docker exec $CONTAINER /data/studio/unsloth_studio/bin/hf download unsloth/Qwen3.8-27B-GGUF --include "*Q5_K_M*"    # баланс
docker exec $CONTAINER /data/studio/unsloth_studio/bin/hf download unsloth/Qwen3.8-27B-GGUF --include "*Q6_K*"      # почти без потерь, ~22 ГБ
docker exec $CONTAINER /data/studio/unsloth_studio/bin/hf download unsloth/Qwen3.8-27B-GGUF --include "*Q8_0*"      # ~28 ГБ, нужны обе GPU
```

Для 2×24 GB (4090): комфортно Q4_K_M / Q4_K_XL / Q5_K_M; Q6_K — впритык с контекстом;
Q8_0 — llama-server сам разложит на обе GPU.

## 2. Запустить сервинг

Вариант A (рекомендовано для агентов) — **auto-switch**: один раз включить, дальше
модель подгружается сама по первому запросу с её именем:

```sh
curl -s -X PUT http://127.0.0.1:$PORT/api/settings/openai-auto-switch -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d '{"enabled":true,"auto_unload_idle_seconds":1800,"auto_download_model":false}'
```

Вариант B — явная загрузка через API (model id = repo id HF; квант берётся из скачанного):

```sh
curl -s -X POST http://127.0.0.1:$PORT/api/inference/load -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d '{"model_path":"unsloth/Qwen3.8-27B-GGUF"}'
```

(Проверенный нюанс: синтаксис `repo:QUANT` в `model_path` уходит в HF-бэкенд и падает —
указывайте либо repo id, либо полный путь к .gguf файлу в `/data/hf_cache/hub/...`.)

Вариант C — UI: `http://<SERVER_IP>:<STUDIO_HOST_PORT>` → выбрать модель → Serve.

Вариант D — голый llama-server (без Studio, OpenAI API на :8080, бинарь собран командой Unsloth):

```sh
MODEL=$(docker exec $CONTAINER sh -c 'ls /data/hf_cache/hub/models--unsloth--Qwen3.8-27B-GGUF/snapshots/*/*Q4_K_M*.gguf' | head -1) && docker exec -d $CONTAINER /data/studio/llama.cpp/llama-server -m "$MODEL" --host 0.0.0.0 --port 8080 --n-gpu-layers 999 --ctx-size 32768 --flash-attn on --api-key <LLAMA_KEY>
```

## 3. Проверить

```sh
curl -s http://127.0.0.1:$PORT/v1/models -H "Authorization: Bearer $KEY" | head -c 300
curl -s -X POST http://127.0.0.1:$PORT/v1/chat/completions -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d '{"model":"unsloth/Qwen3.8-27B-GGUF","messages":[{"role":"user","content":"2+2?"}],"max_tokens":32}'
```

## 4. Освободить GPU

См. `free_gpu.md`: `POST /api/inference/unload` или idle-TTL из шага 2A
(проверено: VRAM падает до нуля, контейнер не перезапускается).
