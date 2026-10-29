#!/usr/bin/env bash
set -Eeuo pipefail
. "$HOME/.config/go/env.sh"
hash -r
export GOTOOLCHAIN=local
expected=${1:-}
go version
[[ -z $expected || $(go env GOVERSION) == "$expected" ]]
[[ $(go env GOROOT) == /usr/local/go && $(go env GOPATH) == "$HOME/.local/share/go" ]]
for name in go gofmt gopls goimports gofumpt dlv staticcheck govulncheck godoc pkgsite; do
    command -v "$name"
done
gopls version
dlv version
staticcheck -version
gofumpt -version
govulncheck -version
go doc fmt.Println >/dev/null
work=$(mktemp -d)
cleanup() {
    local result=$?
    if [[ -n ${GO_SETUP_RECEIPT:-} ]]; then
        for log in "$work"/*.log; do
            [[ ! -f $log ]] || cp "$log" "$GO_SETUP_RECEIPT/"
        done
    fi
    if ((result)); then
        for log in "$work"/*.log; do
            [[ ! -f $log ]] || tail -n 40 "$log"
        done
    fi
    rm -rf -- "$work"
}
trap cleanup EXIT
cd "$work"
go mod init example.com/golang-setup-check
cat > main.go <<'EOF'
// Package main verifies the local Go development environment.
package main

import "fmt"

func answer() int { return 42 }
func main() { fmt.Println(answer()) }
EOF
cat > main_test.go <<'EOF'
package main

import "testing"

func TestAnswer(t *testing.T) {
    if answer() != 42 { t.Fatal("unexpected result") }
}
EOF
gofmt -w .
goimports -w .
gofumpt -w .
go test -race ./...
go vet ./...
staticcheck ./...
govulncheck ./...
gopls check main.go
go build -gcflags='all=-N -l' -o check .
[[ $(./check) == 42 ]]
printf 'break main.main\ncontinue\nexit\n' > debug.commands
timeout 30 dlv exec ./check --allow-non-terminal-interactive --init=debug.commands > debug.log 2>&1
grep -q 'Breakpoint 1' debug.log
mkdir cgo-check
cat > cgo-check/main.go <<'EOF'
package main
// int answer(void) { return 42; }
import "C"
func main() { if C.answer() != 42 { panic("CGO failed") } }
EOF
CGO_ENABLED=1 go run ./cgo-check
# Actually fetch HTTP documentation, rather than merely checking --help.
python3 - <<'PY'
import socket, subprocess, time, urllib.request
for name, route, needle in [('godoc', '/pkg/fmt/', b'Println'), ('pkgsite', '/example.com/golang-setup-check', b'golang-setup-check')]:
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        port = s.getsockname()[1]
    args = [name, '-http=127.0.0.1:' + str(port)] if name == 'godoc' else [name, '-http=127.0.0.1:' + str(port), '.']
    with open(name + '.log', 'wb') as log:
        proc = subprocess.Popen(args, stdout=log, stderr=log)
        try:
            for _ in range(90):
                if proc.poll() is not None:
                    raise RuntimeError(name + ' exited: ' + open(name + '.log').read())
                try:
                    with urllib.request.urlopen(f'http://127.0.0.1:{port}{route}', timeout=2) as response:
                        if response.status == 200 and needle in response.read():
                            print(name + ': HTTP documentation OK')
                            break
                except (OSError, TimeoutError):
                    pass
                time.sleep(1)
            else:
                raise RuntimeError(name + ' HTTP verification timed out: ' + open(name + '.log').read())
        finally:
            proc.terminate()
            try: proc.wait(timeout=10)
            except subprocess.TimeoutExpired: proc.kill(); proc.wait()
PY
if [[ -n ${GO_SETUP_RECEIPT:-} ]]; then
    cp debug.log godoc.log pkgsite.log "$GO_SETUP_RECEIPT/"
    go env -json > "$GO_SETUP_RECEIPT/go-env.json"
    date -u +%FT%TZ > "$GO_SETUP_RECEIPT/VERIFIED"
fi
echo 'PASS: SDK, modules, build, race tests, vet, CGO, LSP, formatting, lint, debugger and documentation HTTP.'
