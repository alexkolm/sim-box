#!/bin/bash
set -euo pipefail

###############################################################################
# НАСТРОЙКИ
###############################################################################

MODEM_DEV="/dev/ttyUSB1"
ENV_FILE="/etc/simbox/telegram.env"
MODEM_ENV="/etc/simbox/modem.env"
SIM_STATE_FILE="/var/lib/simbox/sim.state"
STATE_DIR="/var/lib/simbox"
MODEM_MISSING_FLAG="$STATE_DIR/modem_missing.notified"

LOG_TAG="simbox-modem-init"

###############################################################################
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
###############################################################################

log() {
    echo "[$LOG_TAG] $*"
}

send_telegram() {
    local msg="$1"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        --data-urlencode text="$msg" >/dev/null || true
}

send_at() {
    echo -e "$1\r" > "$MODEM_DEV"
    sleep 0.5
}

read_modem() {
    timeout 2 cat "$MODEM_DEV" || true
}

set_sim_state() {
    printf '%s\n' "$1" > "${SIM_STATE_FILE}.tmp"
    mv "${SIM_STATE_FILE}.tmp" "$SIM_STATE_FILE"
}

###############################################################################
# ЗАГРУЗКА КОНФИГОВ
###############################################################################

if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
else
    log "telegram.env not found, Telegram disabled"
    send_telegram() { :; }
fi

if [[ -f "$MODEM_ENV" ]]; then
    # shellcheck disable=SC1090
    source "$MODEM_ENV"
else
    SIM_PIN=""
fi

mkdir -p "$STATE_DIR"
set_sim_state "UNKNOWN"

###############################################################################
# ОЖИДАНИЕ МОДЕМА
###############################################################################

log "waiting for modem $MODEM_DEV"

for _ in {1..20}; do
    if [[ -c "$MODEM_DEV" ]]; then
        break
    fi
    sleep 1
done

###############################################################################
# МОДЕМ НЕ НАЙДЕН
###############################################################################

if [[ ! -c "$MODEM_DEV" ]]; then
    log "modem not found, skipping init"

    if [[ ! -f "$MODEM_MISSING_FLAG" ]]; then
        send_telegram "⚠️ sim-box: modem not found on boot"
        touch "$MODEM_MISSING_FLAG"
    fi
    set_sim_state "ABSENT"
    exit 0
fi

# модем появился — сбрасываем флаг
rm -f "$MODEM_MISSING_FLAG"

###############################################################################
# ИНИЦИАЛИЗАЦИЯ МОДЕМА
###############################################################################

log "initializing modem"

send_at "ATZ"
send_at "ATE0"
send_at "AT+CMGF=1"
send_at "AT+CSCS=\"UCS2\""

###############################################################################
# ПРОВЕРКА SIM (устойчиво к SIM busy)
###############################################################################

MAX_RETRIES=10
RETRY_DELAY=2
NEED_PIN=0

for ((i=1; i<=MAX_RETRIES; i++)); do
    # очистка входного буфера
    timeout 1 cat "$MODEM_DEV" >/dev/null || true

    send_at "AT+CPIN?"
    sleep 1.5
    RESP="$(timeout 3 cat "$MODEM_DEV" || true)"

    log "CPIN attempt $i:"
    echo "$RESP" | sed 's/^/[RAW] /'

    # SIM готова
    if echo "$RESP" | grep -qi "READY"; then
        log "SIM READY"
	set_sim_state "READY"
        exit 0
    fi

    # SIM требует PIN
    if echo "$RESP" | grep -qi "SIM PIN"; then
        NEED_PIN=1
        break
    fi

    # SIM отсутствует физически
    if echo "$RESP" | grep -Eqi "SIM failure|NOT INSERTED|NO SIM"; then
        log "SIM card not detected"
	set_sim_state "ABSENT"
        send_telegram "⚠️ sim-box: SIM card not detected"
        exit 0
    fi

    # SIM временно занята — ждём
    if echo "$RESP" | grep -qi "SIM busy"; then
        log "SIM busy, waiting..."
        sleep "$RETRY_DELAY"
        continue
    fi

    # прочие ответы — пробуем ещё раз
    log "unexpected CPIN response, retrying"
    sleep "$RETRY_DELAY"
done

###############################################################################
# ВВОД PIN (если требуется)
###############################################################################

if [[ "$NEED_PIN" -eq 1 ]]; then
    if [[ -z "$SIM_PIN" ]]; then
        log "SIM PIN required but not configured"
	set_sim_state "PIN_REQUIRED"
        send_telegram "❌ sim-box: SIM PIN required but not configured"
        exit 0
    fi

    log "entering SIM PIN"
    send_at "AT+CPIN=\"${SIM_PIN}\""

    for ((i=1; i<=10; i++)); do
        sleep 2
        timeout 1 cat "$MODEM_DEV" >/dev/null || true
        send_at "AT+CPIN?"
        RESP="$(timeout 3 cat "$MODEM_DEV" || true)"

        log "PIN check attempt $i:"
        echo "$RESP" | sed 's/^/[RAW] /'

        if echo "$RESP" | grep -qi "READY"; then
            log "SIM unlocked successfully"
	    set_sim_state "READY"
            send_telegram "✅ sim-box: SIM unlocked successfully"
            exit 0
        fi

        if echo "$RESP" | grep -qi "SIM busy"; then
            log "SIM busy after PIN, waiting..."
            continue
        fi
    done

    log "SIM unlock did not confirm READY"
    send_telegram "⚠️ sim-box: SIM unlock timeout, check status"
    exit 0
fi

###############################################################################
# НЕОПРЕДЕЛЁННОЕ СОСТОЯНИЕ
###############################################################################

log "unknown SIM state after retries"
set_sim_state "UNKNOWN"
send_telegram "⚠️ sim-box: unknown SIM state on boot"
exit 0
