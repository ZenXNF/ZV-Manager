#!/bin/bash
# ============================================================
#   ZV-Manager - Trial Account Cleanup
#   Dipanggil tiap menit via cron
#   Hapus akun trial expired + kirim notif Telegram
# ============================================================

source /etc/zv-manager/core/telegram.sh
tg_load 2>/dev/null || true

ACCOUNT_DIR="/etc/zv-manager/accounts/ssh"
LOG="/var/log/zv-manager/install.log"
now_ts=$(date +%s)

_notify_trial_expired() {
    local tg_uid="$1" username="$2"
    [[ -z "$tg_uid" || -z "$TG_TOKEN" ]] && return
    local jfile; jfile=$(mktemp)
    python3 - "$tg_uid" "$username" > "$jfile" << 'PYINLINE'
import json, sys
uid, user = sys.argv[1], sys.argv[2]
text = (
    "⏰ <b>Trial Habis</b>\n\n"
    f"Akun trial <code>{user}</code> kamu sudah berakhir.\n\n"
    "Mau lanjut? Buat akun premium lewat bot."
)
print(json.dumps({"chat_id": uid, "text": text, "parse_mode": "HTML"}))
PYINLINE
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage"         -H "Content-Type: application/json"         -d "@${jfile}" --max-time 10 &>/dev/null
    rm -f "$jfile"
}

for conf_file in "$ACCOUNT_DIR"/*.conf; do
    [[ -f "$conf_file" ]] || continue

    unset IS_TRIAL EXPIRED_TS USERNAME TG_USER_ID
    source "$conf_file"

    [[ "$IS_TRIAL" != "1" ]] && continue
    [[ -z "$EXPIRED_TS" ]] && continue

    if [[ "$now_ts" -ge "$EXPIRED_TS" ]]; then
        _notify_trial_expired "$TG_USER_ID" "$USERNAME"
        pkill -u "$USERNAME" &>/dev/null
        userdel -r "$USERNAME" &>/dev/null 2>&1
        rm -f "$conf_file"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] TRIAL expired & deleted: $USERNAME" >> "$LOG"
    fi
done
