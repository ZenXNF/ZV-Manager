#!/bin/bash
# ============================================================
#   ZV-Manager - UDP Online Tracker
#   Track sesi berdasarkan src IP:port (bukan username)
#   karena event disconnect tidak punya tag [user:]
# ============================================================

ONLINE_FILE="/tmp/zv-udp-online"
> "$ONLINE_FILE"

# Mapping: "IP:port" -> "username"
declare -A SESSION_USER  # src -> username
declare -A USER_COUNT    # username -> jumlah sesi aktif

_write() {
    local tmp="${ONLINE_FILE}.tmp"
    > "$tmp"
    for user in "${!USER_COUNT[@]}"; do
        [[ "${USER_COUNT[$user]}" -gt 0 ]] && echo "${user}:${USER_COUNT[$user]}" >> "$tmp"
    done
    mv "$tmp" "$ONLINE_FILE" 2>/dev/null
}

journalctl -u zv-udp -f -n 0 --output=cat 2>/dev/null | while read -r line; do

    # Client connected — punya [src:] dan [user:]
    if echo "$line" | grep -q "Client connected"; then
        src=$(echo "$line" | grep -oP '\[src:\K[^\]]+')
        user=$(echo "$line" | grep -oP '\[user:\K[^\]]+')
        [[ -z "$src" || -z "$user" ]] && continue

        SESSION_USER["$src"]="$user"
        USER_COUNT["$user"]=$(( ${USER_COUNT["$user"]:-0} + 1 ))
        _write

    # Client disconnected — hanya punya [src:]
    elif echo "$line" | grep -q "Client disconnected"; then
        src=$(echo "$line" | grep -oP '\[src:\K[^\]]+')
        [[ -z "$src" ]] && continue

        user="${SESSION_USER[$src]}"
        [[ -z "$user" ]] && continue

        unset 'SESSION_USER[$src]'
        cnt=$(( ${USER_COUNT["$user"]:-1} - 1 ))
        if [[ "$cnt" -le 0 ]]; then
            unset 'USER_COUNT[$user]'
        else
            USER_COUNT["$user"]="$cnt"
        fi
        _write
    fi
done
