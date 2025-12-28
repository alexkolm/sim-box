#!/bin/bash
set -euo pipefail

###############################################################################
# LOAD CONFIGURATION
###############################################################################

SIMBOX_CONF="/etc/simbox/simbox.conf"
SIMBOX_SECRETS="/etc/simbox/secrets.env"

[[ -f "$SIMBOX_CONF" ]]    && source "$SIMBOX_CONF"
[[ -f "$SIMBOX_SECRETS" ]] && source "$SIMBOX_SECRETS"

###############################################################################
# DEFAULTS
###############################################################################

MODEM_DEV="${MODEM_DEV:-/dev/ttyUSB1}"
SIM_STATE_FILE="${SIM_STATE_FILE:-/var/lib/simbox/sim.state}"

SMS_TEXT="${MONTHLY_SMS_TEXT:-monthly message}"
SMS_TARGET="${MONTHLY_SMS_TARGET:-}"

###############################################################################
# VALIDATION
###############################################################################

if [[ -z "$SMS_TARGET" ]]; then
    echo "[simbox-monthly-sms] MONTHLY_SMS_TARGET not set, exiting"
    exit 0
fi

if [[ -z "${BOT_TOKEN:-}" || -z "${CHAT_ID:-}" ]]; then
    echo "[simbox-monthly-sms] Telegram not configured"
    exit 0
fi

###############################################################################
# HELPERS
###############################################################################

send_telegram() {
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        --data-urlencode text="$1" \
        > /dev/null
}

send_cmd() {
    echo -e "$1\r" > "$MODEM_DEV"
}

read_modem() {
    timeout "${1:-5}" cat "$MODEM_DEV" || true
}

###############################################################################
# PRECHECKS
###############################################################################

if [[ ! -f "$SIM_STATE_FILE" || "$(cat "$SIM_STATE_FILE")" != "READY" ]]; then
    send_telegram "⚠️ sim-box: monthly SMS NOT sent — SIM not READY"
    exit 0
fi

if [[ ! -c "$MODEM_DEV" ]]; then
    send_telegram "⚠️ sim-box: monthly SMS NOT sent — modem not found"
    exit 0
fi

###############################################################################
# SEND SMS (GSM, no '>' ожидания)
###############################################################################

send_cmd "AT"
sleep 0.3
send_cmd "AT+CMGF=1"
sleep 0.3
send_cmd "AT+CSCS=\"GSM\""
sleep 0.3

# очистить вход
read_modem 2 >/dev/null

# инициировать отправку
send_cmd "AT+CMGS=\"${SMS_TARGET}\""

# КРИТИЧНО: небольшая пауза, без ожидания '>'
sleep 1

# отправка текста + Ctrl+Z
echo -ne "${SMS_TEXT}\x1A" > "$MODEM_DEV"

# читать ответ
RESP="$(read_modem 15)"

if echo "$RESP" | grep -qE '\+CMGS:|OK'; then
    send_telegram "✅ sim-box: monthly SMS sent to ${SMS_TARGET}"
else
    send_telegram "❌ sim-box: monthly SMS FAILED to ${SMS_TARGET}"
fi

exit 0
