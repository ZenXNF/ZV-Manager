#!/bin/bash
SESSION_DIR="/tmp/zv-bw"
mkdir -p "$SESSION_DIR"

CONF="/etc/zv-manager/accounts/ssh/${PAM_USER}.conf"
[[ ! -f "$CONF" ]] && exit 0

source /etc/zv-manager/core/bandwidth.sh

if [[ "$PAM_TYPE" == "open_session" ]]; then
    CLIENT_IP="${PAM_RHOST:-unknown}"
    echo "$CLIENT_IP" >> "${SESSION_DIR}/${PAM_USER}.ips"
    COUNT_FILE="${SESSION_DIR}/${PAM_USER}.count"
    count=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
    echo $(( count + 1 )) > "$COUNT_FILE"
    quota=$(grep "^BW_QUOTA_BYTES=" "$CONF" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')
    if [[ "${quota:-0}" != "0" && "$CLIENT_IP" != "unknown" && "$CLIENT_IP" != "127.0.0.1" ]]; then
        _bw_add_ip_rule "$PAM_USER" "$CLIENT_IP"
    fi
    _bw_log "SESSION_OPEN: $PAM_USER from $CLIENT_IP (total: $(( count + 1 )))"

elif [[ "$PAM_TYPE" == "close_session" ]]; then
    CLIENT_IP="${PAM_RHOST:-unknown}"
    quota=$(grep "^BW_QUOTA_BYTES=" "$CONF" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')
    [[ "${quota:-0}" != "0" ]] && _bw_accumulate "$PAM_USER"
    COUNT_FILE="${SESSION_DIR}/${PAM_USER}.count"
    count=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
    new_count=$(( count > 0 ? count - 1 : 0 ))
    echo "$new_count" > "$COUNT_FILE"
    SESSION_FILE="${SESSION_DIR}/${PAM_USER}.ips"
    if [[ -f "$SESSION_FILE" ]]; then
        awk -v ip="$CLIENT_IP" '!found && $0==ip {found=1; next} {print}' \
            "$SESSION_FILE" > "${SESSION_FILE}.tmp"
        mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
    fi
    remaining=$(grep -c "^${CLIENT_IP}$" "$SESSION_FILE" 2>/dev/null || echo 0)
    if [[ "$remaining" == "0" && "$CLIENT_IP" != "unknown" && "$CLIENT_IP" != "127.0.0.1" ]]; then
        _bw_remove_ip_rule "$PAM_USER" "$CLIENT_IP"
    fi
    _bw_log "SESSION_CLOSE: $PAM_USER from $CLIENT_IP (sisa: ${new_count})"
fi

exit 0
