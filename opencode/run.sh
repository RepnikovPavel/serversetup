#!/usr/bin/env bash
# run.sh — launch the OpenCode plugin installer TUI.
# If the catalog is missing, regenerate it from the registry first.
set -eu
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

if [ ! -f plugins_catalog.json ]; then
  echo "catalog missing — building from registry…" >&2
  python3 build_catalog.py
fi

exec python3 installer.py
