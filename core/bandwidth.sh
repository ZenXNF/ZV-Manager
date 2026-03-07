#!/bin/bash
# ============================================================
#   ZV-Manager - Bandwidth Tracking (IP-based)
#   Track by client IP karena sshd jalan sebagai root,
#   bukan sebagai UID user — uid-owner tidak bisa dipakai
# ============================================================
ACCOUNT_DIR="/etc/zv-manager/accounts/ssh"
BW_LOG="/var/log/zv-manager/bandwidth.log"
BW_SESSION_DIR="/tmp/zv-bw"

_bw_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$BW_LOG" 2>/dev/null; }

_bw_chain() { echo "BW_${1}"; }

_bw_init_user() {
    local user="$1"
    local chain; chain=$(_bw_chain "$user")
    mkdir -p "$BW_SESSION_DIR"
    iptables -N "$chain" 2>/dev/null
    iptables -C "$chain" -j RETURN 2>/dev/null || \
        iptables -A "$chain" -j RETURN
    _bw_log "INIT: $user"
}

_bw_add_ip_rule() {
    local user="$1" ip="$2"
    local chain; chain=$(_bw_chain "$user")
    iptables -N "$chain" 2>/dev/null
    iptables -C "$chain" -j RETURN 2>/dev/null || \
        iptables -A "$chain" -j RETURN
    iptables -C OUTPUT -d "$ip" -j "$chain" 2>/dev/null || \
        iptables -I OUTPUT -d "$ip" -j "$chain"
}

_bw_remove_ip_rule() {
    local user="$1" ip="$2"
    local chain; chain=$(_bw_chain "$user")
    iptables -D OUTPUT -d "$ip" -j "$chain" 2>/dev/null
}

_bw_get_active_ips() {
    local user="$1"
    local estab_ips
    estab_ips=$(ss -tn state established 2>/dev/null | \
        awk '$4 ~ /:22$|:500$|:40000$|:109$|:143$/ {print $5}' | \
        cut -d: -f1 | grep -v '^$' | sort -u)
    [[ -z "$estab_ips" ]] && return

    grep "Accepted.*for ${user} from" /var/log/auth.log 2>/dev/null | \
        grep -oP 'from \K[\d.]+' | sort -u | \
        while IFS= read -r ip; do
            echo "$estab_ips" | grep -qx "$ip" && echo "$ip"
        done
}

_bw_read_and_reset() {
    local user="$1"
    local chain; chain=$(_bw_chain "$user")
    local bytes
    bytes=$(iptables -nvx -L "$chain" 2>/dev/null | \
        awk '/RETURN/ {print $2; exit}')
    bytes=${bytes:-0}
    [[ "$bytes" -gt 0 ]] && iptables -Z "$chain" 2>/dev/null
    echo "$bytes"
}

_bw_accumulate() {
    local user="$1"
    local conf="${ACCOUNT_DIR}/${user}.conf"
    [[ ! -f "$conf" ]] && return

    local delta; delta=$(_bw_read_and_reset "$user")
    [[ "${delta:-0}" -eq 0 ]] && return

    local cur; cur=$(grep "^BW_USED_BYTES=" "$conf" | cut -d= -f2 | tr -d '[:space:]')
    cur=${cur:-0}
    local new=$(( cur + delta ))

    if grep -q "^BW_USED_BYTES=" "$conf"; then
        sed -i "s/^BW_USED_BYTES=.*/BW_USED_BYTES=${new}/" "$conf"
    else
        echo "BW_USED_BYTES=${new}" >> "$conf"
    fi

    _bw_log "ACCUMULATE: $user +${delta}B total=${new}B"
    echo "$new"
}

_bw_block() {
    local user="$1"
    local conf="${ACCOUNT_DIR}/${user}.conf"
    [[ ! -f "$conf" ]] && return 1

    pkill -u "$user" -KILL 2>/dev/null
    passwd -l "$user" &>/dev/null

    local session_file="${BW_SESSION_DIR}/${user}.ips"
    if [[ -f "$session_file" ]]; then
        while IFS= read -r ip; do
            [[ -z "$ip" ]] && continue
            iptables -C OUTPUT -d "$ip" -j DROP 2>/dev/null || \
                iptables -I OUTPUT -d "$ip" -j DROP
        done < "$session_file"
    fi

    if grep -q "^BW_BLOCKED=" "$conf"; then
        sed -i "s/^BW_BLOCKED=.*/BW_BLOCKED=1/" "$conf"
    else
        echo "BW_BLOCKED=1" >> "$conf"
    fi
    _bw_log "BLOCKED: $user"
}

