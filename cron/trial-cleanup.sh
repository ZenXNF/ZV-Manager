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

_tg_send() {
    local chat_id="$1" text="$2"
    [[ -z "$TG_TOKEN" || -z "$chat_id" ]] && return
    printf '%b' "$text" | curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -F "chat_id=${chat_id}" \
        -F "parse_mode=HTML" \
        -F "text=<-" --max-time 10 &>/dev/null
}

_notify_trial_expired() {
    local tg_uid="$1" username="$2"
    _tg_send "$tg_uid" "⏰ <b>Trial Habis</b>\n\nAkun trial <code>${username}</code> kamu sudah berakhir.\n\nMau lanjut? Buat akun premium lewat bot."
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
