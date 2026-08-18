# Как Unsloth взаимодействует с llama.cpp: глубокий разбор

Документ отвечает на вопросы:

1. Зачем Unsloth сделали форк llama.cpp и чем он отличается от оригинала?
2. Как Unsloth собирает и устанавливает llama.cpp?
3. Откуда берётся «дополнительный непрозрачный слой»?
4. Можно ли после установки через Unsloth пользоваться llama.cpp привычным способом?
5. Можно ли использовать квантованные Unsloth-модели с оригинальным llama.cpp?
6. Как подключать локальные GGUF-модели Unsloth к harness-утилитам (OpenCode, Aider, Cline, …)?
7. Мультимашинные сценарии: модель на сервере, агенты локально / на второй машине; две ноды для сервинга.

Источники указаны по ходу текста. Локальные ссылки на код (`unsloth/save.py:123` и т.п.) относятся к клону github.com/unslothai/unsloth (master, август 2026).

---

## 0. Краткая карта (TL;DR)

- **Unsloth — это три вещи сразу**: (а) библиотека для файнтюнинга; (б) конвертер HF→GGUF с собственными квант-пресетами; (в) Unsloth Studio — приложение-обёртка, которое качает и запускает `llama-server`.
- **Форк `unslothai/llama.cpp`** существует в основном ради **CI-конвейера пре-билд бинарников** и **раннего доступа к фиксам/новым архитектурам**, которые ещё не влиты в апстрим. Это НЕ отдельный движок: форк = апстрим + упаковка + пины патчей.
- **Непрозрачный слой** — отдельный пакет **`unsloth_zoo`** (репозиторий `unslothai/unsloth-zoo`), куда вынесена реальная механика установки llama.cpp и конвертации в GGUF. В основном репо остаются только обёртки.
- **Привычный llama.cpp после установки Unsloth — да, можно**: бинарники лежат в `~/.unsloth/llama.cpp/`, это обычные `llama-server` / `llama-cli` / `llama-quantize`.
- **GGUF от Unsloth в оригинальном llama.cpp — да, работает** (официально заявлено). Dynamic-кванты (`UD-Q4_K_XL` и т.п.) — это не новые форматы, а смесь стандартных ggml-типов по тензорам.
- **Подключение к любым harness** — через OpenAI-совместимый API `llama-server` (`http://host:port/v1`). Это единая точка интеграции для OpenCode, Aider, Cline, Continue и т.д.
- **Мультимашина**: `llama-server --host 0.0.0.0 --api-key ...` на сервере + `baseURL` в конфиге агента; для двух вычислительных нод — экспериментальный RPC-бэкенд (`ggml-rpc-server`).

---

## 1. Зачем Unsloth форкнули llama.cpp

Репозиторий: https://github.com/unslothai/llama.cpp

### 1.1. Исторические причины

1. **Январь 2025 — динамическая квантизация.** В блоге про DeepSeek-R1 Dynamic 1.58-bit прямо сказано: «We provided our dynamic quantization code as a fork to llama.cpp». Форк изначально был нужен для **создания** квантов, а не для их запуска.
   - https://unsloth.ai/blog/deepseekr1-dynamic
2. **CI-конвейер пре-билдов.** Форк стал источником nightly-сборок llama.cpp под CUDA/ROCm/Vulkan/macOS/Windows/Linux для Unsloth Studio. В релизах форка — манифест `llama-prebuilt-manifest.json` и sha256-чек-суммы; теги вида `b9334`, `b9596-mix-e6f2453`.
   - https://github.com/unslothai/llama.cpp/releases
   - Changelog: «Unsloth now uses constant fresh up to date llama.cpp prebuilts… Added an in-app Update llama.cpp button» — https://unsloth.ai/docs/new/changelog

### 1.2. Чем форк отличается от `ggml-org/llama.cpp`

