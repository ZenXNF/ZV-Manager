#!/bin/bash
# ============================================================
#   ZV-Manager - UDP Online Tracker
#   Cek event terakhir per user dari journalctl
#   Update /tmp/zv-udp-online setiap 3 detik
# ============================================================

ONLINE_FILE="/tmp/zv-udp-online"

> "$ONLINE_FILE"

while true; do
    tmp="${ONLINE_FILE}.tmp"
    > "$tmp"

    # Ambil log 10 menit terakhir, cari semua user
    mapfile -t users < <(
        journalctl -u zv-udp --since "10 minutes ago" --output=cat --no-pager 2>/dev/null \
        | grep -oP '\[user:\K[^\]]+' | sort -u
    )

    for user in "${users[@]}"; do
        [[ -z "$user" ]] && continue

        # Cari event terakhir user ini
        last_event=$(
            journalctl -u zv-udp --since "10 minutes ago" --output=cat --no-pager 2>/dev/null \
            | grep "\[user:${user}\]" | tail -1
        )

        # Kalau event terakhir adalah "connected" → online
        if echo "$last_event" | grep -q "Client connected"; then
            echo "${user}:1" >> "$tmp"
        fi
    done

    mv "$tmp" "$ONLINE_FILE" 2>/dev/null
    sleep 3
done
