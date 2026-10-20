#!/bin/bash
# Проверка стека: все сервисы поднимаются из образов GHCR и отвечают на своих портах, данные
# переживают пересоздание контейнеров, резервная копия и восстановление возвращают данные.
#
# Использование: tests/stack_run.sh   (из каталога apps-stack; поднимает отдельный проект apps-stack-test)
set -u
cd "$(dirname "$0")/.."
# плагин docker compose (v2) или docker-compose 1.29 из Debian 12; DC можно задать снаружи
DC=${DC:-$(docker compose version >/dev/null 2>&1 && echo "docker compose" || echo docker-compose)}
export COMPOSE_PROJECT_NAME=apps-stack-test LISTEN_ADDR=127.0.0.1
export ARENDA_PORT=18180 BAKERY_PORT=18181 PRICE_TAGS_PORT=18182 TSG_BILLING_PORT=18183
fail=0
ok() { echo "ok    $*"; }
bad() { echo "FAIL  $*"; fail=1; }
created_cfg=0
if [ ! -f config/tsg-billing/cfg.json ]; then
    cp config/tsg-billing/cfg.json.example config/tsg-billing/cfg.json
    created_cfg=1
fi
BACKUPS=$(mktemp -d)
cleanup() {
    $DC down -v >/dev/null 2>&1
    rm -rf "$BACKUPS"
    [ "$created_cfg" = 0 ] || rm -f config/tsg-billing/cfg.json
}
trap cleanup EXIT
wait_http() { for _ in $(seq 100); do curl -sf "$1" >/dev/null && return 0; sleep 0.2; done; return 1; }
check_all() {
    wait_http "http://127.0.0.1:$ARENDA_PORT/api/version" && ok "$1: arenda $(curl -s "http://127.0.0.1:$ARENDA_PORT/api/version")" || bad "$1: arenda"
    wait_http "http://127.0.0.1:$BAKERY_PORT/api/version" && ok "$1: bakery $(curl -s "http://127.0.0.1:$BAKERY_PORT/api/version")" || bad "$1: bakery"
    wait_http "http://127.0.0.1:$PRICE_TAGS_PORT/api/products" && ok "$1: price-tags" || bad "$1: price-tags"
    wait_http "http://127.0.0.1:$TSG_BILLING_PORT/" && ok "$1: tsg-billing" || bad "$1: tsg-billing"
}
has_product() { curl -s "http://127.0.0.1:$PRICE_TAGS_PORT/api/products" | grep -q 'Хлеб белый'; }

$DC config -q && ok "docker-compose.yml разбирается" || { bad "docker-compose.yml"; exit 1; }
$DC pull -q && $DC up -d >/dev/null 2>&1 || { bad "не поднялся"; $DC logs | tail -20; exit 1; }
check_all "запуск"
[ "$($DC exec -T arenda date +%Z)" = MSK ] && ok "TZ из .env по умолчанию" || bad "часовой пояс arenda"

curl -sf -X POST "http://127.0.0.1:$PRICE_TAGS_PORT/api/products" -d '{"name":"Хлеб белый","unit":"шт","price_kop":4590}' >/dev/null
$DC down >/dev/null 2>&1 && $DC up -d >/dev/null 2>&1
check_all "пересоздание"
has_product && ok "данные в томах после пересоздания" || bad "данные потеряны после пересоздания"

scripts/backup.sh "$BACKUPS" >/dev/null 2>&1 && ls "$BACKUPS"/*/{arenda,bakery,price-tags,tsg-billing}.tgz >/dev/null 2>&1 \
    && ok "резервная копия: 4 архива" || bad "резервная копия"
curl -sf -X DELETE "http://127.0.0.1:$PRICE_TAGS_PORT/api/products/$(curl -s "http://127.0.0.1:$PRICE_TAGS_PORT/api/products" | sed -n 's/.*"id":\([0-9]*\).*/\1/p' | head -1)" >/dev/null
has_product && bad "товар не удалился перед восстановлением"
scripts/restore.sh "$(ls -d "$BACKUPS"/*/ | head -1)" >/dev/null 2>&1 || bad "restore.sh завершился с ошибкой"
wait_http "http://127.0.0.1:$PRICE_TAGS_PORT/api/products"
has_product && ok "восстановление из копии" || bad "после восстановления нет данных"
[ "$($DC exec -T price-tags id -u)" = 10001 ] && $DC exec -T price-tags test -w /data/catalog.json \
    && ok "после восстановления права на данные сохранены" || bad "права после восстановления"
exit $fail
