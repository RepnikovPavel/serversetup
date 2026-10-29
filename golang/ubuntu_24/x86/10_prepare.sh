#!/usr/bin/env bash
# Download and build everything before replacing the active installation.
set -Eeuo pipefail
: "${GO_SETUP_WORK:?Run run.sh}" "${GO_SETUP_RECEIPT:?Run run.sh}"
selection=${1:?}
curl -fLsS --retry 3 --connect-timeout 20 --max-time 180 \
    'https://go.dev/dl/?mode=json&include=all' -o "$GO_SETUP_WORK/releases.json"
python3 - "$GO_SETUP_WORK" "$selection" <<'PY'
import json, pathlib, sys
root, selection = pathlib.Path(sys.argv[1]), sys.argv[2]
releases = json.loads((root / 'releases.json').read_text())
matches = [r for r in releases if r['stable'] and (selection == 'latest' or r['version'] == 'go' + selection)]
if not matches:
    raise SystemExit('Requested stable Go release not found: ' + selection)
release = max(matches, key=lambda r: tuple(map(int, r['version'][2:].split('.'))))
archive = next(f for f in release['files'] if f['os'] == 'linux' and f['arch'] == 'amd64' and f['kind'] == 'archive')
(root / 'release.json').write_text(json.dumps(archive, indent=2) + '\n')
for key in ('filename', 'sha256', 'version'):
    (root / key).write_text(archive[key] + '\n')
print('Selected:', release['version'])
PY
filename=$(cat "$GO_SETUP_WORK/filename")
curl -fLsS --retry 3 --connect-timeout 20 --max-time 900 \
    "https://go.dev/dl/$filename" -o "$GO_SETUP_WORK/$filename"
(cd "$GO_SETUP_WORK"; printf '%s  %s\n' "$(cat sha256)" "$filename" | sha256sum -c -)
tar -xzf "$GO_SETUP_WORK/$filename" -C "$GO_SETUP_WORK"
export GOROOT="$GO_SETUP_WORK/go" GOENV=off GOTOOLCHAIN=local
export GOPATH="$HOME/.cache/golang-setup/build-workspace" GOBIN="$GO_SETUP_WORK/tools"
export GOMODCACHE="$GOPATH/pkg/mod" GOCACHE="$HOME/.cache/golang-setup/build-cache"
export GOOS=linux GOARCH=amd64 GOFLAGS='' GOWORK=off CGO_ENABLED=1
export GOPROXY=https://proxy.golang.org,direct GOSUMDB=sum.golang.org
export GONOPROXY='' GONOSUMDB='' GOPRIVATE=''
mkdir -p "$GOBIN"
"$GOROOT/bin/go" version
# Build tooling with automatic toolchain selection; this does not change the
# requested SDK. A newer compiler may be needed by current tool releases.
export GOTOOLCHAIN=auto
tools=(
    golang.org/x/tools/gopls@latest
    golang.org/x/tools/cmd/goimports@latest
    mvdan.cc/gofumpt@latest
    github.com/go-delve/delve/cmd/dlv@latest
    honnef.co/go/tools/cmd/staticcheck@latest
    golang.org/x/vuln/cmd/govulncheck@latest
    golang.org/x/tools/cmd/godoc@v0.1.0-deprecated
    golang.org/x/pkgsite/cmd/pkgsite@latest
)
cd "$GO_SETUP_WORK"
for tool in "${tools[@]}"; do
    echo "Building $tool"
    "$GOROOT/bin/go" install "$tool"
done
cp release.json "$GO_SETUP_RECEIPT/"
for binary in "$GOBIN"/*; do
    "$GOROOT/bin/go" version -m "$binary"
done > "$GO_SETUP_RECEIPT/tools.txt"
(cd "$GOBIN"; sha256sum ./*) > "$GO_SETUP_RECEIPT/tools.sha256"
