## What is sim-box?

**sim-box** is a small Linux-based system (NanoPi / Raspberry Pi / any ARM host) connected to a USB modem with a SIM card.  
It allows you to **remotely receive SMS messages and monitor SIM status**, even when you are physically located in another country.

The project is designed for cases where a physical SIM card must stay in one place, while access to it is required remotely and continuously.

---

## Why does this exist?

Over the past years, many people have faced the following situation:

- they relocated or moved abroad for a long period of time;
- banking, government, and commercial services still require **SMS-based verification**;
- roaming is expensive, unreliable, or completely unavailable;
- the SIM card must **physically remain in the operator’s country**.

**sim-box** solves this problem in a simple and transparent way:

> The SIM card stays at home (or with trusted relatives),  
> while all SMS messages are delivered to you via Telegram.

---

## Typical use cases

- 🌍 **Relocation / living abroad**  
  Receiving SMS from banks, government portals, mobile operators.

- 🧳 **Long-term travel**  
  The SIM remains in the home country, while you continue to receive verification codes.

- 🏠 **Remote access to a “home” SIM card**  
  No need to keep a phone powered on or forward messages manually.

- 🔐 **2FA / OTP delivery**  
  Banking, email providers, cloud services, corporate systems.

---

## How it works (conceptually)

SIM card
↓
USB modem (ZTE MF112, Huawei, etc.)
↓
sim-box (Linux)
↓
Telegram bot → your phone


- The SIM card is inserted into a USB modem
- The modem is connected to the sim-box device
- sim-box communicates with the modem via AT commands
- Incoming SMS messages are forwarded to Telegram
- System health is monitored via a heartbeat mechanism

---

## What is implemented now

- ✅ USB modem initialization on system startup
- ✅ Automatic SIM state detection
- ✅ SIM PIN entry when required
- ✅ SMS reception and forwarding to Telegram
- ✅ Periodic heartbeat with diagnostics:
  - modem presence
  - SIM state
  - signal strength
  - system status
- ✅ systemd services and timers
- ✅ Secure handling of secrets (no credentials stored in the repository)

---

## What is planned

- 📞 Voice calls support (SIP / Asterisk)
- 🔄 Remote control (USSD, outgoing SMS)
- 🌐 VPS-based signaling and voice routing
- 📦 Packaging as a ready-to-use solution

---

## Project status

The project is **fully functional** and runs on real hardware.  
Development is active, with documentation evolving alongside new features.

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

