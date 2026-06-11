# xrs

Набор скриптов для управления [Xray-core](https://github.com/XTLS/Xray-core) на Linux: переключение профилей, добавление серверов из VLESS-ссылок и подписок, диагностика, обновление geo-файлов.

## Зависимости

```bash
sudo apt install jq fzf curl
```

[Xray-core](https://github.com/XTLS/Xray-core/releases) должен быть установлен и настроен как systemd-сервис `xray`.

## Установка

```bash
git clone git@github.com:SmirnAA/xrs.git
cd xrs
sudo ./install.sh
```

Скрипт скопирует утилиты в `/usr/local/bin/` и создаст директорию для профилей.

## Быстрый старт

### 1. Добавить сервер

```bash
xrs-add 'vless://uuid@host:443?security=reality&pbk=...&sni=example.com#finland'
```

Или без аргументов — скрипт попросит вставить ссылку и ввести имя:

```bash
xrs-add
```

### 2. Добавить подписку

```bash
xrs sub add 'https://example.com/sub/token' netherlands
```

Скрипт скачает подписку (base64 или plaintext), развернёт каждый VLESS-сервер в отдельный профиль `netherlands:<имя>` и пропустит ссылки других протоколов (vmess/ss/trojan).

```bash
xrs sub update [name]   # пере-синхронизировать (все, если без имени)
xrs sub rm [name]       # удалить подписку и её профили
xrs sub ls              # список подписок
```

При обновлении профили серверов, исчезнувших из подписки, удаляются (активный — сохраняется).

### 3. Переключить профиль

```bash
xrs
```

Откроется интерактивный выбор через fzf. Профили подписок видны наравне с обычными. После выбора xray перезапустится автоматически.

### 4. Проверить статус

```bash
xrs-status
```

Покажет: активный профиль, состояние сервиса, порты, связь с сервером, работу прокси, split-routing, geo-файлы и DNS.

### 5. Обновить geo-файлы

```bash
sudo xrs-update-geo
```

Скачает свежие `geoip.dat` и `geosite.dat`, проверит совместимость с конфигом и перезапустит xray. При ошибке — автоматический откат.

## Структура

```
/usr/local/bin/
  xrs              — переключение профилей (fzf) + диспетчер подкоманд
  xrs-add          — добавление VLESS-сервера
  xrs-rm           — удаление профиля
  xrs-sub          — управление подписками (add/update/rm/ls)
  xrs-status       — диагностика
  xrs-update-geo   — обновление geo-файлов

/usr/local/lib/xrs/
  build.sh         — общая логика парсинга VLESS-URI и сборки конфига

/etc/xray/profiles/
  *.json           — профили (xrs-add и развёрнутые подписки)

/etc/xray/subscriptions/
  *.json           — манифесты подписок (url + список профилей)

/usr/local/etc/xray/
  config.json      — симлинк на активный профиль
```
