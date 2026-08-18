#!/usr/bin/env bash
# tests/agents.sh — физическая проверка harness-агентов против сервера с моделью.
# Запускать на машине агента:
#   SERVER=http://192.168.x.x:48218 API_KEY=sk-unsloth-... bash tests/agents.sh
set -uo pipefail
cd "$(dirname "$0")/.."

SERVER="${SERVER:?укажи SERVER=http://<ip>:<port>}"
KEY="${API_KEY:?укажи API_KEY=sk-unsloth-...}"
MODEL="${MODEL_REPO:-unsloth/Qwen3.8-27B-GGUF}"
FAIL=0

if command -v opencode >/dev/null 2>&1; then
  CFG=$(mktemp /tmp/opencode-test-XXXX.json)
  cat > "$CFG" <<EOF
{"\$schema":"https://opencode.ai/config.json",
 "provider":{"server":{"npm":"@ai-sdk/openai-compatible","name":"server",
   "options":{"baseURL":"$SERVER/v1","apiKey":"$KEY"},
   "models":{"$MODEL":{"name":"$MODEL","limit":{"context":32768,"output":8192}}}}},
 "model":"server/$MODEL"}
EOF
  OUT=$(OPENCODE_CONFIG="$CFG" timeout 300 opencode run "Reply with exactly: OK" 2>&1)
  echo "$OUT" | tail -3
  if echo "$OUT" | grep -qi "ok"; then echo "PASS: opencode"; else echo "FAIL: opencode"; FAIL=1; fi
  rm -f "$CFG"
else
  echo "SKIP: opencode не установлен (agents/cli_install.sh)"
fi

if command -v aider >/dev/null 2>&1; then
  OUT=$(OPENAI_API_BASE="$SERVER/v1" OPENAI_API_KEY="$KEY" timeout 300 \
        aider --no-git --yes --message "Reply with exactly: OK" --model "openai/$MODEL" 2>&1)
  echo "$OUT" | tail -3
  if echo "$OUT" | grep -qi "ok"; then echo "PASS: aider"; else echo "FAIL: aider"; FAIL=1; fi
else
  echo "SKIP: aider не установлен (pip install aider-chat)"
fi

[ "$FAIL" = 0 ] && echo "АГЕНТЫ ОК" || exit 1
