# apps-stack

Запуск на одной машине через Docker Compose четырёх веб-приложений:

| Сервис | Назначение | Порт | Образ |
|---|---|---|---|
| [arenda](https://github.com/khromenokroman/arenda) | договоры аренды нежилых помещений | 8080 | `ghcr.io/khromenokroman/arenda` |
| [bakery](https://github.com/khromenokroman/bakery) | учёт продукции пекарни | 8081 | `ghcr.io/khromenokroman/bakery` |
| [price-tags](https://github.com/khromenokroman/price-tags) | справочники товаров и печать ценников | 8082 | `ghcr.io/khromenokroman/price-tags` |
| [tsg-billing](https://github.com/khromenokroman/tsg-billing) | участники ТСЖ и квитанции | 8083 | `ghcr.io/khromenokroman/tsg-billing` |

Образы собираются в CI каждого проекта и публикуются по тегу версии. Все работают от непривилегированного
пользователя (uid 10001), данные каждого сервиса в своём томе.

## Установка

Debian 12 или 13:

```sh
sudo apt install docker.io docker-compose git
git clone https://github.com/khromenokroman/apps-stack.git
cd apps-stack
cp .env.example .env
cp config/tsg-billing/cfg.json.example config/tsg-billing/cfg.json
chmod 644 config/tsg-billing/cfg.json
sudo docker-compose up -d
```

В `config/tsg-billing/cfg.json` вписать наименование получателя и реквизиты для квитанций и QR-кода
(описание полей в [README tsg-billing](https://github.com/khromenokroman/tsg-billing#параметры-cfgjson)),
`path_db` не менять. Без файла Docker создаст на его месте каталог и tsg-billing не запустится.

Интерфейсы: `http://адрес:8080/` (arenda), `:8081` (bakery), `:8082` (price-tags), `:8083` (tsg-billing).
В arenda и bakery при первом входе создаётся администратор. В price-tags и tsg-billing авторизации нет,
а пароли arenda и bakery идут по сети без шифрования, поэтому порты открывать только в доверенной сети
или ставить HTTPS-прокси.

Команда `docker-compose` из пакета Debian 12 (1.29) и `docker compose` (плагин v2) работают одинаково.

## Настройки

Файл `.env` рядом с `docker-compose.yml`:

| Переменная | По умолчанию | Назначение |
|---|---|---|
| `LISTEN_ADDR` | `0.0.0.0` | адрес хоста для всех портов; `127.0.0.1` - только с этой машины, например за прокси |
| `ARENDA_PORT`, `BAKERY_PORT`, `PRICE_TAGS_PORT`, `TSG_BILLING_PORT` | `8080`-`8083` | порты на хосте |
| `TZ` | `Europe/Kaliningrad` | часовой пояс: даты документов и копии по расписанию в arenda и bakery |
| `ARENDA_TAG`, `BAKERY_TAG`, `PRICE_TAGS_TAG`, `TSG_BILLING_TAG` | `latest` | версии образов |

После правки: `sudo docker-compose up -d` (пересоздаются только изменённые сервисы). Для настроек
tsg-billing: `sudo docker-compose restart tsg-billing`.

Журналы: `sudo docker-compose logs -f [сервис]`, на каждый контейнер хранится до 3 файлов по 10 МБ.

## Обновление

```sh
git pull
sudo docker-compose pull
sudo docker-compose up -d
```

Схемы баз arenda и bakery обновляются при запуске новой версии. Чтобы не получать обновления
неожиданно, закрепить версии в `.env` (например `BAKERY_TAG=0.30.0.0`) и менять их вручную. Перед
обновлением полезно сделать резервную копию.

## Резервные копии

```sh
sudo scripts/backup.sh                    # в backups/ГГГГММДД-ЧЧММСС/
sudo scripts/backup.sh /mnt/usb/apps      # в другой каталог
```

Сервисы останавливаются на несколько секунд, данные каждого тома упаковываются в отдельный архив
(`arenda.tgz`, `bakery.tgz`, `price-tags.tgz`, `tsg-billing.tgz`), рядом копируются `config/` и `.env`.
Каталог `backups/` на том же диске не спасёт при отказе диска: копировать на другой носитель. Копии по
расписанию внутри arenda и bakery продолжают делаться в их томах.

Восстановление (содержимое томов заменяется архивами, текущие данные теряются):

```sh
sudo scripts/restore.sh backups/20261020-030000               # все сервисы
sudo scripts/restore.sh backups/20261020-030000 bakery        # только bakery
```

Перенос на другую машину: установить apps-stack, скопировать туда каталог копии и выполнить
`scripts/restore.sh`, настройки взять из `config/` и `.env` в каталоге копии.

## Удаление

`sudo docker-compose down` останавливает и удаляет контейнеры, тома с данными остаются.
`sudo docker-compose down -v` удаляет и тома: все данные всех сервисов.

## Проверка

`sudo tests/stack_run.sh` поднимает стек отдельным проектом `apps-stack-test` на портах 18180-18183,
проверяет ответы всех сервисов, сохранность данных при пересоздании, резервную копию и восстановление,
затем удаляет его вместе с томами. CI запускает проверку на каждый push и раз в неделю на свежих `latest`.

## Лицензия

GPL-3.0, см. `LICENSE`.
