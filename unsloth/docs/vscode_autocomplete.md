# VSCode: автодополнение кода через Unsloth Studio

## Про llama.vscode (важно)

Расширение `llama.vscode` для inline-автодополнения ходит на эндпоинт `/infill`
(FIM) напрямую в llama-server. Unsloth Studio его **не проксирует** (POST
`/infill` → 405), поэтому llama.vscode со Studio-стеком работает только
частично (чат-панель — да, через `/v1/chat/completions`; ghost-text
автодополнение — нет).

Рабочие варианты автодополнения через Studio:

- **mortar** ([github.com/khimaros/mortar](https://github.com/khimaros/mortar)) —
  использует `/infill`, а при его отсутствии **откатывается на OpenAI-style
  completions** — с нашим стеком работает из коробки;
- **Continue** — tab-autocomplete через OpenAI-compatible провайдера
  (`/v1/completions` с FIM-шаблоном, см. ниже).

Studio отдаёт «сырой» `/v1/completions` (проверено), а токены FIM
(`<|fim_prefix|>`, `<|fim_suffix|>`, `<|fim_middle|>`) в токенизаторе
Qwen3.8-27B есть — значит FIM собирается вручную прямо в prompt.

## Проверка FIM через /v1/completions

```sh
curl -s -X POST http://127.0.0.1:48219/v1/completions \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"model":"unsloth/Qwen3.8-27B-GGUF",
       "prompt":"<|fim_prefix|>def add(a, b):\n<|fim_suffix|>\n    return c<|fim_middle|>",
       "max_tokens":16}'
```

## Continue (config.yaml, фрагмент)

```yaml
models:
  - name: Qwen3.8-27B FIM (host)
    provider: openai
    apiBase: http://127.0.0.1:48219/v1
    apiKey: <HOST_KEY>
    model: unsloth/Qwen3.8-27B-GGUF
    roles: [autocomplete]
    promptTemplates:
      autocomplete: "<|fim_prefix|>{{{prefix}}}<|fim_suffix|>{{{suffix}}}<|fim_middle|>"
```

## Замечания

- Автодополнение дёргает модель часто — на локалке с idle-unload 300 c первое
  дополнение после простоя ждёт авто-поднятия (27B грузится ~1-2 мин с NVMe).
  Если это мешает, увеличьте `UNSLOTH_IDLE_UNLOAD_S` на локальном инстансе.
- Длинный файл (~213K токенов) целиком в prompt автодополнения не отправляйте —
  расширения шлют окно вокруг курсора; полный контекст 256K нужен для чата/
  агентов, и он на обоих инстансах есть.
