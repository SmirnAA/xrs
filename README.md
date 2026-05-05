# xrs

Набор скриптов для управления [Xray-core](https://github.com/XTLS/Xray-core) на Linux: переключение профилей, добавление серверов из VLESS-ссылок, диагностика, обновление geo-файлов.

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

### 2. Переключить профиль

```bash
xrs
```

Откроется интерактивный выбор через fzf. После выбора xray перезапустится автоматически.

### 3. Проверить статус

```bash
xrs-status
```

Покажет: активный профиль, состояние сервиса, порты, связь с сервером, работу прокси, split-routing, geo-файлы и DNS.

### 4. Обновить geo-файлы

```bash
sudo xrs-update-geo
```

Скачает свежие `geoip.dat` и `geosite.dat`, проверит совместимость с конфигом и перезапустит xray. При ошибке — автоматический откат.

## Структура

```
/usr/local/bin/
  xrs              — переключение профилей (fzf)
  xrs-add          — добавление VLESS-сервера
  xrs-status       — диагностика
  xrs-update-geo   — обновление geo-файлов

/etc/xray/profiles/
  *.json           — профили (генерируются через xrs-add)

/usr/local/etc/xray/
  config.json      — симлинк на активный профиль
```
