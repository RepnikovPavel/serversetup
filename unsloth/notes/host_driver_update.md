# Заметки разработчика: обновление драйвера на хосте без ребута (driver drift)

Симптом (2026-08-22, сервер `pc`): после apt-обновления NVIDIA-драйвера на хосте
без перезагрузки новые GPU-контейнеры падают на старте:

```
failed to fulfil mount request: open /run/nvidia-persistenced/socket: no such file or directory
# затем, после создания заглушки сокета:
failed to fulfil mount request: open /usr/lib/x86_64-linux-gnu/libEGL_nvidia.so.580.159.03: no such file or directory
```

Причина: ядро держит старый модуль (580.159.03), userspace на хосте уже новый
(580.173.02), а CDI-спека `/var/run/cdi/nvidia.yaml` (генерируется один раз
`nvidia-ctk cdi generate`, у нас — при буте 2026-07-19) ссылается на файлы
старого драйвера, которые apt уже удалил. `nvidia-smi` на хосте при этом падает
с `Driver/library version mismatch`, `nvidia-persistenced` не стартует —
но давно запущенные контейнеры продолжают работать (их bind-монтирования держат
удалённые inode).

Правильное лечение — **ребут** (поднимется новый модуль ядра, persistenced
стартанёт, спека перегенерируется). Если ребут нельзя (на сервере живые
парсеры), рабочий обход без простоя:

1. Вытащить userspace-библиотеки СТАРОЙ (совпадающей с ядром) версии из любого
   ещё работающего GPU-контейнера. `docker cp` для bind-mount'ов возвращает
   пустые файлы — только tar-стриминг через exec:

   ```sh
   # список недостающих файлов = hostPath из /var/run/cdi/nvidia.yaml, которых нет на хосте
   ssh server 'grep hostPath: /var/run/cdi/nvidia.yaml | sed "s/.*hostPath: //" | sort -u' > /tmp/hp.txt
   docker exec -i <ЖИВОЙ_GPU_КОНТЕЙНЕР> sh -c "cd / && tar cf - -T -" < список_без_ведущего_слэша | tar xf -
   ```

2. Сложить их в `/opt/nvidia-<старая_версия>-compat/` (плоско, по basename) и
   поправить hostPath в `/var/run/cdi/nvidia.yaml` на эти пути (бэкап спеки
   рядом: `nvidia.yaml.bak-*`). Бинарник `nvidia-smi` — тоже оттуда же, хостовый
   уже новой версии и с старой libnvidia-ml не сработает.

3. `mkdir -p /run/nvidia-persistenced && touch /run/nvidia-persistenced/socket` —
   спека монтирует этот сокет; сам сокет контейнеру не нужен, нужен сам факт
   существования пути для bind-монта.

4. Проверка: `docker run --rm --gpus all --entrypoint nvidia-smi <image>` —
   должен показать обе GPU и версию драйвера = версии модуля ядра
   (`cat /proc/driver/nvidia/version`).

Ограничения обхода: `/var/run/cdi/nvidia.yaml` перегенерируется при ребуте/
перезапуске `nvidia-ctk-cdi-refresh` — после ребута хака не нужно, compat-каталог
можно удалить. До ребута `nvidia-smi` на самом хосте останется сломанным
(используйте `docker run --rm --gpus all --entrypoint nvidia-smi ...`).

Реальный compat-каталог на сервере `pc`: `/opt/nvidia-580.159-compat/`
(библиотеки вытащены из контейнера `jupyter-gpu-pc-*`, read-only tar-стримингом).
