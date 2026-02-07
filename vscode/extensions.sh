# #!/bin/bash
# set -e

# EXT_DIR="/mnt/nvme/vscode_extensions"
# mkdir -p "$EXT_DIR"

# # ✅ ПРОВЕРЕННЫЕ ID расширений (февраль 2026)
# declare -A EXTENSIONS=(
#   ["python"]="ms-python.python"
#   ["clangd"]="llvm-vs-code-extensions.vscode-clangd"
#   ["remote-ssh"]="ms-vscode-remote.remote-ssh"
#   ["remote-explorer"]="ms-vscode.remote-explorer"      # ← Было devcontainers
#   ["cmake-tools"]="ms-vscode.cmake-tools"
#   ["go"]="golang.go"
#   ["jupyter"]="ms-toolsai.jupyter"
#   ["gitlens"]="eamodio.gitlens"
# )

# download_ext() {
#   local name=$1
#   local publisher_ext=$2
#   local publisher=${publisher_ext%%.*}
#   local ext=${publisher_ext#*.}
#   local vsix_file="${EXT_DIR}/${publisher_ext}-latest.vsix"

#   echo "=== $name ($publisher_ext) ==="

#   if [ -f "$vsix_file" ]; then
#     echo "  Уже скачан"
#     return 0
#   fi

#   # Новый рабочий URL
#   local url="https://marketplace.visualstudio.com/_apis/public/gallery/publishers/${publisher}/vsextensions/${ext}/latest/vspackage"

#   # иногда требует юзер-агент и --compressed
#   if curl -L -f --compressed -A "Mozilla/5.0" -o "$vsix_file" "$url" 2>/dev/null; then
#     echo "  ✓ Скачан: $(du -h "$vsix_file" | cut -f1)"
#     return 0
#   fi

#   echo "  ✗ Не удалось скачать"
#   return 1
# }

# echo "🚀 Скачиваем в $EXT_DIR..."

# for name in "${!EXTENSIONS[@]}"; do
#   download_ext "$name" "${EXTENSIONS[$name]}" || true
# done

# echo -e "\n✅ Результат:"
# ls -lh "$EXT_DIR"/*.vsix 2>/dev/null || echo "Ничего не скачано"

# echo -e "\n📦 Dockerfile snippet:"
# echo 'COPY /mnt/nvme/vscode_extensions/*.vsix /tmp/exts/'
# echo 'RUN code --install-extension /tmp/exts/*.vsix --force && rm -rf /tmp/exts/'

#!/bin/bash
set -e

EXT_DIR="/mnt/nvme/vscode_extensions"
mkdir -p "$EXT_DIR"

# ✅ ПРОВЕРЕННЫЕ ID расширений (февраль 2026) + Python stack
declare -A EXTENSIONS=(
  # Основной Python pack (тянет Pylance, Debugger, Environments)
  ["python"]="ms-python.python"
  
  # Jupyter stack  
  ["jupyter"]="ms-toolsai.jupyter"
  ["jupyter-keymap"]="ms-toolsai.jupyter-keymap"
  ["jupyter-renderers"]="ms-toolsai.jupyter-renderers"
  
  # C++/Build
  ["clangd"]="llvm-vs-code-extensions.vscode-clangd"
  ["cmake-tools"]="ms-vscode.cmake-tools"
  
  # Remote/DevOps
  ["remote-ssh"]="ms-vscode-remote.remote-ssh"
  ["remote-explorer"]="ms-vscode.remote-explorer"
  
  # Другое
  ["go"]="golang.go"
  ["gitlens"]="eamodio.gitlens"
)

download_ext() {
  local name=$1
  local publisher_ext=$2
  local publisher=${publisher_ext%%.*}
  local ext=${publisher_ext#*.}
  local vsix_file="${EXT_DIR}/${publisher_ext}-latest.vsix"

  echo "=== $name ($publisher_ext) ==="

  if [ -f "$vsix_file" ]; then
    echo "  Уже скачан"
    return 0
  fi

  # Новый рабочий URL
  local url="https://marketplace.visualstudio.com/_apis/public/gallery/publishers/${publisher}/vsextensions/${ext}/latest/vspackage"

  # с юзер-агентом и compressed
  if curl -L -f --compressed -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" -o "$vsix_file" "$url" 2>/dev/null; then
    echo "  ✓ Скачан: $(du -h "$vsix_file" | cut -f1)"
    return 0
  fi

  echo "  ✗ Не удалось скачать"
  return 1
}

echo "🚀 Скачиваем Python/Jupyter stack в $EXT_DIR..."

for name in "${!EXTENSIONS[@]}"; do
  download_ext "$name" "${EXTENSIONS[$name]}" || true
done

echo -e "\n✅ Результат:"
ls -lh "$EXT_DIR"/*.vsix 2>/dev/null || echo "Ничего не скачано"

echo -e "\n📦 Dockerfile snippet:"
echo 'COPY /mnt/nvme/vscode_extensions/*.vsix /tmp/exts/'
echo 'RUN code --install-extension /tmp/exts/*.vsix --force && rm -rf /tmp/exts/'
