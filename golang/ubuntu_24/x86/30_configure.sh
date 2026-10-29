#!/usr/bin/env bash
set -Eeuo pipefail
: "${GO_SETUP_RECEIPT:?Run run.sh}"
# ~/go may contain source projects: preserve directories. A colliding file or
# symlink is archived, never executed or discarded.
if [[ -L $HOME/go || ( -e $HOME/go && ! -d $HOME/go ) ]]; then
    mv -- "$HOME/go" "$GO_SETUP_RECEIPT/home-go"
    [[ -L $GO_SETUP_RECEIPT/home-go ]] || chmod go-rwx "$GO_SETUP_RECEIPT/home-go"
    echo "Archived conflicting ~/go: $GO_SETUP_RECEIPT/home-go"
fi
mkdir -p "$HOME/.config/go" "$HOME/.local/share/go/bin" "$GO_SETUP_RECEIPT/user-files"
python3 - "$GO_SETUP_RECEIPT" <<'PY'
import os, pathlib, re, shutil, sys
home, backup = pathlib.Path.home(), pathlib.Path(sys.argv[1]) / 'user-files'
names = ['.bashrc', '.profile', '.bash_profile', '.bash_login', '.zshrc', '.zprofile']
begin, end = '# >>> serversetup golang >>>', '# <<< serversetup golang <<<'
block = f'{begin}\n[ ! -r "$HOME/.config/go/env.sh" ] || . "$HOME/.config/go/env.sh"\n{end}\n'
for name in names:
    path = home / name
    if not path.exists() and name not in ('.bashrc', '.profile'):
        continue
    old = path.read_text() if path.exists() else ''
    new = re.sub(re.escape(begin) + r'.*?' + re.escape(end) + r'\n?', '', old, flags=re.S)
    # Remove only standalone Go exports / dedicated Go PATH append statements.
    new = re.sub(r'(?m)^\s*(?:export\s+)?(?:GOROOT|GOPATH|GOBIN)=[^\n]*\n?', '', new)
    new = re.sub(r'(?m)^\s*export PATH=["\']?\$(?:PATH|\{PATH\}):/usr/local/go/bin["\']?\s*$', '', new)
    new = new.rstrip() + '\n\n' + block
    if new != old:
        if path.exists(): shutil.copy2(path, backup / name)
        path.write_text(new)
env = home / '.config/go/env.sh'
if env.exists(): shutil.copy2(env, backup / 'env.sh')
env.write_text('''# Managed by serversetup/golang/ubuntu_24/x86.
unset GOROOT
export GOPATH="$HOME/.local/share/go"
export GOBIN="$GOPATH/bin"
# Remove duplicates so sourcing repeatedly does not grow PATH.
_go_path= _go_rest="${PATH-}"
while [ -n "$_go_rest" ]; do
    _go_item=${_go_rest%%:*}
    case $_go_rest in *:*) _go_rest=${_go_rest#*:} ;; *) _go_rest= ;; esac
    case $_go_item in
        /usr/local/go/bin|/usr/local/bin|"$GOBIN") ;;
        *) _go_path="${_go_path:+$_go_path:}$_go_item" ;;
    esac
done
export PATH="/usr/local/go/bin:/usr/local/bin:$GOBIN${_go_path:+:$_go_path}"
unset _go_path _go_rest _go_item
''')
# Persist settings for noninteractive go processes too, while retaining other
# user settings (private proxy configuration etc.).
envfile = pathlib.Path(os.environ.get('GOENV') or home / '.config/go/env')
if str(envfile) != 'off':
    old = envfile.read_text() if envfile.exists() else ''
    if envfile.exists(): shutil.copy2(envfile, backup / 'go-env')
    lines = [s for s in old.splitlines() if not s.startswith(('GOROOT=', 'GOPATH=', 'GOBIN='))]
    lines += [f'GOPATH={home}/.local/share/go', f'GOBIN={home}/.local/share/go/bin']
    envfile.parent.mkdir(parents=True, exist_ok=True)
    envfile.write_text('\n'.join(lines) + '\n')
PY
