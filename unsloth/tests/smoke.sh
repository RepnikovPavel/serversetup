#!/usr/bin/env bash
# tests/smoke.sh — базовая проверка стенда. Запускать на сервере или с любой машины.
#
#   bash tests/smoke.sh                                   # локально на сервере
#   SERVER=http://192.168.x.x:48218 bash tests/smoke.sh   # с другой машины
#
# Ключ берётся из out/agent_api_key (если есть) или из API_KEY=...
set -uo pipefail
cd "$(dirname "$0")/.."

SERVER="${SERVER:-http://127.0.0.1:48218}"
PASSWORD="${UNSLOTH_STUDIO_PASSWORD:-12345678}"
MODEL="${MODEL_REPO:-unsloth/Qwen3.8-27B-GGUF}"
KEY="${API_KEY:-$(cat out/agent_api_key 2>/dev/null || true)}"
FAIL=0
t() { if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; FAIL=1; fi; }

t "1. Studio отвечает ($SERVER)" \
  "curl -fsS -o /dev/null --max-time 10 $SERVER/"

t "2. логин админа работает" \
  "curl -fsS -X POST $SERVER/api/auth/login -H 'Content-Type: application/json' -d '{\"username\":\"unsloth\",\"password\":\"$PASSWORD\"}' --max-time 10 | grep -q access_token"

t "3. /v1/models отдаёт модель по ключу" \
  "curl -fsS $SERVER/v1/models -H 'Authorization: Bearer $KEY' --max-time 10 | grep -q '$MODEL'"

t "4. модель отвечает на chat completion" \
  "curl -fsS -X POST $SERVER/v1/chat/completions -H 'Authorization: Bearer $KEY' -H 'Content-Type: application/json' --max-time 900 -d '{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"2+2? одной цифрой\"}],\"max_tokens\":256,\"chat_template_kwargs\":{\"enable_thinking\":false}}' | grep -q '\"content\"'"

# Серверный контекст после фиксов — полный нативный (262144), не порезанный под слоты.
EXPECT_CTX="${EXPECT_CTX:-262144}"
t "5. серверный контекст = $EXPECT_CTX" \
  "curl -fsS $SERVER/api/inference/status -H 'Authorization: Bearer $KEY' --max-time 30 | grep -qE '\"(context_length|n_ctx|ctx)\": ?$EXPECT_CTX'"

if [ "${CHECK_GPU:-0}" = "1" ]; then
  t "6. модель занимает ОБЕ GPU" \
    "[ \$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | awk '\$1>4000' | wc -l) -ge 2 ]"
  t "7. unload освобождает VRAM" \
    "curl -fsS -X POST $SERVER/api/inference/unload -H 'Authorization: Bearer $KEY' -H 'Content-Type: application/json' -d '{\"model_path\":\"$MODEL\"}' --max-time 300 | grep -q unloaded && sleep 5 && [ \$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | sort -n | tail -1) -lt 2000 ]"
fi

[ "$FAIL" = 0 ] && echo "ВСЕ ТЕСТЫ ПРОШЛИ" || { echo "ЕСТЬ ПАДЕНИЯ"; exit 1; }
