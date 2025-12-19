#!/bin/bash
set -euo pipefail

MODEM="/dev/ttyUSB1"
ENV_FILE="/etc/simbox/telegram.env"

# загрузка токена
source "$ENV_FILE"

send_at() {
    echo -e "$1\r" > "$MODEM"
    sleep 0.5
}

read_modem() {
    timeout 2 cat "$MODEM" || true
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

echo "[simbox-smsd] init modem"

send_at "ATZ"
send_at "ATE0"
send_at "AT+CMGF=1"
send_at "AT+CSCS=\"UCS2\""
send_at "AT+CNMI=2,1,0,0,0"

read_modem

echo "[simbox-smsd] ready, waiting for SMS"
send_telegram "📡 sim-box: SMS RAW-демон запущен"

while true; do
    if read -r line < "$MODEM"; then
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

		SENDER="$(echo "$RESP" | grep '^+CMGR:' | sed -E 's/^\+CMGR:[^,]*,"([^"]+)".*/\1/')"
		SENDER_CONV="$(ucs2_to_utf8 "$SENDER" || echo "$SENDER")"

		echo "[simbox-smsd] RAW SENDER: $SENDER"
		echo "[simbox-smsd] CONV SENDER: $SENDER_CONV"

                send_telegram "📩 RAW SMS from sim-box:

$RESP"

                send_at "AT+CMGD=$IDX"
                ;;
        esac
    fi
done
