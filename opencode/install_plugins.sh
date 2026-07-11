#!/usr/bin/env bash
#
# install_plugins.sh — install every OpenCode plugin listed in plugins.tsv
# into the global OpenCode config (~/.config/opencode/opencode.jsonc) using
# `opencode plugin <spec> -g`.
#
# Features:
#   * idempotent / resumable — plugins already present in the config are skipped
#   * resilient            — a single plugin failure never aborts the run
#   * per-plugin timeout   — a hanging install is killed and marked FAIL
#   * retry once on failure (transient network errors)
#   * full per-plugin log in install.log, machine-readable state in install.state.tsv
#
# Usage:
#   ./install_plugins.sh                 # install everything globally
#   SCOPE=project ./install_plugins.sh   # install into ./.opencode instead
#   MANIFEST=/path/plugins.tsv ./install_plugins.sh
#
set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${MANIFEST:-$DIR/plugins.tsv}"
LOG="$DIR/install.log"
STATE="$DIR/install.state.tsv"

CONFIG_GLOBAL="$HOME/.config/opencode/opencode.jsonc"
CONFIG_LOCAL="./.opencode/opencode.json"
if [ "${SCOPE:-global}" = "project" ]; then
  CONFIG="$CONFIG_LOCAL"; SCOPE_FLAG=""
else
  CONFIG="$CONFIG_GLOBAL"; SCOPE_FLAG="-g"
fi

PER_INSTALL_TIMEOUT="${PER_INSTALL_TIMEOUT:-180}"   # seconds per plugin
RETRIES="${RETRIES:-1}"                              # retries after a failure

command -v opencode >/dev/null 2>&1 || { echo "ERROR: opencode not found in PATH" >&2; exit 1; }
[ -f "$MANIFEST" ] || { echo "ERROR: manifest not found: $MANIFEST (run generate_manifest.py)" >&2; exit 1; }

mkdir -p "$(dirname "$CONFIG")"
[ -f "$CONFIG" ] || printf '{\n  "$schema": "https://opencode.ai/config.json"\n}\n' > "$CONFIG"

# Read the current `plugin:` array from the (possibly commented) jsonc config
# and print one spec per line.
installed_specs() {
  python3 - "$CONFIG" <<'PY'
import json, re, sys
try:
    raw = open(sys.argv[1]).read()
except FileNotFoundError:
    sys.exit(0)
raw = re.sub(r'/\*.*?\*/', '', raw, flags=re.S)          # block comments
raw = re.sub(r'(^|[^:])//.*', r'\1', raw)                # line comments
try:
    cfg = json.loads(raw)
except Exception:
    sys.exit(0)
for x in (cfg.get('plugin') or []):
    if isinstance(x, list) and x:
        print(x[0])
    elif isinstance(x, str):
        print(x)
PY
}

mapfile -t ALREADY < <(installed_specs)
is_installed() {
  local s="$1" x
  for x in "${ALREADY[@]:-}"; do [ "$x" = "$s" ] && return 0; done
  return 1
}

count_data_lines() { awk 'NF && $0 !~ /^#/ {n++} END{print n+0}' "$MANIFEST"; }
total=$(count_data_lines)

: > "$LOG"
: > "$STATE"
i=0; ok=0; fail=0; skip=0
echo "install_plugins.sh — scope=${SCOPE:-global}  config=$CONFIG"
echo "manifest=$MANIFEST  plugins=$total  per_install_timeout=${PER_INSTALL_TIMEOUT}s  retries=$RETRIES"
echo

while IFS=$'\t' read -r pid name repo cand _; do
  cand="${cand:-}"
  [ -z "$cand" ] && continue
  case "$pid" in \#*) continue;; esac
  i=$((i+1))
  # shellcheck disable=SC2086
  set -- $cand            # positional params = candidate specs, in priority order

  # Skip if any candidate is already present in the config.
  already=""
  for spec in "$@"; do
    if is_installed "$spec"; then already="$spec"; break; fi
  done
  if [ -n "$already" ]; then
    skip=$((skip+1))
    printf '[%3d/%d] SKIP  %s (already: %s)\n' "$i" "$total" "$name" "$already"
    printf '%s\t%s\t%s\t%s\t%s\n' "$pid" "SKIP" "$already" "0" "$(date -Is)" >> "$STATE"
    continue
  fi

  printf '[%3d/%d] ....  %s\n' "$i" "$total" "$name"
  st="FAIL"; ec=1; chosen=""; out=""
  for spec in "$@"; do
    attempt_out=""
    for attempt in $(seq 0 "$RETRIES"); do
      attempt_out=$(timeout "${PER_INSTALL_TIMEOUT}" opencode plugin "$spec" $SCOPE_FLAG 2>&1)
      ec=$?
      [ "$ec" = "0" ] && break
      [ "$attempt" -lt "$RETRIES" ] && sleep 3
    done
    out+="--- tried: $spec (exit $ec) ---\n$attempt_out\n"
    if [ "$ec" = "0" ]; then
      st="OK"; chosen="$spec"; break
    fi
  done
  [ -z "$chosen" ] && chosen="$spec"

  if [ "$st" = "OK" ]; then ok=$((ok+1)); else fail=$((fail+1)); fi
  printf '[%3d/%d] %-4s  %s -> %s (exit %s)\n' "$i" "$total" "$st" "$name" "$chosen" "$ec"

  printf '%s\t%s\t%s\t%s\t%s\n' "$pid" "$st" "$chosen" "$ec" "$(date -Is)" >> "$STATE"
  {
    printf '\n=== %s | %s | %s | %s | exit %s ===\n' "$(date -Is)" "$name" "$chosen" "$st" "$ec"
    printf '%b\n' "$out"
  } >> "$LOG"
done < "$MANIFEST"

echo
echo "============================================================"
echo "Done. total=$total  OK=$ok  FAIL=$fail  SKIP=$skip"
echo "state: $STATE   log: $LOG"
echo "config: $CONFIG"
echo "============================================================"
