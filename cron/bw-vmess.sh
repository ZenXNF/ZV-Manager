#!/bin/bash
# ============================================================
#   ZV-Manager - Bandwidth Monitor VMess (Xray Stats API)
#   Cron: setiap 5 menit (sama dengan bw-check.sh SSH)
# ============================================================

VMESS_DIR="/etc/zv-manager/accounts/vmess"
XRAY_BIN="/usr/local/bin/xray"
API_ADDR="127.0.0.1:10085"
LOG="/var/log/zv-manager/bw-vmess.log"
TG_STATE_DIR="/tmp/zv-tg-state"

mkdir -p "$TG_STATE_DIR"

# Load Telegram notif function
source /etc/zv-manager/services/telegram/bot.sh 2>/dev/null || true

_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

# Query bytes dari Xray stats API per user
# Xray stats name format: "user>>>USERNAME@vmess>>>traffic>>>uplink"
_query_xray_bytes() {
    local username="$1"
    local up=0 down=0

    # Cek xray + grpc tools tersedia
    if ! command -v grpc_cli &>/dev/null && ! "$XRAY_BIN" api --help &>/dev/null 2>&1; then
        echo "0"; return
    fi

    # Pakai xray api statsquery
    local tmpout
    tmpout=$(mktemp)
    "$XRAY_BIN" api statsquery \
        --server="$API_ADDR" \
        -pattern "${username}@vmess" \
        2>/dev/null > "$tmpout" || true

    # Parse output: "value: 12345"
    up=$(grep  -A2 "uplink"   "$tmpout" | grep "value:" | awk '{print $2}' | head -1)
    down=$(grep -A2 "downlink" "$tmpout" | grep "value:" | awk '{print $2}' | head -1)
    rm -f "$tmpout"

    echo $(( ${up:-0} + ${down:-0} ))
}

# Kirim notif Telegram ke user
_tg_notify_bw() {
    local tg_uid="$1" username="$2" used_gb="$3" limit_gb="$4"
    [[ -z "$tg_uid" || "$tg_uid" == "0" ]] && return

    local bot_token server_name
    bot_token=$(grep "^BOT_TOKEN=" /etc/zv-manager/servers/*.tg.conf 2>/dev/null | head -1 | cut -d= -f2 | tr -d '"')
    server_name=$(cat /etc/zv-manager/servers/*.tg.conf 2>/dev/null | grep "^TG_SERVER_LABEL=" | head -1 | cut -d= -f2 | tr -d '"')
    [[ -z "$bot_token" ]] && return

    local flag_file="${TG_STATE_DIR}/bw_notif_${username}"
    [[ -f "$flag_file" ]] && return  # sudah pernah notif

    local msg
    msg="⚠️ <b>Bandwidth VMess Hampir Habis!</b>%0A"
    msg+="━━━━━━━━━━━━━━━━━━━%0A"
    msg+="👤 Username : <code>${username}</code>%0A"
    msg+="🌐 Server   : ${server_name}%0A"
    msg+="📶 Terpakai : ${used_gb} GB / ${limit_gb} GB%0A"
    msg+="━━━━━━━━━━━━━━━━━━━%0A"
    msg+="Segera perpanjang akun Anda!"

    curl -s -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
        -d "chat_id=${tg_uid}&text=${msg}&parse_mode=HTML" &>/dev/null

    touch "$flag_file"
}

_tg_notify_bw_habis() {
    local tg_uid="$1" username="$2"
    [[ -z "$tg_uid" || "$tg_uid" == "0" ]] && return

    local bot_token server_name
    bot_token=$(grep "^BOT_TOKEN=" /etc/zv-manager/servers/*.tg.conf 2>/dev/null | head -1 | cut -d= -f2 | tr -d '"')
    server_name=$(cat /etc/zv-manager/servers/*.tg.conf 2>/dev/null | grep "^TG_SERVER_LABEL=" | head -1 | cut -d= -f2 | tr -d '"')
    [[ -z "$bot_token" ]] && return

    local msg
    msg="🚫 <b>Bandwidth VMess Habis!</b>%0A"
    msg+="━━━━━━━━━━━━━━━━━━━%0A"
    msg+="👤 Username : <code>${username}</code>%0A"
    msg+="🌐 Server   : ${server_name}%0A"
    msg+="❌ Akun dinonaktifkan sementara.%0A"
    msg+="━━━━━━━━━━━━━━━━━━━%0A"
    msg+="Hubungi admin untuk reset bandwidth."

    curl -s -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
        -d "chat_id=${tg_uid}&text=${msg}&parse_mode=HTML" &>/dev/null
}

_main() {
    [[ ! -d "$VMESS_DIR" ]] && exit 0

    local any=0
    for conf in "${VMESS_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue

        local username uuid tg_uid bw_limit_gb bw_used_bytes is_trial
        username=$(grep "^USERNAME=" "$conf" | cut -d= -f2 | tr -d '"')
        uuid=$(grep "^UUID=" "$conf" | cut -d= -f2 | tr -d '"')
        tg_uid=$(grep "^TG_USER_ID=" "$conf" | cut -d= -f2 | tr -d '"')
        bw_limit_gb=$(grep "^BW_LIMIT_GB=" "$conf" | cut -d= -f2 | tr -d '"')
        bw_used_bytes=$(grep "^BW_USED_BYTES=" "$conf" | cut -d= -f2 | tr -d '"')
        is_trial=$(grep "^IS_TRIAL=" "$conf" | cut -d= -f2 | tr -d '"')

        bw_limit_gb=${bw_limit_gb:-0}
        bw_used_bytes=${bw_used_bytes:-0}

        # Skip jika unlimited (0) atau trial
        [[ "$bw_limit_gb" == "0" || "$is_trial" == "1" ]] && continue
        any=1

        # Query traffic baru dari Xray stats API
        local new_bytes
        new_bytes=$(_query_xray_bytes "$username")

        # Akumulasi (Xray reset tiap restart, jadi tambahkan ke existing)
        local total_bytes=$(( bw_used_bytes + new_bytes ))

        # Update conf
        local tmpf
        tmpf=$(mktemp)
        grep -v "^BW_USED_BYTES=\|^BW_LAST_CHECK=" "$conf" > "$tmpf"
        echo "BW_USED_BYTES=\"${total_bytes}\"" >> "$tmpf"
        echo "BW_LAST_CHECK=\"$(date +%s)\"" >> "$tmpf"
        mv "$tmpf" "$conf"

        # Hitung dalam GB
        local used_gb
        used_gb=$(python3 -c "print(round(${total_bytes}/1073741824, 2))")
        local limit_bytes=$(( bw_limit_gb * 1073741824 ))

        _log "$username: ${used_gb} GB / ${bw_limit_gb} GB"

        # Cek 80% warning
        local warn_bytes=$(( limit_bytes * 80 / 100 ))
        if (( total_bytes >= warn_bytes && total_bytes < limit_bytes )); then
            _tg_notify_bw "$tg_uid" "$username" "$used_gb" "$bw_limit_gb"
        fi

        # Cek habis → nonaktifkan
        if (( total_bytes >= limit_bytes )); then
            _log "$username BANDWIDTH HABIS — disable"
            _tg_notify_bw_habis "$tg_uid" "$username"
            # Rename conf → .disabled sehingga tidak masuk xray config
            mv "$conf" "${conf%.conf}.disabled"
            # Reload xray
            source /etc/zv-manager/services/xray/install.sh 2>/dev/null
            reload_xray
        fi
    done
}

_main
