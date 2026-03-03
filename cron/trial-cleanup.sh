#!/bin/bash
# ============================================================
#   ZV-Manager - Trial Account Cleanup
#   Dipanggil tiap menit via cron
#   Hapus akun trial yang sudah expired berdasarkan timestamp
# ============================================================

ACCOUNT_DIR="/etc/zv-manager/accounts/ssh"
LOG="/var/log/zv-manager/install.log"
now_ts=$(date +%s)

for conf_file in "$ACCOUNT_DIR"/*.conf; do
    [[ -f "$conf_file" ]] || continue

    unset IS_TRIAL EXPIRED_TS USERNAME
    source "$conf_file"

    # Skip kalau bukan akun trial
    [[ "$IS_TRIAL" != "1" ]] && continue

    # Skip kalau tidak ada timestamp
    [[ -z "$EXPIRED_TS" ]] && continue

    # Hapus kalau sudah lewat waktu expired
    if [[ "$now_ts" -ge "$EXPIRED_TS" ]]; then
        pkill -u "$USERNAME" &>/dev/null
        userdel -r "$USERNAME" &>/dev/null 2>&1
        rm -f "$conf_file"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] TRIAL expired & deleted: $USERNAME" >> "$LOG"
    fi
done
