#!/bin/bash
# ============================================================
#   ZV-Manager - Auto Delete Expired Users
#   Dipanggil via cron setiap hari jam 00:02
# ============================================================

today=$(date +"%Y-%m-%d")

for conf_file in /etc/zv-manager/accounts/ssh/*.conf; do
    [[ -f "$conf_file" ]] || continue
    source "$conf_file"

    if [[ "$EXPIRED" < "$today" ]]; then
        # Kill session aktif
        pkill -u "$USERNAME" &>/dev/null
        # Hapus user Linux
        userdel -r "$USERNAME" &>/dev/null 2>&1
        # Hapus file conf
        rm -f "$conf_file"
        echo "[$(date)] Auto-deleted expired user: $USERNAME" >> /var/log/zv-manager/install.log
    fi
done
