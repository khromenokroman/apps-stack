#!/bin/bash
# Резервная копия данных всех сервисов в backups/ГГГГММДД-ЧЧММСС/: по архиву на сервис, настройки и .env.
# Сервисы на время копии останавливаются (несколько секунд), чтобы базы SQLite и JSON были целыми.
#
# Использование: sudo scripts/backup.sh [каталог для копий, по умолчанию backups]
set -eu
cd "$(dirname "$0")/.."
# плагин docker compose (v2) или docker-compose 1.29 из Debian 12; DC можно задать снаружи
DC=${DC:-$(docker compose version >/dev/null 2>&1 && echo "docker compose" || echo docker-compose)}
SERVICES="arenda bakery price-tags tsg-billing"
OUT=$(realpath -m "${1:-backups}")/$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"
$DC stop
trap '$DC start' EXIT
for s in $SERVICES; do
    cid=$($DC ps -aq "$s")
    [ -n "$cid" ] || { echo "нет контейнера $s: сначала $DC up -d" >&2; exit 1; }
    docker run --rm --volumes-from "$cid" -v "$OUT:/out" debian:trixie-slim tar czf "/out/$s.tgz" -C /data .
done
cp -a config "$OUT/"
[ ! -f .env ] || cp -a .env "$OUT/"
echo "копия: $OUT"
