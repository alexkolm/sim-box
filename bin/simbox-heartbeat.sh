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
    echo "[simbox-heartbeat] simbox.conf not found"
fi

if [[ -f "$SIMBOX_SECRETS" ]]; then
    # shellcheck disable=SC1090
    source "$SIMBOX_SECRETS"
else
    echo "[simbox-heartbeat] secrets.env not found"
fi

###############################################################################
# DEFAULTS (safety net)
###############################################################################

MODEM_DEV="${MODEM_DEV:-/dev/ttyUSB1}"
MODEM_USB_VENDOR="${MODEM_USB_VENDOR:-19d2}"
STATE_DIR="${STATE_DIR:-/var/lib/simbox}"
SIM_STATE_FILE="${SIM_STATE_FILE:-$STATE_DIR/sim.state}"

###############################################################################
# HOST INFO
###############################################################################

HOSTNAME="$(hostname)"
DATE="$(date '+%Y-%m-%d %H:%M:%S')"

###############################################################################
# SYSTEM INFO
###############################################################################

CPU_TEMP_RAW="$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0)"
if [[ "$CPU_TEMP_RAW" =~ ^[0-9]+$ ]]; then
    CPU_TEMP="$(awk "BEGIN {printf \"%.1f\", $CPU_TEMP_RAW/1000}")"
else
    CPU_TEMP="n/a"
fi

MEM_FREE="$(free -m | awk '/Mem:/ {print $4}')"
MEM_TOTAL="$(free -m | awk '/Mem:/ {print $2}')"

UPTIME="$(uptime -p)"

###############################################################################
# MODEM STATUS
###############################################################################

MODEM_STATUS="❌ not found"

if lsusb 2>/dev/null | grep -qi "${MODEM_USB_VENDOR:-19d2}"; then
    MODEM_STATUS="✅ found"
fi

###############################################################################
# SIM STATE (from modem-init)
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
else
    SIM_STATUS="❓ no data"
fi

###############################################################################
# SIGNAL LEVEL (CSQ)
###############################################################################

CSQ_STATUS="❓ unknown"

if [[ -c "$MODEM_DEV" ]]; then
    {
        echo -e "AT+CSQ\r"
        sleep 0.3
    } > "$MODEM_DEV"

    RESP="$(timeout 2 cat "$MODEM_DEV" || true)"

    CSQ_VAL="$(echo "$RESP" | sed -nE 's/.*\+CSQ: ([0-9]+),.*/\1/p' | head -n1)"

    if [[ -n "$CSQ_VAL" ]]; then
        if [[ "$CSQ_VAL" == "99" ]]; then
            CSQ_STATUS="❌ no signal"
        else
            CSQ_STATUS="📶 CSQ=$CSQ_VAL"
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

🌡 CPU temp: ${CPU_TEMP}°C
💾 RAM free: ${MEM_FREE}/${MEM_TOTAL} MB
⏱ Uptime: $UPTIME"

curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d chat_id="${CHAT_ID}" \
  -d parse_mode="Markdown" \
  --data-urlencode text="$TEXT" >/dev/null
