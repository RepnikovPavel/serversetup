#!/bin/bash
# install-python311.sh - Установка Python 3.11 из исходников (Ubuntu)

set -e  # Остановка при ошибках

echo "🐍 Установка Python 3.11 из исходников..."

# Переход в /tmp и получение последней версии Python 3.11
cd /tmp

echo "📥 Получение последней версии Python 3.11..."
PY311_VERSION=$(curl -s https://www.python.org/ftp/python/ | grep -oE '3\.11\.[0-9]+' | sort -V | tail -1)
echo "Найдена версия: $PY311_VERSION"

# Скачивание и распаковка
wget https://www.python.org/ftp/python/$PY311_VERSION/Python-$PY311_VERSION.tar.xz
tar -xf Python-$PY311_VERSION.tar.xz
cd Python-$PY311_VERSION

# Конфигурация с оптимизациями
echo "⚙️ Конфигурация Python 3.11..."
./configure \
    --enable-optimizations \
    --with-ensurepip=install \
    --prefix=/usr/local

# Компиляция (параллельно по количеству ядер)
echo "🔨 Компиляция (используется $(nproc) ядер)..."
make -j$(nproc)

# Установка (altinstall НЕ заменяет системный python3!)
echo "📦 Установка Python 3.11..."
sudo make altinstall

# Очистка
echo "🧹 Очистка временных файлов..."
cd /tmp
rm -rf Python-$PY311_VERSION*

# Проверка установки
echo "✅ Проверка установки..."
/usr/local/bin/python3.11 --version
/usr/local/bin/python3.11 -m pip --version

echo "🎉 Python 3.11 успешно установлен!"
echo ""
echo "Использование:"
echo "  python3.11          # Запуск Python 3.11"
echo "  python3.11 -m pip   # pip для Python 3.11"
echo "  /usr/local/bin/python3.11 script.py"
