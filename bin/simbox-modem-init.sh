#!/bin/bash
set -euo pipefail

###############################################################################
# LOAD CONFIGURATION
###############################################################################

SIMBOX_CONF="/etc/simbox/simbox.conf"
SIMBOX_SECRETS="/etc/simbox/secrets.env"

LOG_TAG="simbox-modem-init"

[[ -f "$SIMBOX_CONF" ]] && source "$SIMBOX_CONF"
[[ -f "$SIMBOX_SECRETS" ]] && source "$SIMBOX_SECRETS"

###############################################################################
# DEFAULTS (safety net)
###############################################################################

MODEM_DEV="${MODEM_DEV:-/dev/ttyUSB1}"
MODEM_WAIT_SECONDS="${MODEM_WAIT_SECONDS:-20}"
MODEM_RETRY_DELAY="${MODEM_RETRY_DELAY:-2}"
MODEM_CPIN_MAX_RETRIES="${MODEM_CPIN_MAX_RETRIES:-10}"
MODEM_PIN_CHECK_RETRIES="${MODEM_PIN_CHECK_RETRIES:-10}"

STATE_DIR="${STATE_DIR:-/var/lib/simbox}"
SIM_STATE_FILE="${SIM_STATE_FILE:-$STATE_DIR/sim.state}"
MODEM_MISSING_FLAG="${MODEM_MISSING_FLAG:-$STATE_DIR/modem_missing.notified}"

NOTIFY_MODEM_MISSING="${NOTIFY_MODEM_MISSING:-1}"
NOTIFY_SIM_ABSENT="${NOTIFY_SIM_ABSENT:-1}"
NOTIFY_SIM_UNLOCKED="${NOTIFY_SIM_UNLOCKED:-1}"

SIM_PIN="${SIM_PIN:-}"

mkdir -p "$STATE_DIR"

###############################################################################
# HELPERS
###############################################################################

log() {
    echo "[$LOG_TAG] $*"
}

send_telegram() {
    local msg="$1"
    [[ -z "${BOT_TOKEN:-}" || -z "${CHAT_ID:-}" ]] && return 0

    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        --data-urlencode text="$msg" >/dev/null || true
}

send_at() {
    echo -e "$1\r" > "$MODEM_DEV"
    sleep 0.5
}

set_sim_state() {
    printf '%s\n' "$1" > "${SIM_STATE_FILE}.tmp"
    mv "${SIM_STATE_FILE}.tmp" "$SIM_STATE_FILE"
}

###############################################################################
# INITIAL STATE
###############################################################################

set_sim_state "UNKNOWN"

###############################################################################
# WAIT FOR MODEM
###############################################################################

log "waiting for modem $MODEM_DEV"

for ((i=1; i<=MODEM_WAIT_SECONDS; i++)); do
    [[ -c "$MODEM_DEV" ]] && break
    sleep 1
done

###############################################################################
# MODEM NOT FOUND
###############################################################################

if [[ ! -c "$MODEM_DEV" ]]; then
    log "modem not found, skipping init"
    set_sim_state "ABSENT"

    if [[ "$NOTIFY_MODEM_MISSING" -eq 1 && ! -f "$MODEM_MISSING_FLAG" ]]; then
        send_telegram "⚠️ sim-box: modem not found on boot"
        touch "$MODEM_MISSING_FLAG"
    fi

    exit 0
fi

rm -f "$MODEM_MISSING_FLAG"

###############################################################################
# MODEM INIT
###############################################################################

log "initializing modem"

send_at "ATZ"
send_at "ATE0"
send_at "AT+CMGF=1"
send_at "AT+CSCS=\"UCS2\""

###############################################################################
# SIM CHECK
###############################################################################

NEED_PIN=0

for ((i=1; i<=MODEM_CPIN_MAX_RETRIES; i++)); do
    timeout 1 cat "$MODEM_DEV" >/dev/null || true

    send_at "AT+CPIN?"
    sleep 1.5
    RESP="$(timeout 3 cat "$MODEM_DEV" || true)"

    log "CPIN attempt $i:"
    echo "$RESP" | sed 's/^/[RAW] /'

    if echo "$RESP" | grep -qi "READY"; then
        log "SIM READY"
        set_sim_state "READY"
        exit 0
    fi

    if echo "$RESP" | grep -qi "SIM PIN"; then
        NEED_PIN=1
        break
    fi

    if echo "$RESP" | grep -Eqi "SIM failure|NOT INSERTED|NO SIM"; then
        log "SIM card not detected"
        set_sim_state "ABSENT"

        [[ "$NOTIFY_SIM_ABSENT" -eq 1 ]] && \
            send_telegram "⚠️ sim-box: SIM card not detected"

        exit 0
    fi

    if echo "$RESP" | grep -qi "SIM busy"; then
        log "SIM busy, waiting..."
        sleep "$MODEM_RETRY_DELAY"
        continue
    fi

    log "unexpected CPIN response, retrying"
    sleep "$MODEM_RETRY_DELAY"
done

###############################################################################
# ENTER PIN
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

    for ((i=1; i<=MODEM_PIN_CHECK_RETRIES; i++)); do
        sleep 2
        timeout 1 cat "$MODEM_DEV" >/dev/null || true

        send_at "AT+CPIN?"
        RESP="$(timeout 3 cat "$MODEM_DEV" || true)"

        log "PIN check attempt $i:"
        echo "$RESP" | sed 's/^/[RAW] /'

        if echo "$RESP" | grep -qi "READY"; then
            log "SIM unlocked successfully"
            set_sim_state "READY"

            [[ "$NOTIFY_SIM_UNLOCKED" -eq 1 ]] && \
                send_telegram "✅ sim-box: SIM unlocked successfully"

            exit 0
        fi

        if echo "$RESP" | grep -qi "SIM busy"; then
            log "SIM busy after PIN, waiting..."
            sleep "$MODEM_RETRY_DELAY"
        fi
    done

    log "SIM unlock timeout"
    send_telegram "⚠️ sim-box: SIM unlock timeout"
    exit 0
fi

###############################################################################
# FALLBACK
###############################################################################

log "unknown SIM state after retries"
set_sim_state "UNKNOWN"
send_telegram "⚠️ sim-box: unknown SIM state on boot"
exit 0
