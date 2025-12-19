# sim-box

SIM-box — это автономный GSM-шлюз на базе NanoPi + USB-модема.

## Возможности
- Приём SMS с SIM-карты
- Пересылка SMS в Telegram
- Heartbeat-уведомления о состоянии устройства
- Автоматическая инициализация модема (PIN, SIM state)
- Устойчив к перезагрузкам и пропаданию модема

## Структура
bin/ — исполняемые скрипты
systemd/ — systemd-сервисы и таймеры
etc/ — примеры конфигураций


## Установка (кратко)
1. Скопировать скрипты в `/usr/local/bin`
2. Скопировать systemd-файлы в `/etc/systemd/system`
3. Создать `/etc/simbox` и заполнить конфиги
4. `systemctl daemon-reload`
5. `systemctl enable --now simbox-modem-init.service`

## Требования
- Linux (Debian / Armbian)
- USB GSM-модем (ZTE MF112 проверен)
- SIM-карта с SMS

