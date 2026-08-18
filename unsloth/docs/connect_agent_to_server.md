# Подключить агента к модели на сервере

`<SERVER_IP>` — IP сервера, `<PORT>` — из `STUDIO_HOST_PORT`, `<API_KEY>` — `sk-unsloth-...`.

## 1. Получить API-ключ (админ, один раз на человека)

```sh
TOKEN=$(curl -s -X POST http://<SERVER_IP>:<PORT>/api/auth/login -H 'Content-Type: application/json' -d '{"username":"unsloth","password":"<ADMIN_PASSWORD>"}' | python3 -c 'import json,sys;print(json.load(sys.stdin)["access_token"])') && curl -s -X POST http://<SERVER_IP>:<PORT>/api/auth/api-keys -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"name":"agent-1"}'
```

## 2. Проверить связность с локального компьютера

```sh
curl -s http://<SERVER_IP>:<PORT>/v1/models -H "Authorization: Bearer <API_KEY>"
```

## 3. Подключить harness

OpenCode, `~/.config/opencode/opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "server": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "server",
      "options": { "baseURL": "http://<SERVER_IP>:<PORT>/v1", "apiKey": "<API_KEY>" },
      "models": { "unsloth/Qwen3.8-27B-GGUF": { "name": "Qwen3.8-27B", "limit": { "context": 32768, "output": 8192 } } }
    }
  }
}
```

Aider:

```sh
OPENAI_API_BASE=http://<SERVER_IP>:<PORT>/v1 OPENAI_API_KEY=<API_KEY> aider --model openai/unsloth/Qwen3.8-27B-GGUF
```

Cline / Continue: провайдер «OpenAI Compatible», Base URL `http://<SERVER_IP>:<PORT>/v1`, ключ `<API_KEY>`, модель `unsloth/Qwen3.8-27B-GGUF`.

## 4. Если порт закрыт фаерволом — SSH-туннель

```sh
ssh -N -L <PORT>:127.0.0.1:<PORT> <USER>@<SERVER_IP> &
```

и везде заменить `http://<SERVER_IP>:<PORT>` на `http://127.0.0.1:<PORT>`.

Клиент на Astra Linux: те же команды (Debian-based), нужны только пакеты `curl ca-certificates`.
