#!/usr/bin/env bash
# setup.sh — один скрипт: поднять Unsloth Studio + модель и/или подключить агента.
#
# Сервер (всё в одном): установка, модель, автозагрузка, API-ключ, smoke-тест:
#   UNSLOTH_HOST_DIR=/mnt/data1/unsloth_default bash setup.sh
#
# Сервер в сети с подменой TLS-сертификатов:
#   UNSLOTH_HOST_DIR=/mnt/data1/unsloth_default USE_LOCAL_CA=1 HF_HUB_DISABLE_XET=1 bash setup.sh
#
# Клиент (настроить OpenCode на этого агента + проверить связь):
#   bash setup.sh client <SERVER_IP> <PORT> <API_KEY> [DISPLAY_NAME]
# DISPLAY_NAME — имя модели в UI агента (квант+объём печатает сервер в конце установки).
set -euo pipefail
cd "$(dirname "$0")"

HOST_DIR="${UNSLOTH_HOST_DIR:-/mnt/data1/unsloth_default}"
CUDA_VARIANT="${CUDA_VARIANT:-cu128}"
PORT="${STUDIO_HOST_PORT:-48218}"
PASSWORD="${UNSLOTH_STUDIO_PASSWORD:-12345678}"
HF_TOKEN="${HF_TOKEN:-}"
XET="${HF_HUB_DISABLE_XET:-0}"
REPO="${MODEL_REPO:-unsloth/Qwen3.8-27B-GGUF}"
QUANT="${QUANT:-UD-Q4_K_XL}"
CONTAINER="unsloth-studio-${CUDA_VARIANT}"
OUT="out"; mkdir -p "$OUT"   # сгенерированные ключи/конфиги, в .gitignore

if [ "${1:-}" = "client" ]; then
    SRV="http://${2:?SERVER_IP}:${3:?PORT}"; KEY="${4:?API_KEY}"
    # Имя модели в UI агента: с квантом и объёмом весов, например
    # "Qwen3.8-27B UD-Q4_K_XL · 17.9 GB · ctx 256K" (сервер печатает готовую
    # команду с этим аргументом в конце setup.sh). id модели не меняется.
    DISPLAY="${5:-$REPO}"
    echo "== 1/2 проверка связи =="
    curl -fsS "$SRV/v1/models" -H "Authorization: Bearer $KEY" | head -c 300; echo
    echo "== 2/2 конфиг OpenCode =="
    mkdir -p ~/.config/opencode
    CTX="${MODEL_CTX:-262144}" OUT_TOK="${MODEL_OUTPUT:-16384}" \
    python3 - "$SRV" "$KEY" "$REPO" "$DISPLAY" <<'EOF'
import json,sys,os
srv,key,model,display=sys.argv[1:5]
ctx=int(os.environ.get("MODEL_CTX","262144")); out_tok=int(os.environ.get("MODEL_OUTPUT","16384"))
p=os.path.expanduser("~/.config/opencode/opencode.json")
cfg=json.load(open(p)) if os.path.exists(p) else {"$schema":"https://opencode.ai/config.json"}
cfg.setdefault("provider",{})["server"]={"npm":"@ai-sdk/openai-compatible","name":"server",
  "options":{"baseURL":srv+"/v1","apiKey":key},
  "models":{model:{"name":display,"limit":{"context":ctx,"output":out_tok}}}}
json.dump(cfg,open(p,"w"),indent=2); print("записано:",p)
EOF
    echo "Готово. Запуск: opencode  (модель: $DISPLAY)"
    exit 0
fi

