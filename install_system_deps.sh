sudo apt install -y net-tools
sudo apt install -y lm-sensors
sudo apt install -y python3.12-venv
cd ~
python3 -m venv ./venv
source ./venv/bin/activate
pip install nvitop --verbose --verbose
deactivate
sudo sysctl -w vm.max_map_count=262144
sh <(curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install) --daemon