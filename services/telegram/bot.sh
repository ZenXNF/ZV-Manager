#!/bin/bash
# ============================================================
#   ZV-Manager - Telegram Bot
# ============================================================

source /etc/zv-manager/core/telegram.sh

ACCOUNT_DIR="/etc/zv-manager/accounts/ssh"
TRIAL_DIR="/etc/zv-manager/accounts/trial"
SALDO_DIR="/etc/zv-manager/accounts/saldo"
SERVER_DIR="/etc/zv-manager/servers"
STATE_DIR="/tmp/zv-tg-state"
LOG="/var/log/zv-manager/telegram-bot.log"
OFFSET_FILE="/tmp/zv-tg-offset"

mkdir -p "$TRIAL_DIR" "$STATE_DIR" "$SALDO_DIR" "$(dirname "$LOG")"

_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"; }

# ============================================================
# State management
# ============================================================
_state_set() {
    local uid="$1" key="$2" val="$3"
    local f="${STATE_DIR}/${uid}"
    touch "$f"
    grep -v "^${key}=" "$f" > "${f}.tmp" 2>/dev/null && mv "${f}.tmp" "$f"
    echo "${key}=${val}" >> "$f"
}
_state_get() {
    local uid="$1" key="$2" f="${STATE_DIR}/${1}"
    [[ -f "$f" ]] && grep "^${key}=" "$f" | cut -d= -f2- | head -1
}
_state_clear() { rm -f "${STATE_DIR}/${1}"; }

# ============================================================
# Saldo management
# ============================================================
_saldo_get() {
    local uid="$1" f="${SALDO_DIR}/${uid}.conf"
    local val="0"
    [[ -f "$f" ]] && val=$(grep "^SALDO=" "$f" | cut -d= -f2 | tr -d '[:space:]')
    [[ -z "$val" || ! "$val" =~ ^[0-9]+$ ]] && val="0"
    echo "$val"
}
_saldo_set() {
    local uid="$1" amount="$2"
    echo "SALDO=${amount}" > "${SALDO_DIR}/${uid}.conf"
}
_saldo_deduct() {
    local uid="$1" amount="$2"
    local cur; cur=$(_saldo_get "$uid")
    local new=$(( cur - amount ))
    [[ $new -lt 0 ]] && return 1
    _saldo_set "$uid" "$new"
    return 0
}

# ============================================================
# HTTP helpers
# ============================================================
_jstr() {
    python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$1" 2>/dev/null
}

# Send new message
_send() {
    local chat_id="$1" text="$2" keyboard="$3"
    local body
    body="{\"chat_id\":\"${chat_id}\",\"text\":$(_jstr "$text"),\"parse_mode\":\"HTML\""
    [[ -n "$keyboard" ]] && body="${body},\"reply_markup\":{\"inline_keyboard\":${keyboard}}"
    body="${body}}"
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -H "Content-Type: application/json" -d "$body" --max-time 10 &>/dev/null
}

# Edit existing message
_edit() {
    local chat_id="$1" msg_id="$2" text="$3" keyboard="$4"
    local body
    body="{\"chat_id\":\"${chat_id}\",\"message_id\":\"${msg_id}\",\"text\":$(_jstr "$text"),\"parse_mode\":\"HTML\""
    [[ -n "$keyboard" ]] && body="${body},\"reply_markup\":{\"inline_keyboard\":${keyboard}}"
    body="${body}}"
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/editMessageText" \
        -H "Content-Type: application/json" -d "$body" --max-time 10 &>/dev/null
}

_answer() {
    local cb_id="$1" text="$2"
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/answerCallbackQuery" \
        -d "callback_query_id=${cb_id}" \
        --data-urlencode "text=${text}" --max-time 5 &>/dev/null
}

# ============================================================
# Server helpers
# ============================================================
_load_tg_conf() {
    local name="$1"
    TG_SERVER_LABEL="$name"; TG_HARGA_HARI="0"; TG_HARGA_BULAN="0"
    TG_QUOTA="Unlimited"; TG_LIMIT_IP="2"; TG_MAX_AKUN="500"
    local f="${SERVER_DIR}/${name}.tg.conf"
    [[ -f "$f" ]] && source "$f"
}