README форка идентичен апстриму — отличия видны по коммитам и PR. В форке есть механизм **«pins»** (`scripts/unsloth/pr-set.json`, введён в PR #21 форка): nightly-пребилды собираются как «апстримный тег + запиненные коммиты из PR, которых ещё нет в апстриме» (цитата из `_doc` самого pr-set.json: «the tree is the upstream tag + pins»). Проверено на 2026-08-18 по актуальному pr-set.json — запинены:

- `ggml-org#24423` (DiffusionGemma, open) и `ggml-org#25731` (архитектура TML Inkling, open) — апстримные PR, влитые в ночные сборки до мержа в апстрим;
- `unslothai#70` (Kimi-K3: vision tower MoonViT-3d, open);
- `unslothai#91` (экспериментальные квант-типы `IQ1_XS/IQ1_XXS/IQ1_XXXS`, см. ниже);
- `unslothai#95` (семплер: penalties по token id, open).

Про «собственные квант-типы» — точная картина (проверено по коду, см. раздел 9):

- `IQ1_XS/IQ1_XXS/IQ1_XXXS` реализованы в PR #61 (open) и #91 форка; #91 влит **не в master, а в побочную ветку** `iq1-narrow-upstream-base` (2026-08-11), и его коммит запинен в nightly;
- при этом в `ggml.h` **и** апстрима, **и** master форка, **и** релизного тега `b10360-mix-87da1a2` этих типов нет — enum содержит только `IQ1_S`/`IQ1_M`. Т.е. на момент проверки шипнутые пребилды этих типов не содержат (пин либо применился неудачно, либо появился после среза тега);
- главное: **ни одна опубликованная GGUF на huggingface.co/unsloth эти типы не использует** (проверено листингом файлов DeepSeek-V3.1-GGUF, Qwen3-Coder-30B-A3B-Instruct-GGUF, gemma-3-27b-it-GGUF — только стандартные типы).
  - https://github.com/unslothai/llama.cpp/pull/21
  - https://github.com/unslothai/llama.cpp/pull/61
  - https://github.com/unslothai/llama.cpp/pull/91

При этом фиксы Unsloth **идут и в апстрим** (автор danielhanchen): Llama 4 RoPE fix (ggml-org#12889), Llama 4 conversion fix (#14311), Gemma2 `query_pre_attn_scalar` (#8444), «Add Unsloth exporting to GGUF in tools» (#17411).
- https://github.com/ggml-org/llama.cpp/pull/12889
- https://unsloth.ai/blog/dynamic-v2 («We helped resolve issues in llama.cpp»)

### 1.3. Важный нюанс: форк ≠ то, из чего собирают исходники

В локальном репозитории unsloth видно (исследование кода):

- **Prebuilt-бинарники** качаются из релизов **форка**: `studio/install_llama_prebuilt.py:254` — `DEFAULT_PUBLISHED_REPO = "unslothai/llama.cpp"` (апстрим доступен только явным override'ом).
- **Source-сборка по умолчанию идёт из апстрима**: `studio/setup.sh:46` — `_DEFAULT_LLAMA_SOURCE="https://github.com/ggml-org/llama.cpp"` (переопределяется `UNSLOTH_LLAMA_SOURCE`, `UNSLOTH_LLAMA_PR`).
- В библиотечном коде (`unsloth/save.py:1751,2241`) вообще зашиты старые URL `github.com/ggerganov/llama.cpp` (редирект на ggml-org).

**Вывод:** форк — это канал доставки готовых бинарников и «скоростная полоса» для патчей. Движок остаётся апстримным llama.cpp.

---

## 2. Как Unsloth собирает и устанавливает llama.cpp

Есть **два независимых слоя установки**.

### 2.1. Библиотека `unsloth` (при `save_pretrained_gguf`)

Цели сборки — `unsloth/save.py:101-105`:

```python
LLAMA_CPP_TARGETS = ["llama-quantize", "llama-cli", "llama-server"]
```

Алгоритм (реальная механика — в `unsloth_zoo`, см. раздел 3):

1. `check_llama_cpp()` / `install_llama_cpp(gpu_support=False)` — **для экспорта GGUF CUDA не нужна** (комментарий в коде: «GGUF conversion doesn't need CUDA»).
2. Установка идёт в `~/.unsloth/llama.cpp` (переопределяется `UNSLOTH_LLAMA_CPP_PATH`):
   - сначала пробуются **пребиилды из релизов форка** `unslothai/llama.cpp` (GPU/CPU-бандлы, проверка sha256 по манифесту); запасной вариант — официальные CPU-архивы ggml-org; тег пинится через `UNSLOTH_LLAMA_TAG`;
   - иначе — **сборка из исходников**: `git clone https://github.com/ggml-org/llama.cpp`, затем
     ```
     cmake llama.cpp -B llama.cpp/build -DBUILD_SHARED_LIBS=OFF -DGGML_CUDA=OFF ...
     cmake --build llama.cpp/build --config Release -j --target llama-quantize llama-cli llama-server
     ```
     (см. `unsloth/save.py:1459-1773`, cmake-вызов на `:1501`).
3. `_download_convert_hf_to_gguf()` — скачивает **пропатченный Unsloth-конвертер** `unsloth_convert_hf_to_gguf.py` (используется в `save_to_gguf_generic`, `unsloth/save.py:6200`).

Пайплайн экспорта `save_to_gguf` (`unsloth/save.py:1870`):

```
HF-модель → convert_to_gguf (f16/bf16/q8_0, max_shard_size="50GB")
          → quantize_gguf (обёртка над llama-quantize) × каждый метод квантования
```

Поддерживаемые кванты — `unsloth/save.py:147-188`: стандартные `f32/bf16/f16/q8_0/q2_k…q6_k` + imatrix-семейство `iq1_s…iq4_xs` (требуют `imatrix_file`, подтягивается с HF `unsloth/<base>-GGUF`). Публичные API: `unsloth_save_pretrained_gguf` (:4528), `unsloth_push_to_hub_gguf` (:5362). Дополнительно генерируется Ollama `Modelfile` (`create_ollama_modelfile`, :2839).

Ручной путь из официальной доки:
- https://docs.unsloth.ai/basics/saving-models/saving-to-gguf

### 2.2. Unsloth Studio (`studio/`, `unsloth_cli/`)

Studio = FastAPI-бэкенд + React-фронтенд + Tauri. Установка (`studio/setup.sh`, 3379 строк):

- **Приоритет — prebuilt-бандл** из релизов `unslothai/llama.cpp` (`studio/setup.sh:2259+`), установка в `~/.unsloth/llama.cpp` через `install_llama_prebuilt.py --published-repo unslothai/llama.cpp`. После скачивания — smoke-тест `llama-server`/`llama-quantize` на tinyllama `stories260K.gguf`.
- **Fallback — source build** (`setup.sh:2695+`): `git clone --depth 1`, cmake-флаги:
  ```
  -DCMAKE_BUILD_TYPE=Release -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF
  -DLLAMA_BUILD_SERVER=ON -DGGML_NATIVE=ON
  ```
  плюс платформенные: macOS — `-DGGML_METAL=ON`; CUDA — проверка nvcc ≥ 12.4; ROCm/HIP через hipcc. Бэкенд выбирается `UNSLOTH_LLAMA_CPP_BACKEND` (`auto|cpu|cuda|vulkan|hip|rocm`).

Обновление llama.cpp из UI: `studio/backend/routes/llama.py` — `POST /api/llama/update` (атомарная замена бинарника тем же `install_llama_prebuilt.py`).

---

## 3. Откуда берётся «непрозрачный слой»

Это **пакет `unsloth_zoo`** (репозиторий https://github.com/unslothai/unsloth-zoo, зависимость `unsloth_zoo>=2026.8.12` в `pyproject.toml:145`).

В `unsloth/save.py:19-31` прямым текстом:

```python
from unsloth_zoo.llama_cpp import (
    install_llama_cpp, check_llama_cpp, convert_to_gguf,
    quantize_gguf, use_local_gguf, _download_convert_hf_to_gguf, ...
)
```

То есть весь «чёрный ящик» установки/конвертации живёт **в отдельном pip-пакете**, чьих исходников в основном репо нет. Чтобы смотреть реальную логику — открывайте `unsloth_zoo/llama_cpp.py` (он доступен: https://raw.githubusercontent.com/unslothai/unsloth-zoo/main/unsloth_zoo/llama_cpp.py).

Своих ggml/CUDA-ядер для инференса у Unsloth нет. Надстройка поверх llama.cpp — чисто Python:

1. **Кастомный квант-пресет `Q2_K_L`** (`unsloth/save.py:365-443`): это НЕ нативный ftype llama.cpp, а рецепт: `llama-quantize --output-tensor-type q8_0 --token-embedding-type q8_0 <in> <out> q2_k`.
2. **Патч токенизатора в GGUF** (`unsloth/tokenizer_utils.py:438-502`, `fix_sentencepiece_gguf`): переписывает `token_type` NORMAL→CONTROL внутри GGUF, чтобы chat-инференс в llama.cpp работал корректно.
3. **Dynamic-кванты** (`UD-Q4_K_XL` и т.п.): не новые форматы, а **потензорная смесь стандартных ggml-типов** (MoE-эксперты в низкие биты, attention в 4–6 бит). Поэтому их читает любой свежий stock llama.cpp — в `llama.h` апстрима никаких `*_K_XL` типов нет.
4. Патченный конвертер `unsloth_convert_hf_to_gguf.py` (скачивается zoo-пакетом) — исторически из форка; на текущем master форка файла уже нет, фиксы ушли в апстрим.
5. `unsloth/kernels/` — Triton/CUDA-ядра для **тренировки**, к llama.cpp отношения не имеют.

---

## 4. Можно ли после установки через Unsloth пользоваться llama.cpp привычным способом?

**Да.** Бинарники — обычные сборки апстримного llama.cpp (плюс запиненные патчи, см. 1.2). После установки они лежат в:

```
~/.unsloth/llama.cpp/llama-server
~/.unsloth/llama.cpp/llama-cli
~/.unsloth/llama.cpp/llama-quantize
~/.unsloth/llama.cpp/build/bin/...   # при source-сборке
```

Studio ищет их именно в таком порядке (`studio/backend/core/inference/llama_cpp.py:4814-4827`): `~/.unsloth/llama.cpp/llama-server` → `.../build/bin/llama-server` → `./llama.cpp/...` → `$PATH`.

Используйте как обычно:

```bash
~/.unsloth/llama.cpp/llama-server -m model.gguf -c 16384 --port 8080
~/.unsloth/llama.cpp/llama-cli -m model.gguf -p "Hello"
```

Обратная совместимость тоже есть: **Studio работает с любыми GGUF из любых папок** (changelog: «Added custom folders so you can use any GGUFs in any folder»), т.е. обычные модели с Hugging Face/LM Studio работают через бинарники форка.

Единственные оговорки:

- экспериментальные квант-типы `IQ1_XS/IQ1_XXS/IQ1_XXXS` живут в отдельной ветке форка и пинах nightly (см. 1.2 и 9): в master форка и в текущих пребилдах их нет, опубликованные модели их не используют. Но если вы **сами** квантуете модель этими типами на сборке с патчем — такой GGUF стоковый llama.cpp не прочитает;
- для новых архитектур форк обновляется раньше апстрима — при переходе на свой llama.cpp следите за свежестью версии.

---

## 5. Квантованные модели Unsloth + оригинальный llama.cpp

**Да, официально поддерживается.**

- Доки про Dynamic 2.0: «You can run the 2.0 GGUFs on most inference engines like llama.cpp, Unsloth Studio etc.» — https://unsloth.ai/docs/basics/unsloth-dynamic-2.0-ggufs
- Туториал Llama 4: «Unsloth imatrix quants are fully compatible with popular inference engines like llama.cpp & Open WebUI» — и инструкция клонирует именно `ggml-org/llama.cpp`. — https://unsloth.ai/docs/models/tutorials/llama-4-how-to-run-and-fine-tune

Техническая причина — UD-кванты это смесь стандартных типов (см. 3.3).

**Оговорки:**

1. **Нужен свежий llama.cpp** («Obtain the latest llama.cpp»). Минимальные версии нигде не зафиксированы — правило простое: чем новее, тем лучше, особенно для свежих архитектур (Gemma 4, Qwen3-VL и т.п.).
2. **`--jinja` обязателен** для chat-шаблонов Unsloth-квантов (карточки моделей: «You must use --jinja for llama.cpp quants»). В свежих версиях llama.cpp `--jinja` включён по умолчанию. Известный quirk: с `--jinja` llama-server может дописывать системное сообщение про JSON/tool_call, что ломает файнтюны — обход: `--no-jinja` (но тогда нет tool calling). Апстрим-issue: https://github.com/ggml-org/llama.cpp/issues/18323
3. **BOS-ловушка:** llama.cpp сам добавляет `<bos>` — второй в промпт добавлять нельзя; проверяйте eos-токен (иначе бесконечная генерация); chat template должен совпадать с тем, что был при обучении.
   - https://docs.unsloth.ai/basics/gemma-3-how-to-run-and-fine-tune

Запуск напрямую с Hugging Face:

```bash
llama-server -hf unsloth/Qwen3.6-27B-GGUF:UD-Q4_K_XL --ctx-size 16384 --port 8001
```

Типовые флаги из документации Unsloth:

```bash
llama-server -m model.gguf \
  --threads -1 --n-gpu-layers 999 --ctx-size 16384 \
  --port 8001 --jinja --min-p 0.01 --prio 3
```

Полезные приёмы:

- **MoE-offload** (Qwen3-Coder и др.): `-ot ".ffn_.*_exps.=CPU"` выгружает экспертов на CPU; рекомендуемый сэмплинг `--temp 0.7 --top-p 0.8 --top-k 20 --min-p 0.0 --repeat-penalty 1.05`.
- **KV-кэш** для длинного контекста: `--cache-type-k q8_0` (квантование V-кэша требует сборки с `-DGGML_CUDA_FA_ALL_QUANTS=ON` + `--flash-attn`).
- Формула оффлоада: `n_offload = VRAM/Filesize × n_layers − 4`.
- `--parallel 2` для параллельных слотов, `--no-cache-prompt` если prompt caching мешает.
- Источники: https://docs.unsloth.ai/basics/qwen3-coder , https://unsloth.ai/blog/deepseekr1-dynamic

Ollama тоже поддерживается: `ollama run hf.co/unsloth/gemma-3-27b-it-GGUF:Q4_K_XL`, локальный GGUF — через Modelfile (Unsloth генерирует его автоматически при `save_pretrained_gguf`); разрезанные GGUF перед этим мерджить: `llama-gguf-split --merge`.
- https://unsloth.ai/docs/integrations/connections/ollama

---

## 6. Подключение моделей к harness-утилитам (OpenCode и др.)

### 6.1. Ключевая идея

`llama-server` предоставляет **OpenAI-совместимый HTTP API**:

- `POST /v1/chat/completions`, `POST /v1/completions`, `GET /v1/models`, `POST /v1/embeddings`, `POST /v1/responses`
- плюс Anthropic-совместимый `POST /v1/messages`
- официальная дока: https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md

Поэтому **любая** утилита, умеющая в «OpenAI-compatible provider», подключается одним и тем же способом: указать `baseURL = http://<host>:<port>/v1` и любой/заданный apiKey. Имя модели должно совпадать с ответом `GET /v1/models` (или `--alias` при запуске).

### 6.2. OpenCode

В официальных доках есть отдельный раздел именно про llama.cpp — https://opencode.ai/docs/providers/

`~/.config/opencode/opencode.json` (или проектный `opencode.json`, он приоритетнее):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "llama.cpp": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "llama-server (local)",
      "options": { "baseURL": "http://127.0.0.1:8080/v1" },
      "models": {
        "qwen3-coder:a3b": {
          "name": "Qwen3-Coder: a3b-30b (local)",
          "limit": { "context": 128000, "output": 65536 }
        }
      }
    }
  }
}
```

Нюансы:

- npm-пакет `@ai-sdk/openai-compatible` — для `/v1/chat/completions`; для `/v1/responses` — `@ai-sdk/openai`.
- `limit.context`/`limit.output` задаются вручную (models.dev для кастомных провайдеров недоступен).
- `apiKey` можно не писать в конфиг: `/connect` → Other → ключ сохранится в `~/.local/share/opencode/auth.json`. Поддерживаются подстановки `{env:VAR}` и `{file:path}`.

### 6.3. Другие harness-утилиты

- **Aider**: `export OPENAI_API_BASE=http://<host>:8080/v1 OPENAI_API_KEY=sk-no-key-required`, затем `aider --model openai/<model>` (префикс `openai/` обязателен). https://aider.chat/docs/llms/openai-compat.html
- **Continue.dev**: в `config.yaml` — `provider: openai`, `apiBase: http://<host>:8080/v1`, `apiKey`, `model`. https://docs.continue.dev/customize/model-providers/top-level/openai
- **Cline**: провайдер «OpenAI Compatible», поля Base URL / API Key / Model ID. https://docs.cline.bot/provider-config/openai-compatible
- **Claude Code**: `ANTHROPIC_BASE_URL=http://<host>:8080` + `ANTHROPIC_AUTH_TOKEN` — работает, потому что llama-server имеет Anthropic-совместимый `/v1/messages`. https://code.claude.com/docs/en/env-vars
- **Kimi Code CLI**: endpoint задаётся в `~/.kimi/config.toml` полем `base_url` провайдера (тип `openai_legacy` для Chat Completions). https://moonshotai.github.io/kimi-cli/en/configuration/providers.html

### 6.4. Путь «через Unsloth»

Unsloth CLI сам поднимает такой сервер:

```bash
unsloth run --model unsloth/...-GGUF:UD-Q4_K_XL   # алиас `unsloth studio run`
unsloth start                                     # coding-agent против работающего сервера
```

Бэкенд Studio монтирует OpenAI-совместимый роутер на `/v1` (`studio/backend/main.py:1359`): `/v1/chat/completions`, `/v1/completions`, `/v1/embeddings`, `/v1/responses`, `/v1/models`, `/v1/messages` (Anthropic-стиль). Внутри это **прокси на subprocess `llama-server`** (`LlamaCppBackend`, `studio/backend/core/inference/llama_cpp.py:3648`): Studio формирует argv llama-server, запускает его через `subprocess.Popen` и проксирует httpx-запросы на `http://127.0.0.1:<port>/v1/chat/completions`. Ключи вида `sk-unsloth-…`.

То есть даже в «родном» пути Unsloth финальная точка интеграции та же — OpenAI API поверх llama-server. Studio добавляет сверху управление моделями, скачивание, UI и политику безопасности (см. 7.2).

---

## 7. Мультимашинные сценарии

### 7.1. Модель на сервере, агенты локально

Это штатный режим llama-server, ничего Unsloth-специфичного:

**На сервере:**

```bash
llama-server -m model.gguf \
  --host 0.0.0.0 --port 8080 \
  --n-gpu-layers 999 --ctx-size 32768 \
  --api-key "your-secret-key"
```

По умолчанию сервер слушает `127.0.0.1` — для внешнего доступа `--host 0.0.0.0` обязателен (так и сделано в официальном Docker-примере: `docker run -p 8080:8080 ghcr.io/ggml-org/llama.cpp:server --host 0.0.0.0 ...`).

**На машине с агентом** — тот же конфиг, что в разделе 6, но с адресом сервера:

```json
"options": { "baseURL": "http://192.168.1.10:8080/v1", "apiKey": "your-secret-key" }
```

### 7.2. Безопасность (важно, из официального SECURITY.md)

- Единственная встроенная auth — `--api-key` / `--api-key-file` (bearer). `/health` ключ не требует.
- Официальное предупреждение: **не выставлять `llama-server` и RPC в недоверенную сеть** — https://github.com/ggml-org/llama.cpp/blob/master/SECURITY.md
- Официальная матрица: Public → «set an API key, put the server behind a reverse proxy»; LAN → `--cors-origins`; localhost → `--cors-origins localhost`.
- TLS встроенный требует пересборки с `-DLLAMA_OPENSSL=ON` + `--ssl-key-file/--ssl-cert-file`. Практичнее — **nginx reverse proxy с TLS** (так советуют мейнтейнеры, issue #2194) или **SSH-туннель**:

```bash
# с локальной машины — безопасно, сервер остаётся на 127.0.0.1
ssh -L 8080:127.0.0.1:8080 user@server
# агент ходит на http://127.0.0.1:8080/v1
```

- У Unsloth Studio своя защита: server tools включены по умолчанию только при bind на `127.0.0.1`; на `0.0.0.0` — выключены (утечка ключа = RCE). https://unsloth.ai/docs/basics/api

### 7.3. Агенты на второй машине

Ничем не отличается: схема «один сервер с llama-server → N клиентов» работает из коробки. Каждый агент (на любой машине) просто указывает `baseURL` сервера. Параллельные клиенты обслуживаются слотами — увеличьте `--parallel N` (каждый слот делит контекст: эффективный контекст = `ctx-size / parallel`).

### 7.4. Две вычислительные ноды для сервинга одной модели (RPC)

В llama.cpp есть **RPC-бэкенд** для распределённого инференса (тензоры/слои одной модели раскладываются по нескольким машинам):

- **Статус: НЕ deprecated**, но официально «proof-of-concept development stage… fragile and insecure».
- Добавлен в 2024 (PR #6829), с мая 2025 переехал из `examples/rpc` в `tools/rpc`, бинарь переименован `rpc-server` → **`ggml-rpc-server`**, протокол v3.0.0.
- Дока: https://github.com/ggml-org/llama.cpp/blob/master/tools/rpc/README.md

Схема:

```bash
# на каждой worker-ноде (сборка с -DGGML_RPC=ON):
ggml-rpc-server --host 0.0.0.0 --port 50052

# на главной ноде:
llama-server -m model.gguf --rpc worker1:50052,worker2:50052 \
  --n-gpu-layers 999 --port 8080 --host 0.0.0.0
```

Недавно добавлен RDMA-транспорт (RoCEv2) — для быстрых interconnect'ов. Разработка активна (коммиты в `ggml/src/ggml-rpc` идут и в 2026).

**Практические оговорки:**

- RPC делит **вычисления**, но сетевые задержки между нодами критичны — имеет смысл только на быстрой локальной сети/RDMA. Для типичного сценария «одна нода с GPU» RPC не нужен.
- Не путать с мультимашинным **доступом** (7.1): RPC — это про раскладку одной модели на несколько машин, а не про подключение клиентов.
- Альтернативы для high-throughput: **vLLM** (`vllm serve unsloth/... --tensor-parallel-size N`) — Unsloth рекомендует сохранять файнтюн для vLLM в 16-bit (`save_pretrained_merged(..., save_method="merged_16bit")`); GGUF-кванты позиционируются именно для llama.cpp/Ollama. https://unsloth.ai/docs/basics/inference-and-deployment/vllm-guide

---

## 8. Итоговые рецепты

### 8.1. «Хочу просто запустить GGUF от Unsloth своим llama.cpp»

```bash
git clone https://github.com/ggml-org/llama.cpp
cmake llama.cpp -B llama.cpp/build -DBUILD_SHARED_LIBS=OFF -DGGML_CUDA=ON
cmake --build llama.cpp/build --config Release -j --target llama-server llama-cli
./llama.cpp/build/bin/llama-server -hf unsloth/Qwen3.6-27B-GGUF:UD-Q4_K_XL \
  --ctx-size 16384 --port 8080
```

### 8.2. «Сервер с моделью + OpenCode на локальной машине»

Сервер: `llama-server -m model.gguf --host 0.0.0.0 --port 8080 --api-key KEY` (за nginx/TLS или через SSH-туннель).
Локально в `opencode.json`: провайдер с `npm: "@ai-sdk/openai-compatible"`, `baseURL: "http://<server>:8080/v1"`, `apiKey: KEY`.

### 8.3. «Две GPU-ноды под одну большую модель»

`ggml-rpc-server` на обеих + `llama-server --rpc node1:50052,node2:50052` на главной; клиенты подключаются к главной ноде обычным OpenAI API.

---

## 9. Проверка фактов: разбор кажущегося противоречия про квант-типы

**Кажущееся противоречие:** «у Unsloth свои типы квантизации» и одновременно «их GGUF работают на стоковом llama.cpp». Оба утверждения верны, потому что относятся к **разным артефактам**. Проверка по первоисточникам (2026-08-18):

1. **В апстриме этих типов нет.** Enum в `ggml/include/ggml.h` master-ветки `ggml-org/llama.cpp`: `GGML_TYPE_IQ1_S = 19`, `GGML_TYPE_IQ1_M = 29` — и всё, никаких `IQ1_XS/XXS/XXXS` (`GGML_TYPE_COUNT = 43`).

2. **В master форка их тоже нет** — `ggml.h` форка идентичен апстриму в этой части. Реализация живёт в PR #61 (open) и #91 (merged 2026-08-11, но **в побочную ветку** `iq1-narrow-upstream-base`, не в master): ~30 файлов, включая `ggml-quants.c`, CUDA-шаблоны `mmq-instance-iq1_xs.cu` и т.д.

3. **В текущих пребилдах их (пока) нет.** Релизный тег `b10360-mix-87da1a2` (2026-08-11) содержит пин коммита из #91 в `scripts/unsloth/pr-set.json`, но `ggml.h` по этому тегу типов не содержит. Т.е. код есть в ветке и в пине, а в фактически шипнутых бинарниках на момент проверки — нет.

4. **Опубликованные модели их не используют.** Листинг файлов HF-репозиториев `unsloth/DeepSeek-V3.1-GGUF`, `unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF`, `unsloth/gemma-3-27b-it-GGUF`: только стандартные типы (`IQ1_M, IQ1_S, IQ2_XXS, IQ3_XXS, IQ4_XS, Q2_K…Q8_0, *_K_XL, Q2_K_L, TQ1_0, F16/BF16/F32`). `Q4_K_XL`, `Q2_K_L` и прочие суффиксы — это **именование рецептов** (какие тензоры в какой стандартный тип), а не новые форматы.

**Итог:** «свои квант-типы» — это экспериментальная разработка в форке (суб-1-бит ниже IQ1_S); «работает на стоковом llama.cpp» — про реально публикуемые GGUF, которые собраны из стандартных типов. Противоречия нет, но формулировка «у них свой тип квантизации» без уточнений вводит в заблуждение.

Команды для самостоятельной проверки:

```bash
# enum типов в апстриме / форке / релизном теге
curl -s https://raw.githubusercontent.com/ggml-org/llama.cpp/master/ggml/include/ggml.h | grep -n "IQ1"
curl -s https://raw.githubusercontent.com/unslothai/llama.cpp/master/ggml/include/ggml.h | grep -n "IQ1"
curl -s https://raw.githubusercontent.com/unslothai/llama.cpp/b10360-mix-87da1a2/ggml/include/ggml.h | grep -n "IQ1"

# что реально запинено в ночные сборки
curl -s https://raw.githubusercontent.com/unslothai/llama.cpp/master/scripts/unsloth/pr-set.json

# типы в именах опубликованных GGUF
curl -s "https://huggingface.co/api/models/unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF" \
  | python3 -c "import json,sys; print('\n'.join(sorted(f['rfilename'] for f in json.load(sys.stdin)['siblings'] if f['rfilename'].endswith('.gguf'))))"
```

### Прочие перепроверенные утверждения

| Утверждение | Статус | Источник |
|---|---|---|
| `llama-server` имеет Anthropic-совместимый `POST /v1/messages` | подтверждено | tools/server/README.md, строка 1563 |
| `--jinja` включён по умолчанию | подтверждено | tools/server/README.md: «(default: enabled)» |
| `--api-key` — единственная встроенная auth | подтверждено | tools/server/README.md, SECURITY.md |
| RPC-бэкенд жив, бинарь `ggml-rpc-server`, статус PoC | подтверждено | tools/rpc/README.md: «proof-of-concept development stage» |
| Форк = «апстримный тег + пины», master форка отстаёт от апстрима | подтверждено | compare API: ahead 158 / behind 897; `_doc` в pr-set.json |
| Prebuilt-релизы форка выходят ежедневно, теги `bNNNNN-mix-<sha>` | подтверждено | API релизов, 5 релизов за 4 дня |

Оговорка про «форк = апстрим + упаковка»: формально diff форка с апстримом затрагивает 223 не-CI файла, но это в основном следствие **отставания** master форка от апстрима (behind 897), а не форк-патчей — реальные изменения форка это CI-воркфлоу пребилдов, `scripts/unsloth/*` и пины.

---

## Приложение: ключевые источники

- Форк: https://github.com/unslothai/llama.cpp (+ релизы, PR #21 pins, PR #61 кванты)
- Апстрим: https://github.com/ggml-org/llama.cpp (tools/server/README.md, tools/rpc/README.md, SECURITY.md)
- Unsloth docs: https://docs.unsloth.ai/basics/saving-models/saving-to-gguf , https://unsloth.ai/docs/basics/inference-and-deployment/llama-server-and-openai-endpoint , https://unsloth.ai/docs/integrations/connections
- Unsloth blog: https://unsloth.ai/blog/deepseekr1-dynamic , https://unsloth.ai/blog/dynamic-v2
- OpenCode: https://opencode.ai/docs/providers/ , https://opencode.ai/docs/config/
- Aider: https://aider.chat/docs/llms/openai-compat.html
- Локальный код: `unsloth/save.py`, `unsloth/tokenizer_utils.py`, `studio/install_llama_prebuilt.py`, `studio/setup.sh`, `studio/backend/core/inference/llama_cpp.py`, `unsloth_cli/commands/studio.py`
