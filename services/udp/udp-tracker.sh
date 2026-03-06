#!/bin/bash
# ============================================================
#   ZV-Manager - UDP Online Tracker
#   Follow journalctl zv-udp → tulis ke /tmp/zv-udp-online
# ============================================================

ONLINE_FILE="/tmp/zv-udp-online"
declare -A COUNTER

> "$ONLINE_FILE"

_write() {
    local tmp="${ONLINE_FILE}.tmp"
    > "$tmp"
    for user in "${!COUNTER[@]}"; do
        [[ "${COUNTER[$user]}" -gt 0 ]] && echo "${user}:${COUNTER[$user]}" >> "$tmp"
    done
    mv "$tmp" "$ONLINE_FILE" 2>/dev/null
}

journalctl -u zv-udp -f -n 0 --output=cat 2>/dev/null | while read -r line; do
    if echo "$line" | grep -q "Client connected"; then
        user=$(echo "$line" | grep -oP '\[user:\K[^\]]+')
        [[ -z "$user" ]] && continue
        COUNTER["$user"]=$(( ${COUNTER["$user"]:-0} + 1 ))
        _write
    elif echo "$line" | grep -q "Client disconnected"; then
        user=$(echo "$line" | grep -oP '\[user:\K[^\]]+')
        [[ -z "$user" ]] && continue
        cnt=$(( ${COUNTER["$user"]:-1} - 1 ))
        if [[ "$cnt" -le 0 ]]; then
            unset 'COUNTER[$user]'
        else
            COUNTER["$user"]="$cnt"
        fi
        _write
    fi
done