# Hitung akun NON-trial saja
_count_accounts() {
    local ip="$1"
    local local_ip; local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null)
    local count=0
    if [[ "$ip" == "$local_ip" ]]; then
        for f in "$ACCOUNT_DIR"/*.conf; do
            [[ -f "$f" ]] || continue
            local is_trial; is_trial=$(grep "^IS_TRIAL=" "$f" | cut -d= -f2)
            [[ "$is_trial" != "1" ]] && count=$((count+1))
        done
    else
        for conf in "$SERVER_DIR"/*.conf; do
            [[ -f "$conf" && "$conf" != *.tg.conf ]] || continue
            unset IP PASS PORT USER; source "$conf"
            [[ "$IP" != "$ip" ]] && continue
            local raw
            raw=$(sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no \
                -o ConnectTimeout=8 -o BatchMode=no \
                -p "$PORT" "${USER}@${IP}" "zv-agent list" 2>/dev/null)
            [[ "$raw" == "LIST-EMPTY" || -z "$raw" ]] && break
            # Remote tidak bisa bedain trial, tampilkan semua
            count=$(echo "$raw" | grep -c '|' || echo 0)
            break
        done
    fi
    echo "$count"
}

_get_server_list() {
    for conf in "$SERVER_DIR"/*.conf; do
        [[ -f "$conf" && "$conf" != *.tg.conf ]] || continue
        unset NAME IP DOMAIN; source "$conf"
        [[ -n "$NAME" ]] && echo "${NAME}|${DOMAIN:-$IP}|${IP}"
    done
}

_username_exists_local() {
    id "$1" &>/dev/null
}

# ============================================================
# Keyboards (tanpa emoji di tombol)
# ============================================================
_kb_home() {
    echo '[[{"text":"⚡ Buat Akun SSH","callback_data":"m_buat"}],[{"text":"🎁 Coba Gratis","callback_data":"m_trial"},{"text":"📖 Cara Pakai","callback_data":"m_howto"}]]'
}

_kb_server_list() {
    local prefix="$1" page="${2:-0}" per_page=6
    local start=$(( page * per_page ))
    local all=()
    while IFS= read -r line; do [[ -n "$line" ]] && all+=("$line"); done < <(_get_server_list)
    local total=${#all[@]}

    local rows='[' count=0 i=$start pair=""
    while [[ $i -lt $total && $count -lt $per_page ]]; do
        IFS='|' read -r name domain ip <<< "${all[$i]}"
        _load_tg_conf "$name"
        local btn="{\"text\":\"${TG_SERVER_LABEL}\",\"callback_data\":\"${prefix}_${name}\"}"
        if [[ $((count % 2)) -eq 0 ]]; then
            pair="$btn"
        else
            [[ $count -eq 1 ]] && rows="${rows}[${pair},${btn}]" || rows="${rows},[${pair},${btn}]"
            pair=""
        fi
        i=$((i+1)); count=$((count+1))
    done
    # Sisa baris ganjil
    if [[ -n "$pair" ]]; then
        [[ $count -eq 1 ]] && rows="${rows}[${pair}]" || rows="${rows},[${pair}]"
    fi

    # Navigasi
    local nav=""
    [[ $page -gt 0 ]] && nav="{\"text\":\"Prev\",\"callback_data\":\"${prefix}_pg_$((page-1))\"}"
    if [[ $((start + per_page)) -lt $total ]]; then
        local next="{\"text\":\"Next\",\"callback_data\":\"${prefix}_pg_$((page+1))\"}"
        [[ -n "$nav" ]] && nav="${nav},${next}" || nav="$next"
    fi
    [[ -n "$nav" ]] && rows="${rows},[${nav}]"

    rows="${rows},[{\"text\":\"Kembali\",\"callback_data\":\"home\"}]]"
    echo "$rows"
}

_kb_home_only() { echo '[[{"text":"🏠 Menu Utama","callback_data":"home"}]]'; }
_kb_confirm()   { echo "[[{\"text\":\"✅ Konfirmasi\",\"callback_data\":\"${1}_ok\"},{\"text\":\"❌ Batal\",\"callback_data\":\"home\"}]]"; }

# ============================================================
# Teks
# ============================================================
_text_home() {
    local fname="$1" uid="$2"
    local sc=0
    for conf in "$SERVER_DIR"/*.conf; do [[ -f "$conf" && "$conf" != *.tg.conf ]] && sc=$((sc+1)); done
    local saldo; saldo=$(_saldo_get "$uid")
    cat <<EOF
⚡ <b>ZV-Manager SSH Tunnel</b>
━━━━━━━━━━━━━━━━━━━
🖥️ Server   : ${sc} server
🆔 User ID  : <code>${uid}</code>
💰 Saldo    : Rp${saldo}
━━━━━━━━━━━━━━━━━━━
🔹 SSH Tunnel (OpenSSH + Dropbear)
🔹 WebSocket WS / WSS
🔹 UDP Custom
🔹 Support Bug Host / SNI
━━━━━━━━━━━━━━━━━━━
Pilih menu di bawah 👇
EOF
}

_text_server_list() {
    local title="$1" out="<b>${title}</b>\n\n"
    local found=false
    while IFS='|' read -r name domain ip; do
        [[ -z "$name" ]] && continue
        found=true
        _load_tg_conf "$name"
        local count; count=$(_count_accounts "$ip")
        local hh hb
        [[ "$TG_HARGA_HARI" == "0" ]] && hh="Hubungi admin" || hh="Rp${TG_HARGA_HARI}"
        [[ "$TG_HARGA_BULAN" == "0" ]] && hb="Hubungi admin" || hb="Rp${TG_HARGA_BULAN}"
        out+="🌐 <b>${TG_SERVER_LABEL}</b>
💰 Harga/hari  : ${hh}
📅 Harga/30hr  : ${hb}
📊 Quota       : ${TG_QUOTA}
🔢 Limit IP    : ${TG_LIMIT_IP} IP/akun
👥 Total Akun  : ${count}/${TG_MAX_AKUN}

"
    done < <(_get_server_list)
    $found || out+="Belum ada server yang tersedia.\n\n"
    out+="Pilih server:"
    echo -e "$out"
}

# ============================================================
# Kirim info akun (chat baru, bukan edit)
# ============================================================
_send_akun() {
    local chat_id="$1" type="$2"
    local username="$3" password="$4" domain="$5"
    local exp_display="$6" limit="$7" server_label="$8"
    local days="${9}" total_harga="${10}"

    local header extra=""
    [[ "$type" == "TRIAL" ]] && header="🎁 Akun Trial SSH" || header="⭐ Akun SSH Premium"

    if [[ "$type" == "BELI" ]]; then
        extra="
Masa Aktif : ${days} hari
Total Bayar : Rp${total_harga}"
    fi

    local txt
    txt="<b>${header}</b>
━━━━━━━━━━━━━━━━━━━
👤 <b>Informasi Akun</b>

Username : <code>${username}</code>
Password : <code>${password}</code>
Host     : <code>${domain}</code>
Server   : ${server_label}${extra}
Expired  : ${exp_display}
━━━━━━━━━━━━━━━━━━━
🔌 <b>Port</b>

OpenSSH  : 22, 500, 40000
Dropbear : 143, 109
BadVPN   : 7300
WS       : 80  |  WSS : 443
UDP      : 1-65535
━━━━━━━━━━━━━━━━━━━
🌐 <b>HTTP Custom</b>

WS  → <code>${domain}:80@${username}:${password}</code>
WSS → <code>${domain}:443@${username}:${password}</code>

📡 <b>UDP Custom</b>

Host : <code>${domain}</code>
Port : 1-65535
User : <code>${username}</code>
Pass : <code>${password}</code>
━━━━━━━━━━━━━━━━━━━
⚠️ Limit ${limit} perangkat · Dilarang share akun!"

    _send "$chat_id" "$txt"
}

# ============================================================
# /start
# ============================================================
_handle_start() {
    local chat_id="$1" fname="$2"
    _state_clear "$chat_id"
    _send "$chat_id" "$(_text_home "$fname" "$chat_id")" "$(_kb_home)"
}

# ============================================================
# Callback handlers
# ============================================================
_cb_home() {
    local chat_id="$1" cb_id="$2" msg_id="$3" fname="$4"
    _answer "$cb_id" ""
    _state_clear "$chat_id"
    _edit "$chat_id" "$msg_id" "$(_text_home "$fname" "$chat_id")" "$(_kb_home)"
}

# Buat Akun → list server
_cb_buat() {
    local chat_id="$1" cb_id="$2" msg_id="$3" page="${4:-0}"
    _answer "$cb_id" ""
    if [[ -z "$(_get_server_list)" ]]; then
        _edit "$chat_id" "$msg_id" "Belum ada server yang tersedia." "$(_kb_home_only)"
        return
    fi
    _edit "$chat_id" "$msg_id" "$(_text_server_list "Buat Akun SSH")" "$(_kb_server_list "s_buat" "$page")"
}

# Pilih server buat → SEND pesan baru, bukan edit
_cb_s_buat() {
    local chat_id="$1" cb_id="$2" msg_id="$3" sname="$4"
    local conf="${SERVER_DIR}/${sname}.conf"
    [[ ! -f "$conf" ]] && { _answer "$cb_id" "Server tidak ditemukan"; return; }

    unset NAME IP DOMAIN; source "$conf"
    _load_tg_conf "$sname"

    local count; count=$(_count_accounts "$IP")
    if [[ "$count" -ge "$TG_MAX_AKUN" ]]; then
        _answer "$cb_id" "Server penuh!"
        return
    fi

    _answer "$cb_id" ""
    _state_clear "$chat_id"
    _state_set "$chat_id" "STATE" "await_user"
    _state_set "$chat_id" "SERVER" "$sname"
    _state_set "$chat_id" "TYPE" "beli"

    # Send pesan baru — server list tetap di atas
    _send "$chat_id" "Server : <b>${TG_SERVER_LABEL}</b>

Ketik username yang kamu inginkan.
Hanya huruf kecil dan angka, minimal 3 karakter." "$(_kb_home_only)"
}

# Trial → list server
_cb_trial() {
    local chat_id="$1" cb_id="$2" msg_id="$3" page="${4:-0}"
    _answer "$cb_id" ""
    if [[ -z "$(_get_server_list)" ]]; then
        _edit "$chat_id" "$msg_id" "Belum ada server yang tersedia." "$(_kb_home_only)"
        return
    fi
    _edit "$chat_id" "$msg_id" "$(_text_server_list "Trial SSH Gratis")" "$(_kb_server_list "s_trial" "$page")"
}

# Pilih server trial → langsung buat, kirim pesan baru
# Cek trial per user+server, reset 24 jam dari waktu trial
_already_trial() {
    local uid="$1" sname="$2"
    local f="${TRIAL_DIR}/${uid}_${sname}.ts"
    [[ ! -f "$f" ]] && return 1
    local last_ts; last_ts=$(cat "$f" 2>/dev/null)
    [[ -z "$last_ts" ]] && return 1
    local now_ts; now_ts=$(date +%s)
    [[ $(( now_ts - last_ts )) -lt 86400 ]]
}
_mark_trial() {
    local uid="$1" sname="$2"
    date +%s > "${TRIAL_DIR}/${uid}_${sname}.ts"
}

_cb_s_trial() {
    local chat_id="$1" cb_id="$2" msg_id="$3" sname="$4"
    _answer "$cb_id" ""

    if _already_trial "$chat_id" "$sname"; then
        _send "$chat_id" "⚠️ Kamu sudah trial di server ini dalam 24 jam terakhir.
Coba lagi nanti atau pilih server lain." "$(_kb_home_only)"
        return
    fi

    local conf="${SERVER_DIR}/${sname}.conf"
    [[ ! -f "$conf" ]] && { _send "$chat_id" "Server tidak ditemukan." "$(_kb_home_only)"; return; }

    unset NAME IP DOMAIN PORT USER PASS; source "$conf"
    _load_tg_conf "$sname"
    local domain="${DOMAIN:-$IP}"
    local local_ip; local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null)

    local count; count=$(_count_accounts "$IP")
    if [[ "$count" -ge "$TG_MAX_AKUN" ]]; then
        _send "$chat_id" "Server <b>${TG_SERVER_LABEL}</b> sedang penuh. Coba server lain." "$(_kb_home_only)"
        return
    fi

    local suffix; suffix=$(tr -dc 'a-z0-9' </dev/urandom | head -c 5)
    local username="trial${suffix}"
    local password; password=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 8)
    local now_ts exp_ts exp_display exp_date
    now_ts=$(date +%s); exp_ts=$(( now_ts + 1800 ))
    exp_display=$(TZ="Asia/Jakarta" date -d "@${exp_ts}" +"%d %b %Y %H:%M WIB")
    exp_date=$(date -d "@${exp_ts}" +"%Y-%m-%d")

    if [[ "$IP" == "$local_ip" ]]; then
        useradd -e "$exp_date" -s /bin/false -M "$username" &>/dev/null
        echo "$username:$password" | chpasswd &>/dev/null
        mkdir -p "$ACCOUNT_DIR"
        cat > "${ACCOUNT_DIR}/${username}.conf" <<EOF
USERNAME=$username
PASSWORD=$password
LIMIT=${TG_LIMIT_IP}
EXPIRED=$exp_date
EXPIRED_TS=$exp_ts
CREATED=$(date +"%Y-%m-%d")
IS_TRIAL=1
TG_USER_ID=$chat_id
SERVER=$sname
EOF
    else
        local result
        result=$(sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no \
            -o ConnectTimeout=10 -o BatchMode=no \
            -p "$PORT" "${USER}@${IP}" \
            "zv-agent add $username $password $TG_LIMIT_IP 1" 2>/dev/null)
        if [[ "$result" != ADD-OK* ]]; then
            _send "$chat_id" "Gagal membuat akun. Coba lagi nanti." "$(_kb_home_only)"
            return
        fi
    fi

    _mark_trial "$chat_id" "$sname"
    _log "TRIAL: $chat_id server=$sname user=$username"
    _send_akun "$chat_id" "TRIAL" "$username" "$password" "$domain" \
        "$exp_display" "${TG_LIMIT_IP}" "${TG_SERVER_LABEL}" "" ""
}

# Cara pakai
_cb_howto() {
    local chat_id="$1" cb_id="$2" msg_id="$3"
    local domain; domain=$(cat /etc/zv-manager/domain 2>/dev/null || echo "host")
    _answer "$cb_id" ""
    _edit "$chat_id" "$msg_id" "<b>Cara Pakai</b>
━━━━━━━━━━━━━━━━━━━
<b>HTTP Custom / NetMod</b>

WS  → <code>host:80@user:pass</code>
WSS → <code>host:443@user:pass</code>

<b>Payload WS</b>
<code>GET / HTTP/1.1[crlf]Host: ${domain}[crlf]Upgrade: websocket[crlf][crlf]</code>

<b>Payload CONNECT (WSS)</b>
<code>CONNECT ${domain}:443 HTTP/1.0[crlf][crlf]</code>

<b>UDP Custom</b>
Host : server kamu
Port : 1-65535
━━━━━━━━━━━━━━━━━━━" "$(_kb_home_only)"
}

# ============================================================
# Multi-step input: buat akun
# ============================================================
_handle_input() {
    local chat_id="$1" text="$2"
    local state; state=$(_state_get "$chat_id" "STATE")
    [[ -z "$state" ]] && return 1

    case "$state" in
        await_user)
            # Validasi: huruf kecil & angka saja, 3-20 karakter
            if ! echo "$text" | grep -qE '^[a-z0-9]{3,20}$'; then
                _send "$chat_id" "Username tidak valid. Gunakan huruf kecil dan angka, 3-20 karakter.

Ketik username:"
                return 0
            fi
            local sname; sname=$(_state_get "$chat_id" "SERVER")
            # Cek duplikat lokal
            if _username_exists_local "$text"; then
                _send "$chat_id" "Username <b>${text}</b> sudah digunakan. Pilih username lain.

Ketik username:"
                return 0
            fi
            _state_set "$chat_id" "USERNAME" "$text"
            _state_set "$chat_id" "STATE" "await_pass"
            _send "$chat_id" "Ketik password (minimal 4 karakter):"
            ;;

        await_pass)
            if [[ ${#text} -lt 4 ]]; then
                _send "$chat_id" "Password minimal 4 karakter.

Ketik password:"
                return 0
            fi
            _state_set "$chat_id" "PASSWORD" "$text"
            _state_set "$chat_id" "STATE" "await_days"
            _send "$chat_id" "Berapa hari masa aktif? (1-365)"
            ;;

        await_days)
            if ! echo "$text" | grep -qE '^[0-9]+$' || [[ "$text" -lt 1 || "$text" -gt 365 ]]; then
                _send "$chat_id" "Masukkan angka antara 1 sampai 365.

Berapa hari masa aktif?"
                return 0
            fi
            local sname; sname=$(_state_get "$chat_id" "SERVER")
            local username; username=$(_state_get "$chat_id" "USERNAME")
            local password; password=$(_state_get "$chat_id" "PASSWORD")
            local days="$text"

            _load_tg_conf "$sname"
            local total=$(( TG_HARGA_HARI * days ))
            local saldo; saldo=$(_saldo_get "$chat_id")

            _state_set "$chat_id" "DAYS" "$days"
            _state_set "$chat_id" "STATE" "await_confirm"

            local hh; [[ "$TG_HARGA_HARI" == "0" ]] && hh="Gratis" || hh="Rp${TG_HARGA_HARI}/hari"

            local saldo_info=""
            if [[ "$TG_HARGA_HARI" != "0" ]]; then
                local saldo_int=$(( saldo + 0 ))
                local total_int=$(( total + 0 ))
                saldo_info="
💰 Saldo kamu : Rp${saldo_int}"
                if [[ $saldo_int -lt $total_int ]]; then
                    local kurang=$(( total_int - saldo_int ))
                    _send "$chat_id" "📋 <b>Konfirmasi Pesanan</b>
━━━━━━━━━━━━━━━━━━━
🌐 Server     : ${TG_SERVER_LABEL}
👤 Username   : <code>${username}</code>
🔑 Password   : <code>${password}</code>
📅 Masa Aktif : ${days} hari
💰 Harga      : ${hh}
💸 Total      : Rp${total_int}
💰 Saldo kamu : Rp${saldo_int}
❌ Kurang     : Rp${kurang}
━━━━━━━━━━━━━━━━━━━
Saldo tidak cukup. Hubungi admin untuk top up."
                    _state_clear "$chat_id"
                    return 0
                fi
            fi

            _send "$chat_id" "📋 <b>Konfirmasi Pesanan</b>
━━━━━━━━━━━━━━━━━━━
🌐 Server     : ${TG_SERVER_LABEL}
👤 Username   : <code>${username}</code>
🔑 Password   : <code>${password}</code>
📅 Masa Aktif : ${days} hari
💰 Harga      : ${hh}
💸 Total      : Rp${total}${saldo_info}
━━━━━━━━━━━━━━━━━━━
Lanjutkan?" "$(_kb_confirm "konfirm")"
            ;;
    esac
    return 0
}

# Konfirmasi buat akun
_cb_konfirm() {
    local chat_id="$1" cb_id="$2" msg_id="$3"
    local state; state=$(_state_get "$chat_id" "STATE")

    if [[ "$state" != "await_confirm" ]]; then
        _answer "$cb_id" "Sesi habis, mulai ulang"
        _state_clear "$chat_id"
        return
    fi

    _answer "$cb_id" "Membuat akun..."

    local sname; sname=$(_state_get "$chat_id" "SERVER")
    local username; username=$(_state_get "$chat_id" "USERNAME")
    local password; password=$(_state_get "$chat_id" "PASSWORD")
    local days; days=$(_state_get "$chat_id" "DAYS")

    local conf="${SERVER_DIR}/${sname}.conf"
    unset NAME IP DOMAIN PORT USER PASS; source "$conf"
    _load_tg_conf "$sname"

    local domain="${DOMAIN:-$IP}"
    local local_ip; local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null)

    # Expired berbasis jam beli (timestamp)
    local now_ts exp_ts exp_display exp_date
    now_ts=$(date +%s)
    exp_ts=$(( now_ts + days * 86400 ))
    exp_display=$(TZ="Asia/Jakarta" date -d "@${exp_ts}" +"%d %b %Y %H:%M WIB")
    exp_date=$(date -d "@${exp_ts}" +"%Y-%m-%d")
    local total=$(( TG_HARGA_HARI * days ))

    # Potong saldo
    if [[ "$TG_HARGA_HARI" != "0" && "$total" -gt 0 ]]; then
        if ! _saldo_deduct "$chat_id" "$total"; then
            _edit "$chat_id" "$msg_id" "Saldo tidak cukup. Hubungi admin untuk top up." "$(_kb_home_only)"
            _state_clear "$chat_id"
            return
        fi
    fi

    if [[ "$IP" == "$local_ip" ]]; then
        useradd -e "$exp_date" -s /bin/false -M "$username" &>/dev/null
        echo "$username:$password" | chpasswd &>/dev/null
        mkdir -p "$ACCOUNT_DIR"
        cat > "${ACCOUNT_DIR}/${username}.conf" <<EOF
USERNAME=$username
PASSWORD=$password
LIMIT=${TG_LIMIT_IP}
EXPIRED=$exp_date
EXPIRED_TS=$exp_ts
CREATED=$(date +"%Y-%m-%d")
IS_TRIAL=0
TG_USER_ID=$chat_id
SERVER=$sname
DOMAIN=$domain
EOF
    else
        local result
        result=$(sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no \
            -o ConnectTimeout=10 -o BatchMode=no \
            -p "$PORT" "${USER}@${IP}" \
            "zv-agent add $username $password $TG_LIMIT_IP $days" 2>/dev/null)
        if [[ "$result" != ADD-OK* ]]; then
            # Kembalikan saldo kalau gagal
            [[ "$total" -gt 0 ]] && _saldo_set "$chat_id" "$(( $(_saldo_get "$chat_id") + total ))"
            _edit "$chat_id" "$msg_id" "Gagal membuat akun. Saldo dikembalikan. Coba lagi nanti." "$(_kb_home_only)"
            _state_clear "$chat_id"
            return
        fi
    fi

    _state_clear "$chat_id"
    _log "BELI: $chat_id server=$sname user=$username days=$days total=$total"
    _send_akun "$chat_id" "BELI" "$username" "$password" "$domain" \
        "$exp_display" "${TG_LIMIT_IP}" "${TG_SERVER_LABEL}" "$days" "$total"
}

# ============================================================
# Parse update dengan python3 (aman untuk karakter khusus)
# ============================================================
_process_update() {
    local raw="$1"
    local parsed
    parsed=$(python3 << PYEOF 2>/dev/null
import sys, json

try:
    raw = '''${raw//\'/\'\\\'\'}'''
    u = json.loads(sys.argv[1] if len(sys.argv) > 1 else raw)
    if 'message' in u:
        m = u['message']
        print('MSG')
        print(str(m['chat']['id']))
        print(m['from'].get('first_name','User'))
        print(m.get('text',''))
    elif 'callback_query' in u:
        cq = u['callback_query']
        print('CB')
        print(str(cq['id']))
        print(str(cq['message']['chat']['id']))
        print(str(cq['message']['message_id']))
        print(cq['from'].get('first_name','User'))
        print(cq.get('data',''))
except: pass
PYEOF
)
    # Parse lebih aman: gunakan file temp
    local tmpf; tmpf=$(mktemp)
    python3 -c "
import sys, json
try:
    u = json.loads(sys.argv[1])
    if 'message' in u:
        m = u['message']
        lines = ['MSG', str(m['chat']['id']), m['from'].get('first_name','User'), m.get('text','')]
    elif 'callback_query' in u:
        cq = u['callback_query']
        lines = ['CB', str(cq['id']), str(cq['message']['chat']['id']),
                 str(cq['message']['message_id']),
                 cq['from'].get('first_name','User'), cq.get('data','')]
    else:
        sys.exit(0)
    for l in lines:
        print(l)
except: pass
" "$raw" > "$tmpf" 2>/dev/null

    local kind; kind=$(sed -n '1p' "$tmpf")
    [[ -z "$kind" ]] && { rm -f "$tmpf"; return; }

    if [[ "$kind" == "MSG" ]]; then
        local chat_id fname text
        chat_id=$(sed -n '2p' "$tmpf")
        fname=$(sed -n '3p' "$tmpf")
        text=$(sed -n '4p' "$tmpf")
        rm -f "$tmpf"

        local cmd; cmd=$(echo "$text" | awk '{print $1}' | cut -d'@' -f1 | tr '[:upper:]' '[:lower:]')
        _log "MSG $chat_id: ${text:0:40}"

        if [[ "$cmd" == "/start" ]]; then
            _handle_start "$chat_id" "$fname"
        else
            _handle_input "$chat_id" "$text" || \
                _send "$chat_id" "Ketuk /start untuk membuka menu."
        fi

    elif [[ "$kind" == "CB" ]]; then
        local cb_id chat_id msg_id fname data
        cb_id=$(sed -n '2p' "$tmpf")
        chat_id=$(sed -n '3p' "$tmpf")
        msg_id=$(sed -n '4p' "$tmpf")
        fname=$(sed -n '5p' "$tmpf")
        data=$(sed -n '6p' "$tmpf")
        rm -f "$tmpf"

        _log "CB $chat_id: $data"

        case "$data" in
            home)         _cb_home   "$chat_id" "$cb_id" "$msg_id" "$fname" ;;
            m_buat)       _cb_buat   "$chat_id" "$cb_id" "$msg_id" ;;
            m_trial)      _cb_trial  "$chat_id" "$cb_id" "$msg_id" ;;
            m_howto)      _cb_howto  "$chat_id" "$cb_id" "$msg_id" ;;
            konfirm_ok)   _cb_konfirm "$chat_id" "$cb_id" "$msg_id" ;;
            s_buat_pg_*)  _cb_buat   "$chat_id" "$cb_id" "$msg_id" "${data#s_buat_pg_}" ;;
            s_trial_pg_*) _cb_trial  "$chat_id" "$cb_id" "$msg_id" "${data#s_trial_pg_}" ;;
            s_buat_*)     _cb_s_buat  "$chat_id" "$cb_id" "$msg_id" "${data#s_buat_}" ;;
            s_trial_*)    _cb_s_trial "$chat_id" "$cb_id" "$msg_id" "${data#s_trial_}" ;;
            *)            _answer "$cb_id" "" ;;
        esac
    else
        rm -f "$tmpf"
    fi
}

# ============================================================
# Main loop
# ============================================================
main() {
    tg_load || { _log "ERROR: config tidak ditemukan!"; exit 1; }
    _log "=== Bot started ==="
    local offset=0
    [[ -f "$OFFSET_FILE" ]] && offset=$(cat "$OFFSET_FILE")

    while true; do
        local response
        response=$(curl -s --max-time 35 \
            "https://api.telegram.org/bot${TG_TOKEN}/getUpdates?offset=${offset}&timeout=30&allowed_updates=%5B%22message%22%2C%22callback_query%22%5D" \
            2>/dev/null)
        [[ -z "$response" || "$response" == *'"ok":false'* ]] && { sleep 5; continue; }

        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            _process_update "$line"
            local uid
            uid=$(echo "$line" | python3 -c "
import sys,json
try: print(json.loads(sys.stdin.read()).get('update_id',''))
except: pass
" 2>/dev/null)
            if [[ -n "$uid" ]]; then
                offset=$(( uid + 1 ))
                echo "$offset" > "$OFFSET_FILE"
            fi
        done < <(echo "$response" | python3 -c "
import sys,json
try:
    for u in json.load(sys.stdin).get('result',[]):
        print(json.dumps(u))
except: pass
" 2>/dev/null)
        sleep 1
    done
}

main
