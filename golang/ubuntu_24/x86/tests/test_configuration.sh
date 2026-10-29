#!/usr/bin/env bash
# Isolated regression tests: no sudo, network or changes to the real home.
set -Eeuo pipefail
scripts=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/user" "$work/receipt1" "$work/receipt2"
printf 'unrelated setup script\n' > "$work/user/go"
printf 'export PATH=$PATH:/usr/local/go/bin\nexport GOPATH=/old\nexport KEEP_ME=yes\n' > "$work/user/.bashrc"
configure() {
    HOME="$work/user" GOENV="$work/user/.config/go/env" GO_SETUP_RECEIPT="$1" "$scripts/30_configure.sh"
}
configure "$work/receipt1"
[[ ! -e $work/user/go ]]
grep -q 'unrelated setup script' "$work/receipt1/home-go"
grep -q 'KEEP_ME=yes' "$work/user/.bashrc"
! grep -q 'GOPATH=/old' "$work/user/.bashrc"
cp "$work/user/.bashrc" "$work/bashrc.first"
configure "$work/receipt2"
cmp "$work/bashrc.first" "$work/user/.bashrc"
HOME="$work/user" bash --noprofile --norc -c '
    . "$HOME/.config/go/env.sh"
    first=$PATH
    . "$HOME/.config/go/env.sh"
    [[ $PATH == "$first" && $GOPATH == "$HOME/.local/share/go" ]]
'
# An existing workspace with source files must survive the migration.
mkdir -p "$work/user/go/src/project" "$work/receipt3"
printf 'valuable source\n' > "$work/user/go/src/project/main.go"
configure "$work/receipt3"
grep -q 'valuable source' "$work/user/go/src/project/main.go"
# A symlink must be archived without chmod-ing its target.
mv "$work/user/go" "$work/project"
ln -s "$work/project" "$work/user/go"
before=$(stat -c %a "$work/project")
mkdir "$work/receipt4"
configure "$work/receipt4"
[[ -L $work/receipt4/home-go && $(stat -c %a "$work/project") == "$before" ]]
for args in '--version' '--latest --version 1.27.3' '--version nonsense'; do
    read -r -a argv <<< "$args"
    if "$scripts/run.sh" "${argv[@]}" >/dev/null 2>&1; then
        echo "Invalid arguments accepted: $args" >&2; exit 1
    fi
done
echo 'PASS: configuration idempotence, PATH idempotence, backup, source preservation, symlink preservation, CLI validation.'
