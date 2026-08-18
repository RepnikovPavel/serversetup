# Корпоративные CA-сертификаты (docker/certs/)

Сюда кладутся корневые CA вашей корпоративной сети (`*.crt`, PEM), если на пути
стоит TLS-инспектор (SSL inspection): он подменяет сертификаты сайтов, и установка
Studio падает с `invalid peer certificate: UnknownIssuer`.

Dockerfile при сборке добавит каждый `*.crt` отсюда в системное хранилище образа
(`update-ca-certificates`). Папка пуста — образ не меняется.

**`*.crt` здесь в .gitignore — не коммитьте их:** в сертификате имена вашей
организации/доменов.

Как получить CA с хоста, где сеть уже работает (Ubuntu/Astra/Debian):

```sh
# посмотреть, кем подписан подменённый сертификат
echo | openssl s_client -connect huggingface.co:443 -servername huggingface.co 2>/dev/null | openssl x509 -noout -issuer

# скопировать локальные корпоративные CA в проект
cp /usr/local/share/ca-certificates/*.crt /path/to/serversetup/unsloth/docker/certs/
```
