#!/bin/bash
# ============================================================
#   ZV-Manager - Auto Kill Multi-Login
#   Dipanggil via cron setiap 1 menit
# ============================================================

source /etc/zv-manager/utils/helpers.sh 2>/dev/null

# Baca limit per user dari file conf
for conf_file in /etc/zv-manager/accounts/ssh/*.conf; do
    [[ -f "$conf_file" ]] || continue
    source "$conf_file"

    local_limit=${LIMIT:-2}
    current_logins=$(who | grep -c "^$USERNAME" 2>/dev/null || echo 0)

    if [[ "$current_logins" -gt "$local_limit" ]]; then
        # Kill session yang paling lama
        excess=$(( current_logins - local_limit ))
        who | grep "^$USERNAME" | head -n "$excess" | awk '{print $2}' | while read -r tty; do
            pkill -t "$tty" &>/dev/null
        done
    fi
done