echo "== 1/6 сертификаты =="
[ "${USE_LOCAL_CA:-0}" = "1" ] && cp /usr/local/share/ca-certificates/*.crt docker/certs/ || echo "пропуск (USE_LOCAL_CA!=1)"

echo "== 2/6 docker compose up =="
UNSLOTH_HOST_DIR="$HOST_DIR" CUDA_VARIANT="$CUDA_VARIANT" STUDIO_HOST_PORT="$PORT" \
UNSLOTH_STUDIO_PASSWORD="$PASSWORD" HF_TOKEN="$HF_TOKEN" HF_HUB_DISABLE_XET="$XET" \
docker compose up -d --build

echo "== 3/6 жду Studio (первая установка ~15 мин) =="
for i in $(seq 1 120); do
  curl -fsS -o /dev/null --max-time 5 "http://127.0.0.1:$PORT/" && break
  docker ps --filter name="$CONTAINER" --format '{{.Status}}' | grep -q Restarting && { docker logs --tail 30 "$CONTAINER"; exit 1; }
  sleep 15
done
curl -fsS -o /dev/null "http://127.0.0.1:$PORT/" && echo "Studio UP"

echo "== 4/6 модель $REPO ($QUANT) =="
docker exec -e HF_HUB_DISABLE_XET="$XET" "$CONTAINER" \
  /data/studio/unsloth_studio/bin/hf download "$REPO" --include "*${QUANT}*"

echo "== 5/6 автозагрузка + API-ключ =="
TOKEN=$(curl -fsS -X POST "http://127.0.0.1:$PORT/api/auth/login" -H 'Content-Type: application/json' \
  -d "{\"username\":\"unsloth\",\"password\":\"$PASSWORD\"}" | python3 -c 'import json,sys;print(json.load(sys.stdin)["access_token"])')
curl -fsS -X PUT "http://127.0.0.1:$PORT/api/settings/openai-auto-switch" -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -d '{"enabled":true,"auto_unload_idle_seconds":1800}' >/dev/null
KEY=$(curl -fsS -X POST "http://127.0.0.1:$PORT/api/auth/api-keys" -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -d "{\"name\":\"setup-$(date +%Y%m%d-%H%M)\"}" | python3 -c 'import json,sys;print(json.load(sys.stdin)["key"])')
echo "$KEY" > "$OUT/agent_api_key"; chmod 600 "$OUT/agent_api_key"
SRV_IP=$(hostname -I | awk '{print $1}')

echo "== 6/6 smoke-тест =="
curl -fsS -X POST "http://127.0.0.1:$PORT/v1/chat/completions" -H "Authorization: Bearer $KEY" \
  -H 'Content-Type: application/json' --max-time 900 \
  -d "{\"model\":\"$REPO\",\"messages\":[{\"role\":\"user\",\"content\":\"2+2? одной цифрой\"}],\"max_tokens\":256,\"chat_template_kwargs\":{\"enable_thinking\":false}}" \
  | python3 -c 'import json,sys;print("ответ модели:",json.load(sys.stdin)["choices"][0]["message"]["content"])'

# Отображаемое имя для агентов: базовая модель + квант + объём весов + контекст.
BASE_NAME=$(basename "$REPO" | sed 's/-GGUF$//')
SIZE_BYTES=$(docker exec "$CONTAINER" sh -c "stat -c %s /data/hf_cache/hub/models--${REPO/\//--}/snapshots/*/*${QUANT}*.gguf 2>/dev/null | head -1" || true)
CTX="${UNSLOTH_LLAMA_CTX_SIZE:-262144}"
DISPLAY=$(BASE_NAME="$BASE_NAME" QUANT="$QUANT" SIZE_BYTES="$SIZE_BYTES" CTX="$CTX" python3 - <<'EOF'
import os
base=os.environ["BASE_NAME"]; quant=os.environ["QUANT"]
size=os.environ.get("SIZE_BYTES") or ""
gb=f"{int(size)/1e9:.1f} GB" if size.isdigit() else "? GB"
ctx_k=int(os.environ.get("CTX","262144"))//1024
print(f"{base} {quant} · {gb} · ctx {ctx_k}K")
EOF
)
echo "$DISPLAY" > "$OUT/model_display_name"

echo "=============================================================="
echo "ГОТОВО. Агентам: baseURL=http://$SRV_IP:$PORT/v1  model=$REPO"
echo "API-ключ: $KEY"
echo "(ключ также в $OUT/agent_api_key)"
echo "На машине агента:"
echo "  bash setup.sh client $SRV_IP $PORT $KEY \"$DISPLAY\""
