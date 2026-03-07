#!/bin/bash
# ============================================================
#   ZV-Manager - Auto Kill Multi-Login
#   Dipanggil via cron setiap 1 menit
#   Jika IP aktif melebihi limit → hapus akun + notif Telegram
#   Deteksi via /tmp/zv-bw/username.ips (PAM session tracker)
# ============================================================
ACCOUNT_DIR="/etc/zv-manager/accounts/ssh"
TG_CONF="/etc/zv-manager/telegram.conf"
LOG="/var/log/zv-manager/install.log"

source /etc/zv-manager/core/bandwidth.sh 2>/dev/null

TOKEN=$(grep "^TG_TOKEN=" "$TG_CONF" 2>/dev/null | cut -d= -f2 | tr -d '"'"'"' ')

_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG" 2>/dev/null; }

_tg_send() {
    local chat="$1" text="$2"
    [[ -z "$TOKEN" || -z "$chat" ]] && return
    python3 - << PYEOF
import json, urllib.request
token = "${TOKEN}"
payload = json.dumps({
    "chat_id":    "${chat}",
    "parse_mode": "HTML",
    "text":       """${text}"""
}).encode()
req = urllib.request.Request(
    f"https://api.telegram.org/bot{token}/sendMessage",
    data=payload, headers={"Content-Type": "application/json"}
)
try: urllib.request.urlopen(req, timeout=10)
except: pass
PYEOF
}

_hapus_akun() {
    local username="$1" tg_uid="$2" server="$3"

    # Cleanup bandwidth iptables
    _bw_cleanup_user "$username" 2>/dev/null

    # Hapus session file
    rm -f "/tmp/zv-bw/${username}.ips" 2>/dev/null
    rm -f "/tmp/zv-bw/${username}.warned" 2>/dev/null

    # Hapus notified flag
    rm -f "/etc/zv-manager/accounts/notified/${username}.notified" 2>/dev/null

    # Kill proses & hapus user Linux
    pkill -u "$username" -9 &>/dev/null
    userdel -r "$username" &>/dev/null 2>&1

    # Hapus conf
    rm -f "${ACCOUNT_DIR}/${username}.conf"

    _log "AUTOKILL: Akun ${username} dihapus karena melebihi limit IP (server: ${server})"

    # Notif Telegram user
    [[ -n "$tg_uid" ]] && _tg_send "$tg_uid" "🚫 <b>Akun Dihapus!</b>
━━━━━━━━━━━━━━━━━━━
👤 Username : <code>${username}</code>
🖥 Server   : ${server}
━━━━━━━━━━━━━━━━━━━
⚠️ Akun kamu dihapus karena terdeteksi <b>Multi Login</b> melebihi batas.
Buat akun baru melalui bot."
}

for conf_file in "$ACCOUNT_DIR"/*.conf; do
    [[ -f "$conf_file" ]] || continue

    uname=$(grep "^USERNAME=" "$conf_file" | cut -d= -f2 | tr -d '[:space:]')
    limit=$(grep "^LIMIT="    "$conf_file" | cut -d= -f2 | tr -d '[:space:]')
    tg_uid=$(grep "^TG_USER_ID=" "$conf_file" | cut -d= -f2 | tr -d '[:space:]')
    server=$(grep "^SERVER=" "$conf_file" | cut -d= -f2 | tr -d '[:space:]')

    [[ -z "$uname" ]] && continue
    limit=${limit:-2}

    # Hitung IP aktif dari session file (diisi oleh PAM bw-session.sh)
    session_file="/tmp/zv-bw/${uname}.ips"
    if [[ ! -f "$session_file" ]]; then
        current_ips=0
    else
        current_ips=$(grep -c '[0-9]' "$session_file" 2>/dev/null || echo 0)
        current_ips=$(echo "$current_ips" | head -1 | tr -d '[:space:]')
        current_ips=${current_ips:-0}
    fi

    if (( current_ips > limit )); then
        _hapus_akun "$uname" "$tg_uid" "$server"
    fi
done
