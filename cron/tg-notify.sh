#!/bin/bash
# ============================================================
#   ZV-Manager - Notifikasi Telegram: akun akan expired
#   Dipanggil tiap jam via cron
#   Kirim notif 20 jam sebelum expired
# ============================================================

source /etc/zv-manager/core/telegram.sh
tg_load || exit 0

ACCOUNT_DIR="/etc/zv-manager/accounts/ssh"
NOTIFY_DIR="/etc/zv-manager/accounts/notified"
LOG="/var/log/zv-manager/install.log"

mkdir -p "$NOTIFY_DIR"

now_ts=$(date +%s)
warn_until=$(( now_ts + 20 * 3600 ))

# Kirim dengan inline button — pure curl, no python3
_tg_send_notify() {
    local chat_id="$1" uname="$2" srv="$3" exp="$4" sisa="$5"
    [[ -z "$TG_TOKEN" || -z "$chat_id" ]] && return
    python3 - << PYEOF
import json, urllib.request, urllib.parse
token  = "${TG_TOKEN}"
text   = (
    "⚠️ <b>Akun Akan Expired!</b>
"
    "━━━━━━━━━━━━━━━━━━━
"
    "👤 Username : <code>${uname}</code>
"
    "🌐 Server   : ${srv}
"
    "⏳ Expired  : ${exp}
"
    "⏱️ Sisa     : ±${sisa} jam
"
    "━━━━━━━━━━━━━━━━━━━
"
    "Segera perpanjang agar tidak terputus!"
)
markup = {"inline_keyboard": [[
    {"text": "🔄 Perpanjang Sekarang", "callback_data": "renew_${uname}"},
    {"text": "🏠 Menu Utama",          "callback_data": "home"}
]]}
payload = json.dumps({
    "chat_id":      "${chat_id}",
    "parse_mode":   "HTML",
    "text":         text,
    "reply_markup": markup
}).encode()
req = urllib.request.Request(
    f"https://api.telegram.org/bot{token}/sendMessage",
    data=payload,
    headers={"Content-Type": "application/json"}
)
try:
    urllib.request.urlopen(req, timeout=10)
except Exception:
    pass
PYEOF
}

for conf in "$ACCOUNT_DIR"/*.conf; do
    [[ -f "$conf" ]] || continue

    # Baca dengan source sekali — lebih cepat dari grep berulang
    unset USERNAME IS_TRIAL EXPIRED_TS TG_USER_ID SERVER
    source "$conf"

    [[ "$IS_TRIAL" == "1" ]] && continue
    [[ -z "$EXPIRED_TS" || -z "$TG_USER_ID" ]] && continue
    [[ "$now_ts" -ge "$EXPIRED_TS" ]] && continue

    if [[ "$EXPIRED_TS" -le "$warn_until" ]]; then
        local_notify_file="${NOTIFY_DIR}/${USERNAME}.notified"
        [[ -f "$local_notify_file" ]] && continue

        exp_display=$(TZ="Asia/Jakarta" date -d "@${EXPIRED_TS}" +"%d %b %Y %H:%M WIB")
        sisa=$(( (EXPIRED_TS - now_ts) / 3600 ))

        _tg_send_notify "$TG_USER_ID" "$USERNAME" "$SERVER" "$exp_display" "$sisa"
        touch "$local_notify_file"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] NOTIFY: $USERNAME → tg:$TG_USER_ID exp:$exp_display" >> "$LOG"
    fi
done
