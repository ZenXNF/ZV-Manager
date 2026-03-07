#!/bin/bash
# ============================================================
#   ZV-Manager - Auto Kill Multi-Login
#   Cek jumlah session aktif via counter file
#   Jika melebihi limit → hapus akun + notif Telegram
# ============================================================
ACCOUNT_DIR="/etc/zv-manager/accounts/ssh"
SESSION_DIR="/tmp/zv-bw"
TG_CONF="/etc/zv-manager/telegram.conf"
LOG="/var/log/zv-manager/install.log"

source /etc/zv-manager/core/bandwidth.sh 2>/dev/null

TOKEN=$(grep "^TG_TOKEN=" "$TG_CONF" 2>/dev/null | cut -d= -f2 | tr -d '"'"'"' ')

_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG" 2>/dev/null; }

_tg_send() {
    local chat="$1" msg="$2"
    [[ -z "$TOKEN" || -z "$chat" ]] && return
    python3 -c "
import json,urllib.request
p=json.dumps({'chat_id':'${chat}','parse_mode':'HTML','text':'''$msg'''}).encode()
r=urllib.request.Request('https://api.telegram.org/bot${TOKEN}/sendMessage',data=p,headers={'Content-Type':'application/json'})
try: urllib.request.urlopen(r,timeout=10)
except: pass
"
}

_hapus_akun() {
    local username="$1" tg_uid="$2" server="$3"
    _bw_cleanup_user "$username" 2>/dev/null
    rm -f "${SESSION_DIR}/${username}.ips" "${SESSION_DIR}/${username}.count" 2>/dev/null
    rm -f "/etc/zv-manager/accounts/notified/${username}.notified" 2>/dev/null
    pkill -u "$username" -9 &>/dev/null
    userdel -r "$username" &>/dev/null 2>&1
    rm -f "${ACCOUNT_DIR}/${username}.conf"
    _log "AUTOKILL: $username dihapus (multi-login)"
    [[ -n "$tg_uid" ]] && _tg_send "$tg_uid" "🚫 Akun Dihapus! Username: $username | Server: $server | Alasan: Multi Login melebihi batas. Buat akun baru via bot."
}

for conf_file in "$ACCOUNT_DIR"/*.conf; do
    [[ -f "$conf_file" ]] || continue
    uname=$(grep "^USERNAME="    "$conf_file" | cut -d= -f2 | tr -d '[:space:]')
    limit=$(grep "^LIMIT="       "$conf_file" | cut -d= -f2 | tr -d '[:space:]')
    tg_uid=$(grep "^TG_USER_ID=" "$conf_file" | cut -d= -f2 | tr -d '[:space:]')
    server=$(grep "^SERVER="     "$conf_file" | cut -d= -f2 | tr -d '[:space:]')
    [[ -z "$uname" ]] && continue
    limit=${limit:-2}
    current=$(cat "${SESSION_DIR}/${uname}.count" 2>/dev/null || echo 0)
    current=${current:-0}
    if (( current > limit )); then
        _hapus_akun "$uname" "$tg_uid" "$server"
    fi
done
