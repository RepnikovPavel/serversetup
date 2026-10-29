#!/usr/bin/env bash
# Privileged stage. Only called after downloads and all tool builds succeeded.
set -Eeuo pipefail
[[ $EUID == 0 ]] || { echo 'This stage requires sudo via run.sh.' >&2; exit 1; }
work=${1:?}
run_id=${2:?}
[[ $run_id =~ ^[0-9TZ-]+-[a-zA-Z0-9]+$ ]] || exit 2
[[ -x $work/go/bin/go && -x $work/tools/godoc && -x $work/tools/pkgsite ]] || exit 2
backup="/var/backups/golang-setup/$run_id"
mkdir -p "$backup" /usr/local/bin /usr/local/libexec
chmod 700 /var/backups/golang-setup "$backup"
# Remove distro SDK packages, but never silently remove dependent applications.
mapfile -t packages < <(dpkg-query -W -f='${binary:Package} ${Status}\n' 2>/dev/null |
    awk '$2 == "install" && $3 == "ok" && $4 == "installed" && $1 ~ /^golang(-[0-9]+\.[0-9]+)?(-go|-src|-doc)?(:amd64)?$/ {print $1}')
if ((${#packages[@]})); then
    apt-get -s remove --no-auto-remove "${packages[@]}" > "$backup/apt-plan.txt"
    while read -r removed; do
        [[ " ${packages[*]} " == *" $removed "* ]] || {
            echo "Refusing removal of unrelated dependent package: $removed" >&2; exit 1;
        }
    done < <(awk '/^Remv / {print $2}' "$backup/apt-plan.txt")
    apt-get remove -y --no-auto-remove "${packages[@]}"
fi
if command -v snap >/dev/null && snap list go >/dev/null 2>&1; then
    snap remove go
fi
# Prepare on the destination filesystem; never unpack over an existing SDK.
staging=$(mktemp -d /usr/local/.golang-setup-XXXXXX)
trap 'rm -rf -- "$staging"' EXIT
cp -a "$work/go" "$staging/go"
cp -a "$work/tools" "$staging/tools"
chown -R root:root "$staging"
chmod -R go-w "$staging"
backup_path() {
    local path=$1
    if [[ -e $path || -L $path ]]; then
        mkdir -p "$backup$(dirname "$path")"
        mv -- "$path" "$backup$path"
    fi
}
backup_path /usr/local/go
if ! mv "$staging/go" /usr/local/go; then
    [[ ! -e $backup/usr/local/go ]] || mv "$backup/usr/local/go" /usr/local/go
    exit 1
fi
backup_path /usr/local/libexec/golang
mv "$staging/tools" /usr/local/libexec/golang
for name in go gofmt gopls goimports gofumpt dlv staticcheck govulncheck godoc pkgsite; do
    backup_path "/usr/local/bin/$name"
    target="/usr/local/libexec/golang/$name"
    [[ $name != go && $name != gofmt ]] || target="/usr/local/go/bin/$name"
    ln -s "$target" "/usr/local/bin/$name"
done
echo "System backup: $backup"
