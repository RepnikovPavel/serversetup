# Подключить агента к модели на сервере

`<SERVER_IP>` — IP сервера, `<PORT>` = 48218 (из `STUDIO_HOST_PORT`), `<API_KEY>` = `sk-unsloth-...`.

Важно: KV-кэш на сервере per-user, а пользователь = API-ключ. Каждому человеку —
свой ключ (шаг 1), не делите один ключ на всех, иначе чужие сессии будут
вытеснять друг друга из кэша.

## Делай раз — получить API-ключ (на сервере, один раз на человека)

`<ADMIN_PASSWORD>` — пароль админа Studio, который задавали при первом запуске
через `UNSLOTH_STUDIO_PASSWORD` (в этом репо дефолт `12345678`). Если сервер
поднимали по README без изменений — это `12345678`. Пароль не знаете —
сбросьте (на сервере):

```sh
docker exec -it unsloth-studio-cu128 /data/studio/unsloth_studio/bin/unsloth studio reset-password
```

Логинимся и получаем токен. Команда специально сделана «громкой»: при неверном
пароле она печатает ответ сервера, а не молчаливый traceback:

```sh
TOKEN=$(curl -s -X POST http://127.0.0.1:48218/api/auth/login -H 'Content-Type: application/json' -d '{"username":"unsloth","password":"<ADMIN_PASSWORD>"}' | python3 -c 'import json,sys; r=json.load(sys.stdin); t=r.get("access_token"); t or sys.exit("ЛОГИН НЕ УДАЛСЯ: %s" % r.get("detail", r)); print(t)')
```

Если увидели `ЛОГИН НЕ УДАЛСЯ: Incorrect password...` — пароль неверный
(частая опечатка: `123456789` вместо `12345678`), см. сброс выше.

```sh
curl -s -X POST http://127.0.0.1:48218/api/auth/api-keys -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"name":"agent-1"}'
```

Из ответа скопировать поле `key` (показывается один раз) — это `<API_KEY>` коллеги.

## Делай два — на машине агента

```sh
bash setup.sh client <SERVER_IP> 48218 <API_KEY> "<DISPLAY_NAME>"
```

`<DISPLAY_NAME>` — имя модели в UI агента с квантом и объёмом весов, например
`"Qwen3.8-27B UD-Q4_K_XL · 17.9 GB · ctx 256K"`; готовую команду сервер печатает
в конце `setup.sh` (и лежит в `out/model_display_name`). Необязательный аргумент.

Скрипт проверит связь и запишет конфиг OpenCode (лимиты: context 262144,
output 16384 — полный нативный контекст модели). Дальше просто `opencode`.

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
