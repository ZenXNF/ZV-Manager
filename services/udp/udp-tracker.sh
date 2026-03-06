#!/bin/bash
# ============================================================
#   ZV-Manager - UDP Online Tracker
#   Cek apakah user punya event "connected" dalam 120 detik
#   terakhir (sesuai TIMEOUT udp-custom = 120s)
# ============================================================

ONLINE_FILE="/tmp/zv-udp-online"
TIMEOUT_SEC=120  # Sama dengan timeout udp-custom

> "$ONLINE_FILE"

while true; do
    tmp="${ONLINE_FILE}.tmp"
    > "$tmp"

    now=$(date +%s)
    since=$(date -d "@$(( now - TIMEOUT_SEC ))" "+%Y-%m-%d %H:%M:%S" 2>/dev/null \
           || date -r $(( now - TIMEOUT_SEC )) "+%Y-%m-%d %H:%M:%S" 2>/dev/null)

    # Ambil semua event connected dalam 120 detik terakhir
    mapfile -t lines < <(
        journalctl -u zv-udp --since "$since" --output=cat --no-pager 2>/dev/null \
        | grep "Client connected"
    )

    declare -A seen
    for line in "${lines[@]}"; do
        user=$(echo "$line" | grep -oP '\[user:\K[^\]]+')
        [[ -z "$user" ]] && continue
        seen["$user"]=1
    done

    for user in "${!seen[@]}"; do
        echo "${user}:1" >> "$tmp"
    done
    unset seen

    mv "$tmp" "$ONLINE_FILE" 2>/dev/null
    sleep 5
done
