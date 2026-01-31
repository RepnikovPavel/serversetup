#!/bin/bash
# motherboard-info.sh
echo "=== Информация о материнской плате ==="
echo "1. dmidecode:"
sudo dmidecode -t baseboard | grep -E "Manufacturer|Product|Version|Serial" | sed 's/^[ \t]*//'
echo -e "\n2. Sysfs:"
echo "Производитель: $(cat /sys/devices/virtual/dmi/id/board_vendor 2>/dev/null || echo 'N/A')"
echo "Модель:       $(cat /sys/devices/virtual/dmi/id/board_name 2>/dev/null || echo 'N/A')"
echo "Версия:       $(cat /sys/devices/virtual/dmi/id/board_version 2>/dev/null || echo 'N/A')"
echo -e "\n3. lshw:"
sudo lshw -short -class system -class bridge | grep -i mother
