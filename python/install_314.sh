cd /tmp
PY314_VERSION=$(curl -s https://www.python.org/ftp/python/ | grep -oE '3\.14\.[0-9]+' | sort -V | tail -1)
wget https://www.python.org/ftp/python/$PY314_VERSION/Python-$PY314_VERSION.tar.xz
tar -xf Python-$PY314_VERSION.tar.xz
cd Python-$PY314_VERSION

./configure --enable-optimizations --with-ensurepip=install --prefix=/usr/local
make -j$(nproc)
sudo make altinstall  # altinstall НЕ заменяет системный python3!