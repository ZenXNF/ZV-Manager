#!/bin/bash
# ============================================================
#   ZV-Manager - Auto Kill Multi-Login
#   Dipanggil via cron setiap 1 menit
#   Pakai ss + /proc karena user /bin/false tidak muncul di who
# ============================================================
ACCOUNT_DIR="/etc/zv-manager/accounts/ssh"

SS_OUT=$(ss -tnp 2>/dev/null | grep ':22\|:500\|:40000\|:109\|:143')
[[ -z "$SS_OUT" ]] && exit 0

for conf_file in "$ACCOUNT_DIR"/*.conf; do
    [[ -f "$conf_file" ]] || continue

    uname=$(grep "^USERNAME=" "$conf_file" | cut -d= -f2 | tr -d '[:space:]')
    limit=$(grep "^LIMIT="    "$conf_file" | cut -d= -f2 | tr -d '[:space:]')

    [[ -z "$uname" ]] && continue
    limit=${limit:-2}

    uid=$(id -u "$uname" 2>/dev/null)
    [[ -z "$uid" ]] && continue

    ip_list=$(
        ss -tnp 2>/dev/null | grep 'ESTAB' | while read -r line; do
            pid=$(echo "$line" | grep -oP 'pid=\K[0-9]+')
            [[ -z "$pid" ]] && continue
            proc_uid=$(stat -c %u /proc/$pid 2>/dev/null)
            [[ "$proc_uid" != "$uid" ]] && continue
            echo "$line" | awk '{print $5}' | cut -d: -f1
        done | sort -u
    )

    current_logins=$(echo "$ip_list" | grep -c '[0-9]' 2>/dev/null)
    current_logins=$(echo "$current_logins" | head -1 | tr -d '[:space:]')
    current_logins=${current_logins:-0}

    if (( current_logins > limit )); then
        pkill -u "$uname" -9 &>/dev/null
        logger -t zv-autokill "KICKED: $uname (${current_logins}IP > limit ${limit})"
    fi
done
