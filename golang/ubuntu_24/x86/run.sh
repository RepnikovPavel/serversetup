#!/usr/bin/env bash
# Ubuntu 24.04 amd64: full Go SDK and development tools.
set -Eeuo pipefail
usage() {
    cat <<'EOF'
Usage: ./run.sh [--latest | --version 1.27.3 | 1.27.3]
       ./run.sh --verify
Run as the target user, not with sudo. Privileged steps use sudo themselves.
Default: latest stable Go. Releases >= 1.21 are supported.
EOF
}
selection=latest
case "${1:---latest}" in
    --help|-h) usage; exit 0 ;;
    --verify) [[ $# == 1 ]] || { usage; exit 2; }; exec "$(dirname "$0")/40_verify.sh" ;;
    --latest) [[ $# -le 1 ]] || { usage; exit 2; } ;;
    --version) [[ $# == 2 ]] || { usage; exit 2; }; selection=${2#go} ;;
    *) [[ $# == 1 ]] || { usage; exit 2; }; selection=${1#go} ;;
esac
[[ $selection == latest || $selection =~ ^1\.[0-9]+\.[0-9]+$ ]] || { usage; exit 2; }
if [[ $selection != latest ]] && (( $(cut -d. -f2 <<< "$selection") < 21 )); then
    echo 'Go >= 1.21 is required for modern development tools.' >&2; exit 2
fi
[[ $EUID != 0 ]] || { echo 'Run as your regular user, without sudo.' >&2; exit 2; }
. /etc/os-release
[[ $ID == ubuntu && $VERSION_ID == 24.04 && $(uname -m) == x86_64 ]] || {
    echo 'This installer requires Ubuntu 24.04 x86_64.' >&2; exit 2;
}
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
state_root="$HOME/.local/state/golang-setup"
mkdir -p "$state_root"
chmod 700 "$state_root"
exec 9>"$state_root/install.lock"
flock -n 9 || { echo 'Another installation is running.' >&2; exit 1; }
export GO_SETUP_RECEIPT
GO_SETUP_RECEIPT=$(mktemp -d "$state_root/$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")
export GO_SETUP_WORK
GO_SETUP_WORK=$(mktemp -d)
trap 'rm -rf -- "$GO_SETUP_WORK"' EXIT
exec > >(tee "$GO_SETUP_RECEIPT/install.log") 2>&1
echo "Receipts and user backups: $GO_SETUP_RECEIPT"
sudo_cmd=(sudo)
[[ -z ${SUDO_ASKPASS:-} ]] || sudo_cmd+=(-A)
"${sudo_cmd[@]}" -v
packages=(ca-certificates curl python3 tar gzip git build-essential pkg-config)
missing=()
for package in "${packages[@]}"; do
    [[ $(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true) == 'install ok installed' ]] || missing+=("$package")
done
if ((${#missing[@]})); then
    "${sudo_cmd[@]}" apt-get update
    "${sudo_cmd[@]}" apt-get install -y --no-install-recommends "${missing[@]}"
fi
"$script_dir/10_prepare.sh" "$selection"
"${sudo_cmd[@]}" bash "$script_dir/20_install.sh" "$GO_SETUP_WORK" "$(basename "$GO_SETUP_RECEIPT")"
"$script_dir/30_configure.sh"
"$script_dir/40_verify.sh" "$(cat "$GO_SETUP_WORK/version")"
ln -sfn "$GO_SETUP_RECEIPT" "$state_root/latest"
echo "Complete. Reload this terminal: source \"$HOME/.config/go/env.sh\"; hash -r"
