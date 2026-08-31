# OpenCode CLI + локальная модель на сервере: полный туториал

Туториал по использованию [OpenCode](https://opencode.ai) CLI (тестировано на
версии 1.18.x) в связке с локальной моделью, которую сервит Unsloth Studio
(см. `../serve_qwen38_27b_gguf.md` и `../connect_agent_to_server.md`).

Все примеры рабочие, проверены на живом сервере. Плейсхолдеры:

- `<SERVER_IP>` — IP сервера с моделью, `<PORT>` = 48218;
- `<API_KEY>` — ключ `sk-unsloth-...` (выдаётся на сервере, см. шаг «Делай раз»
  в `../connect_agent_to_server.md`);
- `server/unsloth/Qwen3.8-27B-GGUF` — идентификатор модели в формате
  `провайдер/модель`, который пишет `setup.sh client`.

## 0. Типовая ошибка: `-m` принимает ID модели, а не её отображаемое имя

Так делать **нельзя** — будет `UnknownError`:

```sh
opencode -m "Qwen3.8-27B UD-Q4_K_XL · 17.9 GB · ctx 256K" run "are you here?"
# Error: { "name": "UnknownError", "data": { "message": "Unexpected server error...", "ref": "err_..." } }
```

`"Qwen3.8-27B UD-Q4_K_XL · 17.9 GB · ctx 256K"` — это `name` (красивая подпись
в TUI-пикере), а не идентификатор. Флаг `-m/--model` принимает строго формат
`provider/model`. Правильно:

```sh
opencode run -m "server/unsloth/Qwen3.8-27B-GGUF" "are you here?"
```

Список валидных идентификаторов на вашей машине:

```sh
opencode models            # ищите строку server/unsloth/Qwen3.8-27B-GGUF
```

Если модели нет в списке — клиент не настроен, выполните
`bash setup.sh client <SERVER_IP> 48218 <API_KEY>` (см. `../connect_agent_to_server.md`).

Чтобы не передавать `-m` каждый раз, задайте модель по умолчанию в конфиге
(`~/.config/opencode/opencode.json` — глобально, `./opencode.json` в корне
проекта — per-project):

```json
{
  "model": "server/unsloth/Qwen3.8-27B-GGUF"
}
```

## 1. Подключение (напоминание)

```sh
bash setup.sh client <SERVER_IP> 48218 <API_KEY>
```

Скрипт пишет `~/.config/opencode/opencode.json`: провайдер `server`
(OpenAI-compatible, `http://<SERVER_IP>:48218/v1`), лимиты контекста
(262144/16384) и variants thinking-режима (`off/low/medium/high/xhigh`).
Проверка связи в обход opencode:

```sh
curl -s http://<SERVER_IP>:48218/v1/models -H "Authorization: Bearer <API_KEY>"
```

## 2. Возможности CLI по юзкейсам

### 2.1. Чаттинг через CLI (one-shot запросы)

Простейший запрос без TUI:

```sh
opencode run -m "server/unsloth/Qwen3.8-27B-GGUF" "объясни, что такое KV-кэш, в двух абзацах"
```

Полезные флаги `opencode run`:

| Флаг | Что делает |
|---|---|
| `-m, --model` | модель в формате `provider/model` |
| `--variant` | thinking-режим: `off`, `low`, `medium`, `high`, `xhigh` (мапится в `reasoning_effort` сервера) |
| `--thinking` | показать thinking-блоки в выводе |
| `-f, --file` | приложить файл(ы) к сообщению (можно несколько раз) |
| `--title` | название сессии (удобно для поиска в `session list`) |
| `--format json` | сырой поток JSON-событий вместо форматированного вывода — для парсинга в скриптах |
| `-c, --continue` | продолжить последнюю сессию |
| `-s, --session <id>` | продолжить конкретную сессию |
| `--agent <name>` | агент (см. 2.2) |
| `--auto` | авто-разрешить все действия, кроме явно запрещённых (см. 2.4) |
| `--dir <path>` | рабочий каталог (важно для агентных задач) |

Примеры:

```sh
# быстрый вопрос без thinking (быстрее и дешевле по токенам)
opencode run -m "server/unsloth/Qwen3.8-27B-GGUF" --variant off "2+2?"

# чат про конкретный файл
opencode run -m "server/unsloth/Qwen3.8-27B-GGUF" -f docker-compose.yml "найди проблемы в этом compose-файле"

# машинно-читаемый вывод: каждая строка — JSON-событие (step_start/text/step_finish),
# в step_finish лежит статистика токенов
opencode run -m "server/unsloth/Qwen3.8-27B-GGUF" --format json "скажи PONG" | jq -r 'select(.type=="text") | .part.text'
```

Для интерактивного чата есть полный TUI (`opencode`) и компактный
(`opencode --mini`), но для скриптов и пайплайнов основной инструмент —
`opencode run`.

