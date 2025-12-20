#!/bin/bash
set -euo pipefail

###############################################################################
# LOAD CONFIGURATION
###############################################################################

SIMBOX_CONF="/etc/simbox/simbox.conf"
SIMBOX_SECRETS="/etc/simbox/secrets.env"

if [[ -f "$SIMBOX_CONF" ]]; then
    # shellcheck disable=SC1090
    source "$SIMBOX_CONF"
else
    echo "[simbox-smsd] simbox.conf not found"
fi

if [[ -f "$SIMBOX_SECRETS" ]]; then
    # shellcheck disable=SC1090
    source "$SIMBOX_SECRETS"
else
    echo "[simbox-smsd] secrets.env not found"
fi

###############################################################################
# DEFAULTS (safety net)
###############################################################################

MODEM_DEV="${MODEM_DEV:-/dev/ttyUSB1}"

###############################################################################
# VALIDATION
###############################################################################

if [[ -z "${BOT_TOKEN:-}" || -z "${CHAT_ID:-}" ]]; then
    echo "[simbox-smsd] BOT_TOKEN or CHAT_ID not set, exiting"
    exit 0
fi

###############################################################################
# HELPERS
###############################################################################

send_at() {
    echo -e "$1\r" > "$MODEM_DEV"
    sleep 0.5
}

read_modem() {
    timeout 2 cat "$MODEM_DEV" || true
}

send_telegram() {
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        --data-urlencode text="$1" \
        > /dev/null
}

ucs2_to_utf8() {
    local hex="$1"
    echo "$hex" | xxd -r -p | iconv -f UTF-16BE -t UTF-8
}

###############################################################################
# INIT MODEM FOR SMS
###############################################################################

echo "[simbox-smsd] init modem"

send_at "ATZ"
send_at "ATE0"
send_at "AT+CMGF=1"
send_at "AT+CSCS=\"UCS2\""
send_at "AT+CNMI=2,1,0,0,0"

read_modem

echo "[simbox-smsd] ready, waiting for SMS"
send_telegram "📡 sim-box: SMS RAW daemon started"

###############################################################################
# MAIN LOOP
###############################################################################

while true; do
    if read -r line < "$MODEM_DEV"; then
        echo "[MODEM] $line"

        case "$line" in
            *"+CMTI:"*)
                IDX="$(echo "$line" | sed -E 's/.*,(.*)/\1/')"
                echo "[simbox-smsd] SMS index: $IDX"

                send_at "AT+CMGR=$IDX"
                RESP="$(read_modem)"

                echo "========== RAW SMS BEGIN =========="
                echo "$RESP"
                echo "=========== RAW SMS END ==========="

                SENDER_RAW="$(echo "$RESP" | grep '^+CMGR:' | sed -E 's/^\+CMGR:[^,]*,"([^"]+)".*/\1/')"
                SENDER_CONV="$(ucs2_to_utf8 "$SENDER_RAW" || echo "$SENDER_RAW")"

                echo "[simbox-smsd] RAW SENDER:  $SENDER_RAW"
                echo "[simbox-smsd] CONV SENDER: $SENDER_CONV"

                send_telegram "📩 *RAW SMS from sim-box*

From: $SENDER_CONV

$RESP"

                send_at "AT+CMGD=$IDX"
                ;;
        esac
    fi
done
