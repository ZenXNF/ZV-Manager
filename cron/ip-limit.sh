#!/bin/bash
# ============================================================
#   ZV-Manager - IP Limit Enforcement VMess
#   Cron: setiap menit
#   Cara kerja:
#     1. Query statsonlineiplist per user
#     2. Hitung unique IP aktif
#     3. Jika > TG_LIMIT_IP → kick user (rmu) dari semua inbound
#        tunggu 30 detik → tambah balik (adu)
#     4. Notif Telegram ke user
# ============================================================

VMESS_DIR="/etc/zv-manager/accounts/vmess"
XRAY_BIN="/usr/local/bin/xray"
API_ADDR="127.0.0.1:10085"
LOG="/var/log/zv-manager/ip-limit.log"
KICK_STATE="/tmp/zv-ip-kick"
TG_STATE_DIR="/tmp/zv-tg-state"

mkdir -p "$KICK_STATE" "$TG_STATE_DIR"

_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

# Ambil TG_LIMIT_IP dari server conf lokal
_get_ip_limit() {
    local limit=0
    local local_ip
    local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null)
    for sc in /etc/zv-manager/servers/*.tg.conf; do
        [[ -f "$sc" ]] || continue
        local sc_ip
        sc_ip=$(grep "^IP=" "$sc" | cut -d= -f2 | tr -d '"')
        if [[ "$sc_ip" == "$local_ip" || -z "$local_ip" ]]; then
            limit=$(grep "^TG_LIMIT_IP=" "$sc" | cut -d= -f2 | tr -d '"')
            break
        fi
    done
    echo "${limit:-0}"
}

# Hitung IP aktif user via Xray API
_count_online_ips() {
    local username="$1"
    local tmpout
    tmpout=$(mktemp)
    "$XRAY_BIN" api statsonlineiplist \
        -s "$API_ADDR" \
        -email "${username}@vmess" \
        2>/dev/null > "$tmpout" || true

    local count
    count=$(python3 - "$tmpout" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    records = data.get("ip_records", [])
    print(len(records))
except Exception:
    print(0)
PYEOF
)
    rm -f "$tmpout"
    echo "${count:-0}"
}

# Kick user dari semua inbound VMess
_kick_user() {
    local username="$1"
    local email="${username}@vmess"
    "$XRAY_BIN" api rmu -s "$API_ADDR" -inbound "vmess-ws"   -email "$email" &>/dev/null || true
    "$XRAY_BIN" api rmu -s "$API_ADDR" -inbound "vmess-grpc" -email "$email" &>/dev/null || true
    _log "$username KICKED (IP limit)"
}

# Tambah balik user ke semua inbound VMess
_readd_user() {
    local username="$1" uuid="$2"
    local email="${username}@vmess"
    local user_json="{\"vmess\":{\"id\":\"${uuid}\",\"email\":\"${email}\",\"alterId\":0}}"
    "$XRAY_BIN" api adu -s "$API_ADDR" -inbound "vmess-ws"   -user "$user_json" &>/dev/null || true
    "$XRAY_BIN" api adu -s "$API_ADDR" -inbound "vmess-grpc" -user "$user_json" &>/dev/null || true
    _log "$username RE-ADDED after kick"
}

# Kirim notif Telegram
_tg_notify_ip() {
    local tg_uid="$1" username="$2" ip_count="$3" ip_limit="$4"
    [[ -z "$tg_uid" || "$tg_uid" == "0" ]] && return

    # Rate limit notif — max 1x per 5 menit per user
    local flag_file="${TG_STATE_DIR}/iplimit_${username}"
    if [[ -f "$flag_file" ]]; then
        local last_notif
        last_notif=$(cat "$flag_file")
        local now_ts
        now_ts=$(date +%s)
        (( now_ts - last_notif < 300 )) && return
    fi

    local bot_token server_name
    bot_token=$(grep "^BOT_TOKEN=" /etc/zv-manager/servers/*.tg.conf 2>/dev/null | head -1 | cut -d= -f2 | tr -d '"')
    server_name=$(grep "^TG_SERVER_LABEL=" /etc/zv-manager/servers/*.tg.conf 2>/dev/null | head -1 | cut -d= -f2 | tr -d '"')
    [[ -z "$bot_token" ]] && return

    local msg
    msg="⚠️ <b>Limit IP VMess Terlampaui!</b>%0A"
    msg+="━━━━━━━━━━━━━━━━━━━%0A"
    msg+="👤 Username : <code>${username}</code>%0A"
    msg+="🌐 Server   : ${server_name}%0A"
    msg+="📱 IP Aktif : ${ip_count} / ${ip_limit}%0A"
    msg+="━━━━━━━━━━━━━━━━━━━%0A"
    msg+="🔄 Koneksi direset. Harap hanya gunakan ${ip_limit} perangkat."

    curl -s -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
        -d "chat_id=${tg_uid}&text=${msg}&parse_mode=HTML" &>/dev/null

    date +%s > "$flag_file"
}

_main() {
    [[ ! -d "$VMESS_DIR" ]] && exit 0

    local ip_limit
    ip_limit=$(_get_ip_limit)
    [[ "$ip_limit" == "0" ]] && exit 0  # unlimited, skip

    for conf in "${VMESS_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue

        local username uuid tg_uid is_trial
        username=$(grep "^USERNAME=" "$conf" | cut -d= -f2 | tr -d '"')
        uuid=$(grep "^UUID=" "$conf" | cut -d= -f2 | tr -d '"')
        tg_uid=$(grep "^TG_USER_ID=" "$conf" | cut -d= -f2 | tr -d '"')
        is_trial=$(grep "^IS_TRIAL=" "$conf" | cut -d= -f2 | tr -d '"')

        [[ -z "$username" || -z "$uuid" ]] && continue

        # Cek apakah sedang dalam cooldown kick (30 detik)
        local kick_flag="${KICK_STATE}/${username}.kick"
        if [[ -f "$kick_flag" ]]; then
            local kick_ts
            kick_ts=$(cat "$kick_flag")
            local now_ts
            now_ts=$(date +%s)
            if (( now_ts - kick_ts >= 30 )); then
                # Cooldown selesai → tambah balik
                _readd_user "$username" "$uuid"
                rm -f "$kick_flag"
            fi
            continue
        fi

        # Hitung IP aktif
        local ip_count
        ip_count=$(_count_online_ips "$username")

        [[ "$ip_count" -le "$ip_limit" ]] && continue

        # Melebihi limit → kick
        _log "$username: ${ip_count} IP aktif (limit: ${ip_limit}) → kick"
        _tg_notify_ip "$tg_uid" "$username" "$ip_count" "$ip_limit"
        _kick_user "$username"
        date +%s > "$kick_flag"
    done
}

_main