_bw_unblock() {
    local user="$1"
    local conf="${ACCOUNT_DIR}/${user}.conf"
    [[ ! -f "$conf" ]] && return 1

    passwd -u "$user" &>/dev/null

    local session_file="${BW_SESSION_DIR}/${user}.ips"
    if [[ -f "$session_file" ]]; then
        while IFS= read -r ip; do
            [[ -z "$ip" ]] && continue
            iptables -D OUTPUT -d "$ip" -j DROP 2>/dev/null
        done < "$session_file"
    fi

    if grep -q "^BW_BLOCKED=" "$conf"; then
        sed -i "s/^BW_BLOCKED=.*/BW_BLOCKED=0/" "$conf"
    else
        echo "BW_BLOCKED=0" >> "$conf"
    fi
    _bw_log "UNBLOCKED: $user"
}

_bw_cleanup_user() {
    local user="$1"
    local chain; chain=$(_bw_chain "$user")

    while iptables -D OUTPUT -j "$chain" 2>/dev/null; do :; done

    local session_file="${BW_SESSION_DIR}/${user}.ips"
    if [[ -f "$session_file" ]]; then
        while IFS= read -r ip; do
            [[ -z "$ip" ]] && continue
            iptables -D OUTPUT -d "$ip" -j "$chain" 2>/dev/null
            iptables -D OUTPUT -d "$ip" -j DROP 2>/dev/null
        done < "$session_file"
        rm -f "$session_file"
    fi

    iptables -F "$chain" 2>/dev/null
    iptables -X "$chain" 2>/dev/null
    _bw_log "CLEANUP: $user"
}

_bw_is_blocked() {
    grep -q "^BW_BLOCKED=1" "${ACCOUNT_DIR}/${1}.conf" 2>/dev/null
}

_bw_get_quota() {
    local q; q=$(grep "^BW_QUOTA_BYTES=" "${ACCOUNT_DIR}/${1}.conf" 2>/dev/null | \
        cut -d= -f2 | tr -d '[:space:]')
    echo "${q:-0}"
}

_bw_get_used() {
    local u; u=$(grep "^BW_USED_BYTES=" "${ACCOUNT_DIR}/${1}.conf" 2>/dev/null | \
        cut -d= -f2 | tr -d '[:space:]')
    echo "${u:-0}"
}

_bw_fmt() {
    local b="${1:-0}"
    [[ "$b" =~ ^[0-9]+$ ]] || { echo "0 B"; return; }
    if   (( b < 1024 ));       then echo "${b} B"
    elif (( b < 1048576 ));    then echo "$(( b / 1024 )).$(( (b % 1024) * 10 / 1024 )) KB"
    elif (( b < 1073741824 )); then echo "$(( b / 1048576 )).$(( (b % 1048576) * 10 / 1048576 )) MB"
    else                            echo "$(( b / 1073741824 )).$(( (b % 1073741824) * 100 / 1073741824 )) GB"
    fi
}

_bw_progress_bar() {
    local used="${1:-0}" quota="${2:-0}"
    (( quota == 0 )) && { echo "∞ (Unlimited)"; return; }
    local pct=$(( used * 100 / quota ))
    (( pct > 100 )) && pct=100
    local filled=$(( pct / 10 )) empty=$(( 10 - pct / 10 ))
    local bar="" i
    for (( i=0; i<filled; i++ )); do bar+="█"; done
    for (( i=0; i<empty;  i++ )); do bar+="░"; done
    echo "${bar} ${pct}%"
}

_bw_gb_to_bytes() { echo $(( ${1:-0} * 1024 * 1024 * 1024 )); }
_bw_bytes_to_gb() { echo "$(( ${1:-0} / 1073741824 ))"; }
