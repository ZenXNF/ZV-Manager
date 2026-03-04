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
notify_window=$(( 20 * 3600 ))   # 20 jam dalam detik
warn_until=$(( now_ts + notify_window ))

for conf in "$ACCOUNT_DIR"/*.conf; do
    [[ -f "$conf" ]] || continue

    local_username=$(grep "^USERNAME=" "$conf" | cut -d= -f2)
    is_trial=$(grep "^IS_TRIAL=" "$conf" | cut -d= -f2)
    exp_ts=$(grep "^EXPIRED_TS=" "$conf" | cut -d= -f2)
    tg_uid=$(grep "^TG_USER_ID=" "$conf" | cut -d= -f2)
    domain=$(grep "^DOMAIN=" "$conf" | cut -d= -f2)
    server=$(grep "^SERVER=" "$conf" | cut -d= -f2)

    # Skip trial & yang tidak punya timestamp/tg_uid
    [[ "$is_trial" == "1" ]] && continue
    [[ -z "$exp_ts" || -z "$tg_uid" ]] && continue

    # Sudah expired — skip
    [[ "$now_ts" -ge "$exp_ts" ]] && continue

    # Dalam window 20 jam ke depan
    if [[ "$exp_ts" -le "$warn_until" ]]; then
        local_notify_file="${NOTIFY_DIR}/${local_username}.notified"
        # Jangan kirim 2x
        [[ -f "$local_notify_file" ]] && continue

        local exp_display
        exp_display=$(TZ="Asia/Jakarta" date -d "@${exp_ts}" +"%d %b %Y %H:%M WIB")
        local sisa=$(( (exp_ts - now_ts) / 3600 ))

        tg_send "$tg_uid" "⚠️ <b>Akun Akan Expired!</b>

Username : <code>${local_username}</code>
Server   : ${server}
Expired  : ${exp_display}
Sisa     : ±${sisa} jam

Segera perpanjang agar tidak terputus!" 2>/dev/null

        touch "$local_notify_file"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] NOTIFY: $local_username → tg:$tg_uid exp:$exp_display" >> "$LOG"
    fi
done