### 2.2. Агентные задачи через CLI

`opencode run` — это не только чат: по умолчанию работает агент `build`,
который умеет читать/писать файлы, запускать команды и выполнять многошаговые
задачи. Ключевое отличие агентной задачи от чата — модель сама вызывает
инструменты в цикле, пока задача не выполнена.

```sh
cd ~/myproject
opencode run -m "server/unsloth/Qwen3.8-27B-GGUF" \
  "прогони pytest, найди упавший тест и почини его"
```

Встроенные агенты (флаг `--agent`):

- `build` (дефолт) — полный доступ: файлы, bash, всё что разрешено (см. 2.4);
- `plan` — read-only режим: анализ и план без изменений;
- `explore`, `general` — сабагенты для поиска по коду и общих задач;
- свои агенты описываются в конфиге в секции `agent` (см. схему
  https://opencode.ai/config.json).

```sh
# только план, ничего не менять
opencode run -m "server/unsloth/Qwen3.8-27B-GGUF" --agent plan \
  "как безопасно перевести этот проект с pip на uv?"

# запуск в другом каталоге, не меняя текущий
opencode run --dir /path/to/project -m "server/unsloth/Qwen3.8-27B-GGUF" "опиши структуру проекта"
```

Для неинтерактивного запуска агентных задач (CI, крон, скрипты) почти всегда
нужен `--auto` — иначе агент остановится на первом запросе разрешения, а спросить
некому. Подробно про разрешения — в 2.4.

Прогон агента против этого сервера как тест: `tests/agents.sh` в корне `unsloth/`.

### 2.3. Сессии программно

Каждый `opencode run` создаёт сессию (диалог с историей). Сессии хранятся
локально, и ими можно управлять из командной строки — это основа для
многоходовых сценариев в скриптах.

Управление:

```sh
opencode session list                       # все сессии: ID, заголовок, время
opencode session delete <sessionID>         # удалить
opencode export <sessionID> > sess.json     # экспорт в JSON
opencode import sess.json                   # импорт
```

Продолжение диалога:

```sh
opencode run -c "а теперь то же самое, но для продакшена"          # последняя сессия
opencode run -s ses_fa874fad9ffekgsEyIrRQme7Lt "продолжаем"         # конкретная
opencode run -s ses_fa87... --fork "вариант Б"                      # форк: не портить исходную
```

Типовой паттерн «многошаговый диалог из bash-скрипта»: создаём сессию с
известным заголовком, забираем её ID из JSON-событий, затем продолжаем по ID:

```sh
#!/bin/bash
MODEL="server/unsloth/Qwen3.8-27B-GGUF"

# шаг 1: новая сессия, ID берём из первого JSON-события
SID=$(opencode run -m "$MODEL" --variant off --format json --title "deploy-check" \
      "Запомни: мы проверяем деплой. Ответь OK" | \
      head -1 | jq -r .sessionID)

# шаг 2+: продолжаем ту же сессию — модель помнит контекст
opencode run -m "$MODEL" --variant off -s "$SID" "Шаг 1: проверь docker ps"
opencode run -m "$MODEL" --variant off -s "$SID" "Шаг 2: что мы проверяли?"
```

Замечание про серверную сторону: KV-кэш Unsloth Studio привязан к API-ключу,
а не к сессии opencode, поэтому продолжение сессии (`-s`) почти бесплатно по
prefill — пока между запросами не вклинился другой пользователь с тем же
ключом (поэтому один ключ = один человек, см. `../connect_agent_to_server.md`).

### 2.4. Разрешения на файлы и действия программно

OpenCode спрашивает разрешение на потенциально опасные действия (правка файлов,
bash-команды, выход за пределы каталога проекта, веб-запросы). В скриптах и CI
интерактивные вопросы недопустимы — разрешения задаются заранее, двумя способами.

**Способ 1: секция `permission` в конфиге** (`~/.config/opencode/opencode.json`
глобально или `./opencode.json` в проекте). Действия: `ask` (спросить),
`allow` (разрешить молча), `deny` (запретить). Правила применяются по инструментам,
значение может быть строкой-действием или объектом «паттерн → действие»:

```json
{
  "permission": {
    "read": "allow",
    "glob": "allow",
    "grep": "allow",
    "edit": "allow",
    "webfetch": "deny",
    "external_directory": "deny",
    "bash": {
      "git status": "allow",
      "git diff *": "allow",
      "pytest *": "allow",
      "rm *": "deny",
      "*": "ask"
    }
  }
}
```

- `edit` — правка/создание файлов внутри проекта;
- `external_directory` — любой доступ за пределы каталога проекта (чтение и
  запись); `deny` надёжно запирает агента внутри проекта;
- `bash` — паттерны команд: конкретная команда или glob (`*`); `*` — запасное
  правило для всего остального;
- `read`, `glob`, `grep`, `list`, `webfetch`, `websearch`, `task`, `skill`,
  `lsp`, `todowrite`, `question`, `doom_loop` — остальные инструменты.

Разрешения можно переопределить per-agent (секция `agent`):

```json
{
  "agent": {
    "plan":  { "permission": { "edit": "deny", "bash": "deny" } },
    "build": { "permission": { "bash": { "*": "ask" } } }
  }
}
```

**Способ 2: флаг `--auto`** — авто-разрешить всё, что не запрещено явно
(`deny` в конфиге продолжает работать):

```sh
opencode run -m "server/unsloth/Qwen3.8-27B-GGUF" --auto \
  "обнови зависимости и прогони тесты"
```

Безопасный паттерн для CI: `--auto` + явные `deny` в конфиге проекта
(`external_directory`, `webfetch`, опасные bash-паттерны). Так агент не
останавливается на вопросах, но выйти за очерченный периметр не может.

Файлы можно давать агенту и точечно, без прав доступа: флаг `-f/--file`
прикладывает файл прямо в сообщение — агент видит его содержимое, даже если
чтение с диска ограничено.

### 2.5. Headless-режим: opencode как HTTP-сервис

Для интеграции из любого языка opencode умеет поднимать HTTP-сервер:

```sh
opencode serve --port 4096 --hostname 127.0.0.1
```

Дальше — REST API. Создать сессию и отправить сообщение (ответ — JSON с
parts, токенами и метаданными):

```sh
# создать сессию
curl -s -X POST http://127.0.0.1:4096/session \
  -H 'Content-Type: application/json' -d '{"title":"api-demo"}'
# → {"id":"ses_...", ...}

# отправить сообщение в сессию (ответ приходит целиком, когда агент закончил)
curl -s -X POST http://127.0.0.1:4096/session/<SESSION_ID>/message \
  -H 'Content-Type: application/json' -d '{
    "model": {"providerID":"server","modelID":"unsloth/Qwen3.8-27B-GGUF"},
    "variant": "off",
    "parts": [{"type":"text","text":"Reply with exactly: PONG"}]
  }'
```

- список сессий: `GET /session`;
- история сообщений: `GET /session/<ID>/message`;
- подключить TUI к уже работающему серверу: `opencode attach http://127.0.0.1:4096`;
- basic-аутентификация на сервере: флаги `-u/-p` или переменные
  `OPENCODE_SERVER_USERNAME` / `OPENCODE_SERVER_PASSWORD` (у `serve`, `run --attach`,
  `attach`);
- если opencode работает на одной машине, а модель на сервере — схема та же:
  opencode сам ходит на `http://<SERVER_IP>:48218/v1` по конфигу провайдера.

Также `opencode run --attach http://127.0.0.1:4096 ...` выполняет запрос через
уже запущенный сервер вместо поднятия нового инстанса — полезно, когда сервер
держит долгоживущие сессии.

## 3. Troubleshooting

| Симптом | Причина и лечение |
|---|---|
| `UnknownError ... "ref": "err_..."` при `run` | Чаще всего невалидный `-m`: передано отображаемое имя вместо `provider/model`. Проверьте `opencode models`. Детали — в логах: добавьте `--print-logs --log-level DEBUG` |
| Модель не видна в `opencode models` | Клиент не настроен: `bash setup.sh client <SERVER_IP> 48218 <API_KEY>` |
| Таймауты / connection refused | Проверьте `curl http://<SERVER_IP>:48218/v1/models -H "Authorization: Bearer <API_KEY>"`; если порт закрыт — SSH-туннель (`ssh -N -L 48218:127.0.0.1:48218 user@<SERVER_IP>`) и `baseURL http://127.0.0.1:48218/v1` |
| Агент «завис» в скрипте | Ждёт разрешения. Добавьте `--auto` и/или секцию `permission` (см. 2.4) |
| Долгий первый токен после перерыва | KV-кэш другого пользователя вытеснил ваш: один API-ключ на человека |
| Thinking тормозит простые задачи | `--variant off` (или `low`) — см. 2.1 |

## 4. Шпаргалка

```sh
# чат
opencode run -m server/unsloth/Qwen3.8-27B-GGUF "вопрос"
# чат без thinking, json-вывод
opencode run -m server/unsloth/Qwen3.8-27B-GGUF --variant off --format json "вопрос"
# агентная задача в проекте, без интерактива
cd проект && opencode run -m server/unsloth/Qwen3.8-27B-GGUF --auto "почини упавший тест"
# сессии
opencode session list
opencode run -s <ID> "продолжить"
opencode run -c "продолжить последнюю"
# сервис
opencode serve --port 4096 &
opencode attach http://127.0.0.1:4096
```
