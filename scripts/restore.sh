#!/bin/bash
# Восстановление данных из копии scripts/backup.sh: содержимое томов заменяется архивами из каталога.
# Настройки (config, .env) не трогаются: при необходимости скопировать их из каталога копии вручную.
#
# Использование: sudo scripts/restore.sh backups/ГГГГММДД-ЧЧММСС [сервис ...]   (по умолчанию все)
set -eu
cd "$(dirname "$0")/.."
# плагин docker compose (v2) или docker-compose 1.29 из Debian 12; DC можно задать снаружи
DC=${DC:-$(docker compose version >/dev/null 2>&1 && echo "docker compose" || echo docker-compose)}
SRC=$(realpath "${1:?укажите каталог копии}")
shift
SERVICES=${*:-arenda bakery price-tags tsg-billing}
for s in $SERVICES; do
    [ -f "$SRC/$s.tgz" ] || { echo "нет $SRC/$s.tgz" >&2; exit 1; }
done
$DC up --no-start
$DC stop
trap '$DC start' EXIT
for s in $SERVICES; do
    cid=$($DC ps -aq "$s")
    docker run --rm --volumes-from "$cid" -v "$SRC:/in:ro" debian:trixie-slim \
        sh -c "find /data -mindepth 1 -delete && tar xzf /in/$s.tgz -C /data"
    echo "восстановлен $s"
done
