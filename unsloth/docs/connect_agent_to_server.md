# Подключить агента к модели на сервере

`<SERVER_IP>` — IP сервера, `<PORT>` = 48218 (из `STUDIO_HOST_PORT`), `<API_KEY>` = `sk-unsloth-...`.

## Делай раз — получить API-ключ (на сервере, один раз на человека)

```sh
TOKEN=$(curl -s -X POST http://127.0.0.1:48218/api/auth/login -H 'Content-Type: application/json' -d '{"username":"unsloth","password":"<ADMIN_PASSWORD>"}' | python3 -c 'import json,sys;print(json.load(sys.stdin)["access_token"])')
```

```sh
curl -s -X POST http://127.0.0.1:48218/api/auth/api-keys -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"name":"agent-1"}'
```

Из ответа скопировать поле `key` (показывается один раз) — это `<API_KEY>` коллеги.

## Делай два — на машине агента

```sh
bash setup.sh client <SERVER_IP> 48218 <API_KEY>
```

Скрипт проверит связь и запишет конфиг OpenCode. Дальше просто `opencode`.

## Делай три — если harness другой

Aider:

```sh
OPENAI_API_BASE=http://<SERVER_IP>:48218/v1 OPENAI_API_KEY=<API_KEY> aider --model openai/unsloth/Qwen3.8-27B-GGUF
```

Cline / Continue: провайдер «OpenAI Compatible», Base URL `http://<SERVER_IP>:48218/v1`, ключ `<API_KEY>`, модель `unsloth/Qwen3.8-27B-GGUF`.

## Если порт закрыт фаерволом — SSH-туннель

```sh
ssh -N -L 48218:127.0.0.1:48218 <USER>@<SERVER_IP> &
```

и везде заменить `http://<SERVER_IP>:48218` на `http://127.0.0.1:48218`.

Клиент на Astra Linux: те же команды (Debian-based), нужны только пакеты `curl ca-certificates`.

## Проверка агентов (реальный прогон)

```sh
SERVER=http://<SERVER_IP>:48218 API_KEY=<API_KEY> bash tests/agents.sh
```
