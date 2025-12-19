#!/bin/bash
set -e

source /etc/simbox/telegram.env

MODEM_DEV="/dev/ttyUSB1"
SIM_STATE_FILE="/var/lib/simbox/sim.state"

HOSTNAME=$(hostname)
DATE=$(date "+%Y-%m-%d %H:%M:%S")

# ------------------ SYSTEM INFO ------------------

CPU_TEMP_RAW=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0)
CPU_TEMP=$(awk "BEGIN {printf \"%.1f\", $CPU_TEMP_RAW/1000}")

MEM_FREE=$(free -m | awk '/Mem:/ {print $4}')
MEM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')

UPTIME=$(uptime -p)

# ------------------ MODEM STATUS ------------------

MODEM_STATUS="❌ not found"
SIM_STATUS="❓ unknown"
CSQ_STATUS="❓ unknown"

if lsusb | grep -q 19d2; then
    MODEM_STATUS="✅ found"
fi

# ------------------ SIM STATE ------------------

if [[ -f "$SIM_STATE_FILE" ]]; then
    case "$(cat "$SIM_STATE_FILE")" in
        READY)         SIM_STATUS="✅ READY" ;;
        PIN_REQUIRED)  SIM_STATUS="🔒 PIN required" ;;
        ABSENT)        SIM_STATUS="❌ not inserted" ;;
        UNKNOWN)       SIM_STATUS="⚠ unknown" ;;
        *)             SIM_STATUS="⚠ invalid state" ;;
    esac
else
    SIM_STATUS="❓ no data"
fi

# ------------------ SIGNAL LEVEL ------------------

if [[ -c "$MODEM_DEV" ]]; then
    {
        echo -e "AT+CSQ\r"
        sleep 0.3
    } > "$MODEM_DEV"

    RESP=$(timeout 2 cat "$MODEM_DEV" || true)

    CSQ_VAL=$(echo "$RESP" | grep '+CSQ:' | sed -E 's/.*\+CSQ: ([0-9]+),.*/\1/' | head -n1)

    if [[ -n "$CSQ_VAL" ]]; then
        if [[ "$CSQ_VAL" == "99" ]]; then
            CSQ_STATUS="❌ no signal"
        else
            CSQ_STATUS="📶 CSQ=$CSQ_VAL"
        fi
    fi
fi

# ------------------ TELEGRAM ------------------

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
