#!/bin/bash
# ============================================================
#   ZV-Manager - Auto Kill Multi-Login
#   Dipanggil via cron setiap 1 menit
# ============================================================

ACCOUNT_DIR="/etc/zv-manager/accounts/ssh"

# Ambil snapshot who sekali — hemat fork
WHO_OUT=$(who 2>/dev/null)
[[ -z "$WHO_OUT" ]] && exit 0

for conf_file in "$ACCOUNT_DIR"/*.conf; do
    [[ -f "$conf_file" ]] || continue
    # Grep langsung, hindari source seluruh conf
    uname=$(grep "^USERNAME=" "$conf_file" | cut -d= -f2 | tr -d '[:space:]')
    limit=$(grep "^LIMIT="    "$conf_file" | cut -d= -f2 | tr -d '[:space:]')
    [[ -z "$uname" ]] && continue
    limit=${limit:-2}

    current_logins=$(echo "$WHO_OUT" | grep -c "^${uname} " 2>/dev/null || echo 0)
    if (( current_logins > limit )); then
        excess=$(( current_logins - limit ))
        echo "$WHO_OUT" | grep "^${uname} " | head -n "$excess" | awk '{print $2}' | \
            while read -r tty; do pkill -t "$tty" &>/dev/null; done
    fi
done
