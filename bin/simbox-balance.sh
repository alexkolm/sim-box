#!/bin/bash
# simbox-balance.sh
# Read balance via USSD (configurable), decode UCS2, print result

set -u
# deliberately WITHOUT set -e / pipefail

###############################################################################
# LOAD CONFIG
###############################################################################

SIMBOX_CONF="/etc/simbox/simbox.conf"

if [[ -f "$SIMBOX_CONF" ]]; then
    # shellcheck disable=SC1090
    source "$SIMBOX_CONF"
fi

###############################################################################
# CONFIG / DEFAULTS
###############################################################################

MODEM_DEV="${MODEM_DEV:-/dev/ttyUSB1}"
USSD_CODE="${USSD_BALANCE:-*100#}"
READ_TIMEOUT=20

###############################################################################
# UCS2 → UTF-8
###############################################################################

decode_ucs2() {
    local hex="$1"
    hex="$(echo "$hex" | tr -d '\r\n ')"
    echo "$hex" | xxd -r -p | iconv -f UTF-16BE -t UTF-8 2>/dev/null
}

###############################################################################
# SANITY CHECK
###############################################################################

if [[ ! -c "$MODEM_DEV" ]]; then
    echo "💰 Balance:"
    echo "❌ modem not available"
    exit 1
fi

###############################################################################
# PREPARE MODEM
###############################################################################

{
    echo -e "AT\r"
    sleep 0.2
    echo -e "AT+CMGF=1\r"
    sleep 0.2
    echo -e "AT+CSCS=\"UCS2\"\r"
    sleep 0.2
    echo -e "AT+CUSD=1\r"
    sleep 0.2
} > "$MODEM_DEV"

# flush input buffer
timeout 2 cat "$MODEM_DEV" >/dev/null 2>&1 || true

###############################################################################
# SEND USSD
###############################################################################

echo -e "AT+CUSD=1,\"$USSD_CODE\",15\r" > "$MODEM_DEV"

###############################################################################
# READ RESPONSE
###############################################################################

RAW="$(timeout "$READ_TIMEOUT" cat "$MODEM_DEV" || true)"

###############################################################################
# EXTRACT +CUSD
###############################################################################

CUSD_LINE="$(
    echo "$RAW" \
    | tr -d '\r' \
    | sed -nE 's/.*\+CUSD:[[:space:]]*[0-9]+,"([^"]+)".*/\1/p' \
    | head -n1
)"

if [[ -z "$CUSD_LINE" ]]; then
    echo "💰 Balance:"
    echo "❌ USSD response not received"
    exit 2
fi

###############################################################################
# DECODE AND PRINT
###############################################################################

DECODED="$(decode_ucs2 "$CUSD_LINE")"

echo "💰 Balance:"
echo "$DECODED"

exit 0
