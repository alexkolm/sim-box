#!/bin/bash
set -euo pipefail

###############################################################################
# LOAD CONFIGURATION
###############################################################################

SIMBOX_CONF="/etc/simbox/simbox.conf"
SIMBOX_SECRETS="/etc/simbox/secrets.env"

[[ -f "$SIMBOX_CONF" ]] && source "$SIMBOX_CONF"
[[ -f "$SIMBOX_SECRETS" ]] && source "$SIMBOX_SECRETS"

###############################################################################
# DEFAULTS
###############################################################################

MODEM_DEV="${MODEM_DEV:-/dev/ttyUSB1}"
SIM_STATE_FILE="${SIM_STATE_FILE:-/var/lib/simbox/sim.state}"

###############################################################################
# VALIDATION
###############################################################################

if [[ -z "${MONTHLY_SMS_TARGET:-}" ]]; then
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

send_at() {
    echo -e "$1\r" > "$MODEM_DEV"
    sleep 0.5
}

read_modem() {
    timeout 3 cat "$MODEM_DEV" || true
}

###############################################################################
# PRECHECKS
###############################################################################

# Проверка SIM
if [[ ! -f "$SIM_STATE_FILE" ]] || [[ "$(cat "$SIM_STATE_FILE")" != "READY" ]]; then
    send_telegram "⚠️ sim-box: monthly SMS NOT sent — SIM not READY"
    exit 0
fi

# Проверка модема
if [[ ! -c "$MODEM_DEV" ]]; then
    send_telegram "⚠️ sim-box: monthly SMS NOT sent — modem not found"
    exit 0
fi

###############################################################################
# SEND SMS
###############################################################################

SMS_TEXT="${MONTHLY_SMS_TEXT:-тестовое ежемесячное сообщение}"

send_at "AT+CMGF=1"
send_at "AT+CSCS=\"UCS2\""
send_at "AT+CMGS=\"${MONTHLY_SMS_TARGET}\""
sleep 0.5
echo -ne "${SMS_TEXT}\x1A" > "$MODEM_DEV"

RESP="$(read_modem)"

if echo "$RESP" | grep -q "OK"; then
    send_telegram "✅ sim-box: monthly SMS sent to ${MONTHLY_SMS_TARGET}"
else
    send_telegram "❌ sim-box: monthly SMS FAILED to ${MONTHLY_SMS_TARGET}"
fi
