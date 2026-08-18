# Заметки разработчика: TLS-инспекция и HF-загрузки

Здесь — рассуждения и детали. Практические шаги: `../README.md` и `../docs/`.

## TLS-инспекция (подмена сертификатов в сети)

В некоторых сетях TLS-трафик прозрачно расшифровывается: клиенту вместо
сертификата сайта подсовывается сертификат, подписанный локальным CA
(`openssl s_client -connect huggingface.co:443 -servername huggingface.co` —
смотрите `issuer`). В контейнере этого CA нет, поэтому `uv`/pip/curl падают с
`invalid peer certificate: UnknownIssuer`.

Решение в этом репозитории:

- `docker/certs/*.crt` копируются Dockerfile'ом в системное хранилище образа
  (`update-ca-certificates`) до любых сетевых шагов сборки;
- в образе выставлены trust-переменные на системный бандл: `SSL_CERT_FILE`,
  `REQUESTS_CA_BUNDLE`, `CURL_CA_BUNDLE`, `GIT_SSL_CAINFO`, `NODE_EXTRA_CA_CERTS`,
  `PIP_CERT`, `UV_NATIVE_TLS=true` — они безобидны и в обычной сети (указывают на
  дефолтное хранилище);
- `docker/certs/*.crt` в `.gitignore`: в сертификате — имена организации/доменов,
  в публичный репозиторий им не место. Поэтому коллеги должны скопировать CA
  со своего хоста сами (`cp /usr/local/share/ca-certificates/*.crt docker/certs/`).

## HF xet за прокси с подменой TLS

`hf download` по умолчанию использует протокол xet (chunk-dedup). За такой сетью
реконструкция файлов ломается: `File reconstruction error: CAS Client Error:
error decoding response body`. `HF_HUB_DISABLE_XET=1` переключает на обычный
CDN-скачивание — медленнее стартует, но надёжно. Переменная проброшена в compose
и влияет также на загрузки моделей из UI Studio.

## Прочие проверенные нюансы

- `hf` внутри контейнера живёт в venv: `/data/studio/unsloth_studio/bin/hf`;
  голый `hf` через `docker exec` не находится (PATH entrypoint'а не наследуется).
- llama-server из пребилда: `/data/studio/llama.cpp/llama-server`.
- `model_path` вида `repo:QUANT` в `/api/inference/load` уходит в HF-бэкенд и
  падает; указывайте repo id (`unsloth/Qwen3.8-27B-GGUF`) или полный путь к .gguf.
- Автозагрузка (`/api/settings/openai-auto-switch`) сама поднимает модель по
  первому запросу с её именем и выгружает по `auto_unload_idle_seconds`.
- Выгрузка: `POST /api/inference/unload` гасит subprocess llama-server,
  VRAM освобождается полностью, контейнер не трогается.
- Если удалить файл кванта из HF-кэша вручную, реестр моделей Studio остаётся
  старым (chat падает с 500) — после ручной чистки кэша нужен
  `docker restart unsloth-studio-<вариант>`, чтобы реестр пересканировался.
- При нескольких скачанных квантах одной модели Studio может выбрать не тот:
  в `/v1/models` у repo id один квант. Держите по одному кванту на модель.
