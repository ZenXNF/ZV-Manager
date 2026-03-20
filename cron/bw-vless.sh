#!/bin/bash
# ============================================================
#   ZV-Manager - Bandwidth Monitor VLESS (via zv-vless-agent)
#   Cron: setiap 5 menit
# ============================================================
VLESS_DIR="/etc/zv-manager/accounts/vless"
LOG="/var/log/zv-manager/bw-vless.log"
TG_STATE_DIR="/tmp/zv-tg-state"
mkdir -p "$TG_STATE_DIR"

source /etc/zv-manager/utils/remote.sh 2>/dev/null

_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

_bot_token() {
    grep "^TG_TOKEN=" /etc/zv-manager/telegram.conf 2>/dev/null | cut -d= -f2 | tr -d '"'
}

_server_label() {
    local sname="$1"
    local tg_conf="/etc/zv-manager/servers/${sname}.tg.conf"
    if [[ -f "$tg_conf" ]]; then
        grep "^TG_SERVER_LABEL=" "$tg_conf" | cut -d= -f2 | tr -d '"'
    else
        echo "$sname"
    fi
}

_tg_send() {
    local tg_uid="$1" msg="$2"
    [[ -z "$tg_uid" || "$tg_uid" == "0" ]] && return
    local bot_token; bot_token=$(_bot_token)
    [[ -z "$bot_token" ]] && return
    printf '%b' "$msg" | curl -s -X POST \
        "https://api.telegram.org/bot${bot_token}/sendMessage" \
        -F "chat_id=${tg_uid}" \
        -F "parse_mode=HTML" \
        -F "text=<-" --max-time 10 &>/dev/null
}

_tg_notify_bw_warn() {
    local tg_uid="$1" username="$2" used_gb="$3" limit_gb="$4" sname="$5"
    local flag="${TG_STATE_DIR}/bw_vless_notif_${username}"
    [[ -f "$flag" ]] && return
    local label; label=$(_server_label "$sname")
    _tg_send "$tg_uid" "⚠️ <b>Bandwidth VLESS Hampir Habis!</b>
━━━━━━━━━━━━━━━━━━━
👤 Username : <code>${username}</code>
🌐 Server   : ${label}
📶 Terpakai : ${used_gb} GB / ${limit_gb} GB
━━━━━━━━━━━━━━━━━━━
Segera perpanjang akun Anda!"
    touch "$flag"
}

_tg_notify_bw_habis() {
    local tg_uid="$1" username="$2" sname="$3"
    local label; label=$(_server_label "$sname")
    _tg_send "$tg_uid" "🚫 <b>Bandwidth VLESS Habis!</b>
━━━━━━━━━━━━━━━━━━━
👤 Username : <code>${username}</code>
🌐 Server   : ${label}
❌ Akun dinonaktifkan sementara.
━━━━━━━━━━━━━━━━━━━
Hubungi admin untuk reset bandwidth."
}

_main() {
    [[ ! -d "$VLESS_DIR" ]] && exit 0

    for conf in "${VLESS_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue
        local _username _exp_ts _is_trial _bw_limit
        _username=$(grep "^USERNAME=" "$conf" | cut -d= -f2 | tr -d '"' | tr -d '[:space:]')
        _exp_ts=$(grep "^EXPIRED_TS=" "$conf" | cut -d= -f2 | tr -d '"' | tr -d '[:space:]')
        _is_trial=$(grep "^IS_TRIAL=" "$conf" | cut -d= -f2 | tr -d '"' | tr -d '[:space:]')
        _bw_limit=$(grep "^BW_LIMIT_GB=" "$conf" | cut -d= -f2 | tr -d '"' | tr -d '[:space:]')

        # Skip trial, unlimited, atau expired
        [[ "$_is_trial" == "1" ]] && continue
        [[ "${_bw_limit:-0}" == "0" ]] && continue
        [[ -n "$_exp_ts" && "$_exp_ts" =~ ^[0-9]+$ && "$_exp_ts" -lt "$(date +%s)" ]] && continue

        unset USERNAME UUID TG_USER_ID BW_LIMIT_GB BW_USED_BYTES IS_TRIAL SERVER
        source "$conf"

        BW_LIMIT_GB="${BW_LIMIT_GB:-0}"
        BW_USED_BYTES="${BW_USED_BYTES:-0}"
        local sname="${SERVER:-local}"

        # Query bytes via agent
        local bw_result
        bw_result=$(remote_vless_agent "$sname" bw "$USERNAME" 2>/dev/null)
        if ! echo "$bw_result" | grep -q "^BW-OK"; then
            _log "$USERNAME [$sname]: Gagal query BW — $bw_result"
            continue
        fi

        local new_bytes; new_bytes=$(echo "$bw_result" | cut -d'|' -f3)
        new_bytes="${new_bytes:-0}"
        local total_bytes=$(( BW_USED_BYTES + new_bytes ))

        # Update conf lokal di brain
        local tmpf; tmpf=$(mktemp)
        grep -v "^BW_USED_BYTES=\|^BW_LAST_CHECK=" "$conf" > "$tmpf"
        echo "BW_USED_BYTES=\"${total_bytes}\"" >> "$tmpf"
        echo "BW_LAST_CHECK=\"$(date +%s)\"" >> "$tmpf"
        mv "$tmpf" "$conf"

        local used_gb; used_gb=$(python3 -c "print(round(${total_bytes}/1073741824, 2))")
        local limit_bytes=$(( BW_LIMIT_GB * 1073741824 ))

        _log "$USERNAME [$sname]: ${used_gb} GB / ${BW_LIMIT_GB} GB"

        # 80% warning
        local warn_bytes=$(( limit_bytes * 80 / 100 ))
        if (( total_bytes >= warn_bytes && total_bytes < limit_bytes )); then
            _tg_notify_bw_warn "$TG_USER_ID" "$USERNAME" "$used_gb" "$BW_LIMIT_GB" "$sname"
        fi

        # Habis → disable
        if (( total_bytes >= limit_bytes )); then
            _log "$USERNAME [$sname]: BANDWIDTH HABIS — disable"
            remote_vless_agent "$sname" disable "$USERNAME" &>/dev/null
            mv "$conf" "${conf%.conf}.disabled"
            _tg_notify_bw_habis "$TG_USER_ID" "$USERNAME" "$sname"
        fi
    done
}

_main
