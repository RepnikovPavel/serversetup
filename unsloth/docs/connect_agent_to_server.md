# Подключение агента (harness) с локального компьютера к модели на сервере

Модель сервится на сервере Unsloth Studio, который отдаёт OpenAI-совместимый API.
Любой агент, умеющий "OpenAI-compatible provider", подключается одним способом:
указать `baseURL = http://<SERVER_IP>:<STUDIO_HOST_PORT>/v1` и API-ключ.

`<SERVER_IP>` — IP сервера в вашей сети, `<STUDIO_HOST_PORT>` — порт из `STUDIO_HOST_PORT`
(по умолчанию 8000). Не публикуйте реальные значения в общих репозиториях.

## 0. Проверка связности (с локального компьютера)

```sh
curl -s http://<SERVER_IP>:<STUDIO_HOST_PORT>/v1/models -H "Authorization: Bearer <API_KEY>" | head -c 300
```

Проверено: с машины в той же LAN отвечает JSON со списком моделей.

**Как админу выдать ключ коллеге** (UI: Settings → API keys, или однострочником):

```sh
TOKEN=$(curl -s -X POST http://<SERVER_IP>:<STUDIO_HOST_PORT>/api/auth/login -H 'Content-Type: application/json' -d '{"username":"unsloth","password":"<ADMIN_PASSWORD>"}' | python3 -c 'import json,sys;print(json.load(sys.stdin)["access_token"])') && curl -s -X POST http://<SERVER_IP>:<STUDIO_HOST_PORT>/api/auth/api-keys -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"name":"colleague-1"}'
```

Сырой ключ (`sk-unsloth-...`) показывается один раз — сразу передайте коллеге.

**Автозагрузка модели:** если на сервере включён auto-switch (см.
`serve_qwen38_27b_gguf.md`, шаг 2A), агенту достаточно указать имя модели —
явный `/load` не нужен.

## 1. OpenCode

`~/.config/opencode/opencode.json` (глобально) или `opencode.json` в проекте:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "server-studio": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Unsloth Studio (server)",
      "options": { "baseURL": "http://<SERVER_IP>:<STUDIO_HOST_PORT>/v1", "apiKey": "<API_KEY>" },
      "models": {
        "<MODEL_ID>": { "name": "Qwen3.8-27B (server)", "limit": { "context": 32768, "output": 8192 } }
      }
    }
  }
}
```

`<MODEL_ID>` — точное имя из ответа `/v1/models`. Дальше: `opencode` → выбрать модель.

## 2. Aider

```sh
export OPENAI_API_BASE=http://<SERVER_IP>:<STUDIO_HOST_PORT>/v1 OPENAI_API_KEY=<API_KEY> && aider --model openai/<MODEL_ID>
```

## 3. Cline / Continue (VS Code)

Провайдер «OpenAI Compatible»: Base URL `http://<SERVER_IP>:<STUDIO_HOST_PORT>/v1`,
API Key `<API_KEY>`, Model ID `<MODEL_ID>`.

## 4. Если порт сервера недоступен напрямую (фаервол) — SSH-туннель

```sh
ssh -N -L 48218:127.0.0.1:48218 <USER>@<SERVER_IP> &
curl -s http://127.0.0.1:48218/v1/models -H "Authorization: Bearer <API_KEY>" | head -c 300
```

В конфигах агентов тогда `baseURL = http://127.0.0.1:48218/v1`.

## 5. Не-Ubuntu клиенты (Astra Linux и др.)

Astra Linux — Debian-based, всё выше работает без изменений. Минимум на клиенте:

```sh
sudo apt-get install -y curl ca-certificates   # Astra/Debian/Ubuntu одинаково
```

Если корпоративный TLS-инспектор ломает HTTPS на клиенте — импорт CA (Astra/Debian/Ubuntu):

```sh
sudo cp corp-ca.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates
```

Для чистого HTTP внутри LAN (наш случай) CA на клиенте не нужен вовсе.

## 6. Безопасность

- Сервер слушает LAN без TLS — ключ и трафик видны в сети; для недоверенной сети —
  только SSH-туннель (п.4) или reverse-proxy с TLS.
- Один API-ключ на человека, не один на всех: отзыв/ротация проще.
