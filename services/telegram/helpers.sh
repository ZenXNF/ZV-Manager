#!/bin/bash
# ============================================================
#   ZV-Manager - Telegram Bot Helpers
#   _log, _fmt, _jstr, state, saldo, HTTP, server helpers
# ============================================================

_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"; }

# Format angka: 100000 → 100.000 (pure bash)
_fmt() {
    local n="${1//[^0-9]/}" result="" len i
    [[ -z "$n" || "$n" == "0" ]] && { echo "0"; return; }
    n=$(( 10#$n ))
    n="${n#-}"
    len=${#n}
    for (( i=0; i<len; i++ )); do
        [[ $i -gt 0 && $(( (len - i) % 3 )) -eq 0 ]] && result="${result}."
        result="${result}${n:$i:1}"
    done
    echo "$result"
}

# ============================================================
# State management
# ============================================================
_state_set() {
    local f="${STATE_DIR}/${1}"; touch "$f"
    grep -v "^${2}=" "$f" > "${f}.tmp" 2>/dev/null && mv "${f}.tmp" "$f"
    echo "${2}=${3}" >> "$f"
}
_state_get() {
    local f="${STATE_DIR}/${1}"
    [[ -f "$f" ]] && grep "^${2}=" "$f" | cut -d= -f2- | head -1 || echo ""
}
_state_clear() { rm -f "${STATE_DIR}/${1}"; }

# ============================================================
# Saldo
# ============================================================
_saldo_get() {
    local f="${SALDO_DIR}/${1}.saldo" val="0"
    if [[ -f "$f" ]]; then
        val=$(cat "$f" | tr -d "[:space:]")
        val="${val#SALDO=}"
    fi
    [[ "$val" =~ ^[0-9]+$ ]] || val="0"
    echo "$val"
}
_saldo_set() {
    local amount="$2"
    [[ "$amount" =~ ^[0-9]+$ ]] || amount="0"
    echo "$amount" > "${SALDO_DIR}/${1}.saldo"
}
_saldo_deduct() {
    local cur=$(( 10#$(_saldo_get "$1") ))
    local amt=$(( 10#${2} ))
    [[ $cur -lt $amt ]] && return 1
    _saldo_set "$1" "$(( cur - amt ))"
}

# ============================================================
# HTTP helpers (curl background)
# ============================================================
# Escape string ke JSON (pure bash)
_jstr() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    echo "\"$s\""
}

_send() {
    local body="{\"chat_id\":\"${1}\",\"text\":$(_jstr "$2"),\"parse_mode\":\"HTML\""
    [[ -n "$3" ]] && body="${body},\"reply_markup\":{\"inline_keyboard\":${3}}"
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -H "Content-Type: application/json" -d "${body}}" --max-time 10 &>/dev/null &
}

_edit() {
    local body="{\"chat_id\":\"${1}\",\"message_id\":\"${2}\",\"text\":$(_jstr "$3"),\"parse_mode\":\"HTML\""
    [[ -n "$4" ]] && body="${body},\"reply_markup\":{\"inline_keyboard\":${4}}"
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/editMessageText" \
        -H "Content-Type: application/json" -d "${body}}" --max-time 10 &>/dev/null &
}

_answer() {
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/answerCallbackQuery" \
        -d "callback_query_id=${1}" --data-urlencode "text=${2}" --max-time 5 &>/dev/null &
}

# ============================================================
# Server helpers
# ============================================================
_load_tg_conf() {
    TG_SERVER_LABEL="$1"; TG_HARGA_HARI="0"; TG_HARGA_BULAN="0"
    TG_QUOTA="Unlimited"; TG_LIMIT_IP="2"; TG_MAX_AKUN="500"; TG_BW_PER_HARI="5"
    [[ -f "${SERVER_DIR}/${1}.tg.conf" ]] && source "${SERVER_DIR}/${1}.tg.conf"
}

_count_accounts() {
    local ip="$1" local_ip count=0
    local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null)

    # Cache 60 detik per IP — hindari SSH tiap klik
    local cache_key="${ip//\./_}"
    local cache_file="/tmp/zv-cnt-${cache_key}"
    if [[ -f "$cache_file" ]]; then
        local age=$(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0) ))
        [[ $age -lt 60 ]] && { cat "$cache_file"; return; }
    fi

    if [[ "$ip" == "$local_ip" ]]; then
        for f in "$ACCOUNT_DIR"/*.conf; do
            [[ -f "$f" ]] || continue
            [[ "$(grep "^IS_TRIAL=" "$f" | cut -d= -f2)" != "1" ]] && count=$(( count + 1 ))
        done
    else
        for conf in "$SERVER_DIR"/*.conf; do
            [[ -f "$conf" && "$conf" != *.tg.conf ]] || continue
            unset IP PASS PORT USER; source "$conf"
            [[ "$IP" != "$ip" ]] && continue
            local raw; raw=$(sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no \
                -o ConnectTimeout=8 -o BatchMode=no -p "$PORT" "${USER}@${IP}" \
                "zv-agent list" 2>/dev/null)
            [[ -n "$raw" && "$raw" != "LIST-EMPTY" ]] && \
                count=$(echo "$raw" | grep -c '|' 2>/dev/null || echo 0)
            break
        done
    fi
    echo "$count" | tee "$cache_file"
}

_get_server_list() {
    for conf in "$SERVER_DIR"/*.conf; do
        [[ -f "$conf" && "$conf" != *.tg.conf ]] || continue
        unset NAME IP DOMAIN; source "$conf"
        [[ -n "$NAME" ]] && echo "${NAME}|${DOMAIN:-$IP}|${IP}"
    done
}

_is_admin() {
    local uid; uid=$(echo "$1" | tr -d "[:space:]")
    local admin; admin=$(echo "$TG_ADMIN_ID" | tr -d "[:space:]")
    [[ "$uid" == "$admin" ]]
}

_register_user() {
    local uid="$1" fname="$2"
    mkdir -p "$USERS_DIR"
    local ufile="${USERS_DIR}/${uid}.user"
    if [[ ! -f "$ufile" ]]; then
        cat > "$ufile" <<EOF
UID=${uid}
NAME=${fname}
JOINED=$(date +"%Y-%m-%d %H:%M:%S")
EOF
        _log "NEW_USER: uid=$uid name=$fname"
    else
        sed -i "s/^NAME=.*/NAME=${fname}/" "$ufile"
    fi
}

_notify_admin_beli() {
    local tipe="$1" fname="$2" chat_id="$3" username="$4" sname="$5" days="$6" total="$7"
    [[ -z "$TG_ADMIN_ID" || "$chat_id" == "$TG_ADMIN_ID" ]] && return
    local icon label
    case "$tipe" in
        BELI)  icon="🛒"; label="Pembelian Baru" ;;
        RENEW) icon="🔄"; label="Perpanjang Akun" ;;
        BW)    icon="📶"; label="Tambah Bandwidth" ;;
        *)     icon="💡"; label="Transaksi" ;;
    esac
    local extra_line=""
    [[ "$tipe" == "BW" ]] && extra_line="
📶 Tambah   : ${days} GB" || extra_line="
📅 Durasi   : ${days} hari"
    _send "$TG_ADMIN_ID" "${icon} <b>${label}</b>
━━━━━━━━━━━━━━━━━━━
👤 User     : ${fname} (<code>${chat_id}</code>)
🖥️ Akun     : <code>${username}</code>
🌐 Server   : ${sname}${extra_line}
💸 Total    : Rp$(_fmt "$total")
━━━━━━━━━━━━━━━━━━━"
}
