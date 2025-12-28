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
MODEM_USB_VENDOR="${MODEM_USB_VENDOR:-19d2}"
STATE_DIR="${STATE_DIR:-/var/lib/simbox}"
SIM_STATE_FILE="${SIM_STATE_FILE:-$STATE_DIR/sim.state}"
BALANCE_CMD="/usr/local/bin/simbox-balance.sh"

###############################################################################
# HOST INFO
###############################################################################

HOSTNAME="$(hostname)"
DATE="$(date '+%Y-%m-%d %H:%M:%S')"

###############################################################################
# SYSTEM INFO
###############################################################################

CPU_TEMP_RAW="$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0)"
CPU_TEMP="$(awk "BEGIN {printf \"%.1f\", ${CPU_TEMP_RAW:-0}/1000}")"

MEM_FREE="$(free -m | awk '/Mem:/ {print $4}')"
MEM_TOTAL="$(free -m | awk '/Mem:/ {print $2}')"

UPTIME="$(uptime -p)"

###############################################################################
# MODEM STATUS
###############################################################################

MODEM_STATUS="❌ not found"
lsusb 2>/dev/null | grep -qi "$MODEM_USB_VENDOR" && MODEM_STATUS="✅ found"

###############################################################################
# SIM STATE
###############################################################################

SIM_STATUS="❓ unknown"

if [[ -f "$SIM_STATE_FILE" ]]; then
    case "$(cat "$SIM_STATE_FILE")" in
        READY)         SIM_STATUS="✅ READY" ;;
        PIN_REQUIRED)  SIM_STATUS="🔒 PIN required" ;;
        ABSENT)        SIM_STATUS="❌ not inserted" ;;
        BUSY)          SIM_STATUS="⏳ busy" ;;
        UNKNOWN)       SIM_STATUS="⚠ unknown" ;;
        *)             SIM_STATUS="⚠ invalid state" ;;
    esac
fi

###############################################################################
# SIGNAL LEVEL (CSQ)
###############################################################################

CSQ_STATUS="❓ unknown"

if [[ -c "$MODEM_DEV" ]]; then
    timeout 1 cat "$MODEM_DEV" >/dev/null 2>&1 || true
    echo -e "AT+CSQ\r" > "$MODEM_DEV"

    RESP="$(timeout 5 cat "$MODEM_DEV" || true)"
    CSQ_VAL="$(echo "$RESP" | sed -nE 's/.*\+CSQ:[[:space:]]*([0-9]+),.*/\1/p' | head -n1)"

    [[ -n "$CSQ_VAL" && "$CSQ_VAL" != "99" ]] && CSQ_STATUS="📶 CSQ=$CSQ_VAL"
    [[ "$CSQ_VAL" == "99" ]] && CSQ_STATUS="❌ no signal"
fi

###############################################################################
# BALANCE (USSD via simbox-balance.sh)
###############################################################################

BALANCE_TEXT="💰 Balance:\n❌ unavailable"

if [[ -x "$BALANCE_CMD" ]]; then
    if BAL_OUT="$(timeout 25 "$BALANCE_CMD" 2>/dev/null || true)"; then
        if echo "$BAL_OUT" | grep -q "💰 Balance:"; then
            BALANCE_TEXT="$(echo "$BAL_OUT" | sed '1d')"
        fi
    fi
fi

###############################################################################
# TELEGRAM
###############################################################################

[[ -z "${BOT_TOKEN:-}" || -z "${CHAT_ID:-}" ]] && exit 0

TEXT="📡 *Sim-box alive*
🖥 Host: \`$HOSTNAME\`
🕒 Time: $DATE

🔌 Modem: $MODEM_STATUS
📱 SIM: $SIM_STATUS
📶 Signal: $CSQ_STATUS

💰 Balance:
$BALANCE_TEXT

🌡 CPU temp: ${CPU_TEMP}°C
💾 RAM free: ${MEM_FREE}/${MEM_TOTAL} MB
⏱ Uptime: $UPTIME"

curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d chat_id="$CHAT_ID" \
  -d parse_mode="Markdown" \
  --data-urlencode text="$TEXT" >/dev/null
