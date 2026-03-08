#!/bin/bash
# ============================================================
#   ZV-Manager - IP Limit Enforcement VMess
#   Teknik: korelasi timestamp nginx log + xray log
#   Cron: setiap menit
# ============================================================

VMESS_DIR="/etc/zv-manager/accounts/vmess"
XRAY_BIN="/usr/local/bin/xray"
API_ADDR="127.0.0.1:10085"
NGINX_LOG="/var/log/nginx/access.log"
XRAY_LOG="/var/log/xray-access.log"
LOG="/var/log/zv-manager/ip-limit.log"
KICK_STATE="/tmp/zv-ip-kick"
TG_STATE_DIR="/tmp/zv-tg-state"

mkdir -p "$KICK_STATE" "$TG_STATE_DIR" "$(dirname $LOG)"

_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

# Ambil TG_LIMIT_IP dari server conf berdasarkan SERVER di vmess conf
_get_ip_limit() {
    local username="$1"
    local server_name limit=0
    server_name=$(grep "^SERVER=" "${VMESS_DIR}/${username}.conf" 2>/dev/null | cut -d= -f2 | tr -d '"')
    if [[ -n "$server_name" && -f "/etc/zv-manager/servers/${server_name}.tg.conf" ]]; then
        limit=$(grep "^TG_LIMIT_IP=" "/etc/zv-manager/servers/${server_name}.tg.conf" | cut -d= -f2 | tr -d '"')
    else
        local sc
        sc=$(ls /etc/zv-manager/servers/*.tg.conf 2>/dev/null | head -1)
        [[ -f "$sc" ]] && limit=$(grep "^TG_LIMIT_IP=" "$sc" | cut -d= -f2 | tr -d '"')
    fi
    echo "${limit:-0}"
}

# Korelasi nginx + xray log → {user: [IP1, IP2, ...]}
# Window: 3 menit terakhir
_get_user_ips() {
    python3 - "$NGINX_LOG" "$XRAY_LOG" << 'PYEOF2'
import sys, re, json
from datetime import datetime, timedelta

nginx_log = sys.argv[1]
xray_log  = sys.argv[2]
now       = datetime.now()
window    = timedelta(minutes=5)

nginx_re = re.compile(
    r'^(\S+) \S+ \S+ \[(\d+/\w+/\d+:\d+:\d+:\d+) ([+-]\d{4})\] '
    r'"(?:GET|POST) /vmess[\s/].*?" (101)'
)
xray_re = re.compile(
    r'^(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2})\.\d+ from 127\.0\.0\.1:\d+ '
    r'accepted .+ email: (\S+@vmess)'
)

nginx_map = {}
try:
    with open(nginx_log) as f:
        for line in f:
            m = nginx_re.match(line)
            if not m: continue
            ip, ts_str, tz_str, _ = m.groups()
            dt = datetime.strptime(f"{ts_str} {tz_str}", "%d/%b/%Y:%H:%M:%S %z").astimezone().replace(tzinfo=None)
            if now - dt > window: continue
            key = dt.strftime("%Y/%m/%d %H:%M:%S")
            nginx_map.setdefault(key, []).append(ip)
except Exception:
    pass

user_ips = {}
try:
    with open(xray_log) as f:
        for line in f:
            m = xray_re.match(line)
            if not m: continue
            ts_key, email = m.groups()
            base_dt = datetime.strptime(ts_key, "%Y/%m/%d %H:%M:%S")
            if now - base_dt > window: continue
            username = email.replace("@vmess", "")
            for delta in range(-2, 3):
                check = (base_dt + timedelta(seconds=delta)).strftime("%Y/%m/%d %H:%M:%S")
                user_ips.setdefault(username, set()).update(nginx_map.get(check, []))
except Exception:
    pass

print(json.dumps({k: list(v) for k, v in user_ips.items()}))
PYEOF2
}


# Kick user via Xray API
_kick_user() {
    local username="$1" uuid="$2"
    local email="${username}@vmess"
    "$XRAY_BIN" api rmu -s "$API_ADDR" -inbound "vmess-ws"   -email "$email" &>/dev/null || true
    "$XRAY_BIN" api rmu -s "$API_ADDR" -inbound "vmess-grpc" -email "$email" &>/dev/null || true
    _log "$username KICKED (IP limit exceeded)"
}

_readd_user() {
    local username="$1" uuid="$2"
    local email="${username}@vmess"
    local user_json="{\"vmess\":{\"id\":\"${uuid}\",\"email\":\"${email}\",\"alterId\":0}}"
    "$XRAY_BIN" api adu -s "$API_ADDR" -inbound "vmess-ws"   -user "$user_json" &>/dev/null || true
    "$XRAY_BIN" api adu -s "$API_ADDR" -inbound "vmess-grpc" -user "$user_json" &>/dev/null || true
    _log "$username RE-ADDED after kick cooldown"
}

_tg_notify_ip() {
    local tg_uid="$1" username="$2" ip_count="$3" ip_limit="$4"
    [[ -z "$tg_uid" || "$tg_uid" == "0" ]] && return
    local flag_file="${TG_STATE_DIR}/iplimit_${username}"
    if [[ -f "$flag_file" ]]; then
        local last; last=$(cat "$flag_file")
        (( $(date +%s) - last < 300 )) && return
    fi
    local bot_token server_name
    bot_token=$(grep "^TG_TOKEN=" /etc/zv-manager/telegram.conf 2>/dev/null | cut -d= -f2 | tr -d '"')
    server_name=$(grep "^TG_SERVER_LABEL=" /etc/zv-manager/servers/*.tg.conf 2>/dev/null | head -1 | cut -d= -f2 | tr -d '"')
    [[ -z "$bot_token" ]] && return
    local msg="⚠️ <b>Limit IP VMess Terlampaui!</b>%0A"
    msg+="━━━━━━━━━━━━━━━━━━━%0A"
    msg+="👤 Username : <code>${username}</code>%0A"
    msg+="🌐 Server   : ${server_name}%0A"
    msg+="📱 IP Aktif : ${ip_count} / ${ip_limit}%0A"
    msg+="━━━━━━━━━━━━━━━━━━━%0A"
    msg+="🔄 Koneksi direset. Harap gunakan max ${ip_limit} perangkat."
    curl -s -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
        -d "chat_id=${tg_uid}&text=${msg}&parse_mode=HTML" &>/dev/null
    date +%s > "$flag_file"
}

_main() {
    [[ ! -d "$VMESS_DIR" ]] && exit 0
    [[ ! -f "$NGINX_LOG" || ! -f "$XRAY_LOG" ]] && exit 0

    # Dapatkan mapping user → IPs dari log korelasi
    local user_ips_json
    user_ips_json=$(_get_user_ips)

    for conf in "${VMESS_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue

        local username uuid tg_uid
        username=$(grep "^USERNAME=" "$conf" | cut -d= -f2 | tr -d '"')
        uuid=$(grep "^UUID=" "$conf" | cut -d= -f2 | tr -d '"')
        tg_uid=$(grep "^TG_USER_ID=" "$conf" | cut -d= -f2 | tr -d '"')
        [[ -z "$username" || -z "$uuid" ]] && continue

        # Cek cooldown kick
        local kick_flag="${KICK_STATE}/${username}.kick"
        if [[ -f "$kick_flag" ]]; then
            local kick_ts; kick_ts=$(cat "$kick_flag")
            if (( $(date +%s) - kick_ts >= 30 )); then
                _readd_user "$username" "$uuid"
                rm -f "$kick_flag"
            fi
            continue
        fi

        local ip_limit
        ip_limit=$(_get_ip_limit "$username")
        [[ "${ip_limit:-0}" == "0" ]] && continue

        # Hitung unique IP dari korelasi log
        local ip_count
        ip_count=$(python3 -c "
import json, sys
data = json.loads('''${user_ips_json}''')
ips = data.get('${username}', [])
print(len(set(ips)))
" 2>/dev/null || echo "0")

        _log "$username: ${ip_count} IP unik (limit: ${ip_limit})"

        if (( ip_count > ip_limit )); then
            _log "$username melebihi limit → kick"
            _tg_notify_ip "$tg_uid" "$username" "$ip_count" "$ip_limit"
            _kick_user "$username" "$uuid"
            date +%s > "$kick_flag"
        fi
    done
}

_main
