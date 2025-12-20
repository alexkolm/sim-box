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
SIM_STATE_FILE="${SIM_STATE_FILE:-/var/lib/simbox/sim.state}"

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

check_modem_ready() {
    # модем отсутствует
    [[ ! -c "$MODEM_DEV" ]] && return 1

    # SIM состояние известно и плохое
    if [[ -f "$SIM_STATE_FILE" ]]; then
        case "$(cat "$SIM_STATE_FILE")" in
            READY) return 0 ;;
            *)     return 2 ;;
        esac
    fi

    # если состояния нет — считаем, что не готов
    return 2
}

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

echo "[simbox-smsd] waiting for modem and SIM"

for _ in {1..30}; do
    if check_modem_ready; then
        break
    fi
    sleep 2
done

if ! check_modem_ready; then
    echo "[simbox-smsd] modem or SIM not ready, exiting"
    exit 0
fi

echo "[simbox-smsd] init modem for SMS"

send_at "ATZ"
send_at "ATE0"
send_at "AT+CMGF=1"
send_at "AT+CSCS=\"UCS2\""
send_at "AT+CNMI=2,1,0,0,0"

read_modem

###############################################################################
# MAIN LOOP
###############################################################################

while true; do
    # модем пропал — пауза и retry
    if [[ ! -c "$MODEM_DEV" ]]; then
        echo "[simbox-smsd] modem disappeared, waiting..."
        sleep 5
        continue
    fi

    if ! read -r line < "$MODEM_DEV"; then
        echo "[simbox-smsd] read error, retrying..."
        sleep 1
        continue
    fi

        echo "[MODEM] $line"

        case "$line" in
            *"+CMTI:"*)
                IDX="$(echo "$line" | sed -E 's/.*,(.*)/\1/')"
                echo "[simbox-smsd] SMS index: $IDX"

                send_at "AT+CMGR=$IDX"
                RESP="$(read_modem)"

		if ! echo "$RESP" | grep -q "^+CMGR:"; then
    		    echo "[simbox-smsd] invalid SMS response, skipping"
    		    continue
		fi


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
    sleep 0.1
done
