#!/bin/bash
# ============================================================
#   ZV-Manager - Telegram Bot
#   Flow: /start → menu → protokol → server → aksi
# ============================================================

source /etc/zv-manager/core/telegram.sh

ACCOUNT_DIR="/etc/zv-manager/accounts/ssh"
TRIAL_DIR="/etc/zv-manager/accounts/trial"
SERVER_DIR="/etc/zv-manager/servers"
LOG="/var/log/zv-manager/telegram-bot.log"
OFFSET_FILE="/tmp/zv-tg-offset"

mkdir -p "$TRIAL_DIR" "$(dirname "$LOG")"

_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"; }

# ============================================================
# HTTP helpers
# ============================================================
_json_str() {
    python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$1" 2>/dev/null
}

_send() {
    local chat_id="$1" text="$2" keyboard="$3"
    local body
    body="{\"chat_id\":\"${chat_id}\",\"text\":$(_json_str "$text"),\"parse_mode\":\"HTML\""
    [[ -n "$keyboard" ]] && body="${body},\"reply_markup\":{\"inline_keyboard\":${keyboard}}"
    body="${body}}"
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -H "Content-Type: application/json" -d "$body" --max-time 10 &>/dev/null
}

_edit() {
    local chat_id="$1" msg_id="$2" text="$3" keyboard="$4"
    local body
    body="{\"chat_id\":\"${chat_id}\",\"message_id\":\"${msg_id}\",\"text\":$(_json_str "$text"),\"parse_mode\":\"HTML\""
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
# Baca server list — return "nama|domain|ip" per baris
# ============================================================
_get_servers() {
    for conf in "$SERVER_DIR"/*.conf; do
        [[ -f "$conf" ]] || continue
        unset NAME IP DOMAIN PORT
        source "$conf"
        echo "${NAME}|${DOMAIN:-$IP}|${IP}"
    done
}

# Hitung berapa akun SSH sudah dibuat di server tertentu
_count_accounts() {
    local target_ip="$1"
    local local_ip
    local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null)
    local count=0

    if [[ "$target_ip" == "$local_ip" ]]; then
        for f in "$ACCOUNT_DIR"/*.conf; do
            [[ -f "$f" ]] && count=$((count+1))
        done
    else
        # Remote: via zv-agent list
        local sconf="${SERVER_DIR}"
        for conf in "$sconf"/*.conf; do
            [[ -f "$conf" ]] || continue
            unset IP PASS PORT USER
            source "$conf"
            [[ "$IP" != "$target_ip" ]] && continue
            local raw
            raw=$(sshpass -p "$PASS" ssh \
                -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                -o ConnectTimeout=8 -o BatchMode=no \
                -p "$PORT" "${USER}@${IP}" "zv-agent list" 2>/dev/null)
            [[ "$raw" == "LIST-EMPTY" || -z "$raw" ]] && break
            count=$(echo "$raw" | grep -c '|' || echo 0)
            break
        done
    fi
    echo "$count"
}

# Baca tg config server (harga, quota, limit, max akun)
_load_tg_conf() {
    local server_name="$1"
    local tgconf="${SERVER_DIR}/${server_name}.tg.conf"
    # Default
    TG_HARGA_HARI="0"
    TG_HARGA_BULAN="0"
    TG_QUOTA="Unlimited"
    TG_LIMIT_IP="2"
    TG_MAX_AKUN="500"
    TG_SERVER_LABEL="$server_name"
    [[ -f "$tgconf" ]] && source "$tgconf"
}

# ============================================================
# Keyboard builders
# ============================================================

# Menu utama
_kb_home() {
    echo '[[{"text":"🛒 Buat Akun","callback_data":"menu_buat"}],[{"text":"🖥️ Info Server","callback_data":"menu_info"},{"text":"📋 Cara Pakai","callback_data":"howto"}]]'
}

# Pilih protokol (buat akun)
_kb_protokol_buat() {
    echo '[[{"text":"🔑 SSH Trial","callback_data":"buat_ssh"}],[{"text":"🏠 Kembali","callback_data":"home"}]]'
}

# Pilih protokol (info server)
_kb_protokol_info() {
    echo '[[{"text":"🔑 SSH","callback_data":"info_ssh"}],[{"text":"🏠 Kembali","callback_data":"home"}]]'
}

# List server untuk buat akun
_kb_server_buat() {
    local proto="$1"  # ssh
    local rows='['
    local first=true
    while IFS='|' read -r name domain ip; do
        [[ -z "$name" ]] && continue
        $first || rows="${rows},"
        rows="${rows}[{\"text\":\"🌐 ${name}\",\"callback_data\":\"dobuat_${proto}_${name}\"}]"
        first=false
    done < <(_get_servers)
    rows="${rows},[{\"text\":\"🏠 Kembali\",\"callback_data\":\"menu_buat\"}]]"
    echo "$rows"
}

# List server untuk info
_kb_server_info() {
    local rows='['
    local first=true
    while IFS='|' read -r name domain ip; do
        [[ -z "$name" ]] && continue
        $first || rows="${rows},"
        rows="${rows}[{\"text\":\"🌐 ${name}\",\"callback_data\":\"doinfo_ssh_${name}\"}]"
        first=false
    done < <(_get_servers)
    rows="${rows},[{\"text\":\"🏠 Kembali\",\"callback_data\":\"menu_info\"}]]"
    echo "$rows"
}

_kb_back_home() {
    echo '[[{"text":"🏠 Menu Utama","callback_data":"home"}]]'
}

_kb_back_buat() {
    echo '[[{"text":"⬅️ Kembali","callback_data":"buat_ssh"},{"text":"🏠 Menu Utama","callback_data":"home"}]]'
}

_kb_back_info() {
    echo '[[{"text":"⬅️ Kembali","callback_data":"info_ssh"},{"text":"🏠 Menu Utama","callback_data":"home"}]]'
}

# ============================================================
# Teks menu utama
# ============================================================
_text_home() {
    local first_name="$1" user_id="$2"
    local domain
    domain=$(cat /etc/zv-manager/domain 2>/dev/null || echo "VPS")
    cat <<EOF
👋 Halo, <b>${first_name}</b>!

🆔 <b>User ID</b> : <code>${user_id}</code>

━━━━━━━━━━━━━━━━━━━
⚡ <b>Layanan Tersedia</b>
🔑 SSH Tunnel
   • OpenSSH + Dropbear
   • WebSocket WS / WSS
   • UDP Custom
━━━━━━━━━━━━━━━━━━━
🖥️ <b>Server</b> : <code>${domain}</code>
━━━━━━━━━━━━━━━━━━━
Pilih menu di bawah 👇
EOF
}

# ============================================================
# /start
# ============================================================
_handle_start() {
    local chat_id="$1" first_name="$2"
    _send "$chat_id" "$(_text_home "$first_name" "$chat_id")" "$(_kb_home)"
}

# ============================================================
# Callbacks
# ============================================================

# Home
_cb_home() {
    local chat_id="$1" cb_id="$2" msg_id="$3" first_name="$4"
    _answer "$cb_id" ""
    _edit "$chat_id" "$msg_id" "$(_text_home "$first_name" "$chat_id")" "$(_kb_home)"
}

# Menu Buat Akun
_cb_menu_buat() {
    local chat_id="$1" cb_id="$2" msg_id="$3"
    _answer "$cb_id" ""
    _edit "$chat_id" "$msg_id" "🛒 <b>Buat Akun</b>

Pilih protokol yang kamu inginkan 👇" "$(_kb_protokol_buat)"
}

# Menu Info Server
_cb_menu_info() {
    local chat_id="$1" cb_id="$2" msg_id="$3"
    _answer "$cb_id" ""
    _edit "$chat_id" "$msg_id" "🖥️ <b>Info Server</b>

Pilih protokol untuk melihat info server 👇" "$(_kb_protokol_info)"
}

# Pilih protokol SSH → list server (buat)
_cb_buat_ssh() {
    local chat_id="$1" cb_id="$2" msg_id="$3"
    _answer "$cb_id" ""

    local servers
    servers=$(_get_servers)
    if [[ -z "$servers" ]]; then
        _edit "$chat_id" "$msg_id" "🔑 <b>SSH Trial</b>

❌ Belum ada server yang ditambahkan.
Hubungi admin untuk info lebih lanjut." "$(_kb_back_home)"
        return
    fi

    _edit "$chat_id" "$msg_id" "🔑 <b>SSH Trial</b>

Pilih server yang ingin kamu gunakan 👇" "$(_kb_server_buat "ssh")"
}

# Pilih protokol SSH → list server (info)
_cb_info_ssh() {
    local chat_id="$1" cb_id="$2" msg_id="$3"
    _answer "$cb_id" ""

    local servers
    servers=$(_get_servers)
    if [[ -z "$servers" ]]; then
        _edit "$chat_id" "$msg_id" "🖥️ <b>Info Server SSH</b>

❌ Belum ada server yang ditambahkan." "$(_kb_back_home)"
        return
    fi

    _edit "$chat_id" "$msg_id" "🖥️ <b>Info Server SSH</b>

Pilih server untuk melihat detail 👇" "$(_kb_server_info)"
}

# Detail info server
_cb_doinfo() {
    local chat_id="$1" cb_id="$2" msg_id="$3" proto="$4" server_name="$5"
    _answer "$cb_id" ""

    # Cari server
    local conf="${SERVER_DIR}/${server_name}.conf"
    if [[ ! -f "$conf" ]]; then
        _edit "$chat_id" "$msg_id" "❌ Server tidak ditemukan." "$(_kb_back_info)"
        return
    fi

    unset NAME IP DOMAIN PORT
    source "$conf"
    _load_tg_conf "$server_name"

    local domain="${DOMAIN:-$IP}"
    local count
    count=$(_count_accounts "$IP")

    # Format harga
    local harga_hari harga_bulan
    if [[ "$TG_HARGA_HARI" == "0" ]]; then
        harga_hari="Belum diset"
        harga_bulan="Belum diset"
    else
        harga_hari="Rp$(printf "%'.0f" "$TG_HARGA_HARI" 2>/dev/null || echo "$TG_HARGA_HARI")"
        harga_bulan="Rp$(printf "%'.0f" "$TG_HARGA_BULAN" 2>/dev/null || echo "$TG_HARGA_BULAN")"
    fi

    _edit "$chat_id" "$msg_id" "🌐 <b>${TG_SERVER_LABEL}</b>

━━━━━━━━━━━━━━━━━━━
🖥️ <b>Host</b>    : <code>${domain}</code>
💰 <b>Harga/hari</b>  : ${harga_hari}
📅 <b>Harga/30 hari</b>: ${harga_bulan}
📊 <b>Quota</b>   : ${TG_QUOTA}
🔢 <b>Limit IP</b> : ${TG_LIMIT_IP} IP/akun
👥 <b>Total Akun</b>: ${count}/${TG_MAX_AKUN}
━━━━━━━━━━━━━━━━━━━
🔌 <b>Port SSH</b>
• OpenSSH  : 22, 500, 40000
• Dropbear : 109, 143
• WS  : 80  |  WSS : 443
━━━━━━━━━━━━━━━━━━━" "$(_kb_back_info)"
}

# Buat trial SSH di server tertentu
_already_trial_today() {
    local user_id="$1"
    local f="${TRIAL_DIR}/${user_id}.used"
    [[ -f "$f" ]] && [[ "$(cat "$f")" == "$(date +"%Y-%m-%d")" ]]
}

_cb_dobuat() {
    local chat_id="$1" cb_id="$2" msg_id="$3" proto="$4" server_name="$5"
    _answer "$cb_id" "⏳ Membuat akun trial..."

    if _already_trial_today "$chat_id"; then
        _edit "$chat_id" "$msg_id" "❌ <b>Sudah Trial Hari Ini</b>

Kamu sudah menggunakan trial hari ini.
Trial hanya bisa digunakan <b>1x per hari</b>.

Coba lagi besok! 😊" "$(_kb_back_buat)"
        return
    fi

    local conf="${SERVER_DIR}/${server_name}.conf"
    if [[ ! -f "$conf" ]]; then
        _edit "$chat_id" "$msg_id" "❌ Server tidak ditemukan." "$(_kb_back_buat)"
        return
    fi

    unset NAME IP DOMAIN PORT USER PASS
    source "$conf"
    _load_tg_conf "$server_name"

    local domain="${DOMAIN:-$IP}"
    local local_ip
    local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null)
    local is_local=false
    [[ "$IP" == "$local_ip" ]] && is_local=true

    # Cek max akun
    local count
    count=$(_count_accounts "$IP")
    if [[ "$count" -ge "$TG_MAX_AKUN" ]]; then
        _edit "$chat_id" "$msg_id" "❌ <b>Server Penuh</b>

Server <b>${NAME}</b> sudah mencapai kapasitas maksimum (${TG_MAX_AKUN} akun).
Silakan pilih server lain." "$(_kb_back_buat)"
        return
    fi

    # Generate akun
    local suffix
    suffix=$(tr -dc 'a-z0-9' </dev/urandom | head -c 5)
    local username="trial${suffix}"
    local password
    password=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 8)

    local now_ts exp_ts exp_display exp_date
    now_ts=$(date +%s)
    exp_ts=$(( now_ts + 1800 ))
    exp_display=$(TZ="Asia/Jakarta" date -d "@${exp_ts}" +"%H:%M WIB")
    exp_date=$(date -d "@${exp_ts}" +"%Y-%m-%d")

    if [[ "$is_local" == true ]]; then
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
EOF
    else
        # Remote via zv-agent
        local result
        result=$(sshpass -p "$PASS" ssh \
            -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=10 -o BatchMode=no \
            -p "$PORT" "${USER}@${IP}" \
            "zv-agent add $username $password $TG_LIMIT_IP 1" 2>/dev/null)
        if [[ "$result" != ADD-OK* ]]; then
            _edit "$chat_id" "$msg_id" "❌ Gagal membuat akun di server <b>${NAME}</b>.
Coba lagi nanti atau pilih server lain." "$(_kb_back_buat)"
            return
        fi
    fi

    date +"%Y-%m-%d" > "${TRIAL_DIR}/${chat_id}.used"
    _log "TRIAL: chat_id=$chat_id server=$server_name username=$username exp=$exp_display"

    _edit "$chat_id" "$msg_id" "✅ <b>Akun Trial Berhasil!</b>

━━━━━━━━━━━━━━━━━━━
🌐 <b>Server</b>   : ${TG_SERVER_LABEL}
🖥️ <b>Host</b>     : <code>${domain}</code>
👤 <b>Username</b> : <code>${username}</code>
🔑 <b>Password</b> : <code>${password}</code>
⏱️ <b>Durasi</b>   : 30 menit
⌛ <b>Expired</b>  : ${exp_display}
🔢 <b>Limit</b>    : ${TG_LIMIT_IP} perangkat
━━━━━━━━━━━━━━━━━━━
🔌 <b>Port SSH</b>
• OpenSSH  : 22, 500, 40000
• Dropbear : 109, 143
• WS : 80  |  WSS : 443
━━━━━━━━━━━━━━━━━━━
🌐 <b>HTTP Custom</b>
WS  : <code>${domain}:80@${username}:${password}</code>
WSS : <code>${domain}:443@${username}:${password}</code>
━━━━━━━━━━━━━━━━━━━
⚠️ Trial 1x/hari • Auto hapus saat expired" "$(_kb_back_home)"
}

# Cara pakai
_cb_howto() {
    local chat_id="$1" cb_id="$2" msg_id="$3"
    local domain
    domain=$(cat /etc/zv-manager/domain 2>/dev/null || echo "VPS")
    _answer "$cb_id" ""
    _edit "$chat_id" "$msg_id" "📋 <b>Cara Pakai</b>

━━━━━━━━━━━━━━━━━━━
<b>HTTP Custom / NetMod</b>

Format WS:
<code>host:80@user:pass</code>

Format WSS:
<code>host:443@user:pass</code>

━━━━━━━━━━━━━━━━━━━
<b>Payload WS (Non-SSL)</b>
<code>GET / HTTP/1.1[crlf]Host: ${domain}[crlf]Upgrade: websocket[crlf][crlf]</code>

<b>Payload WSS (CONNECT)</b>
<code>CONNECT ${domain}:443 HTTP/1.0[crlf][crlf]</code>
━━━━━━━━━━━━━━━━━━━" "$(_kb_back_home)"
}

# ============================================================
# Process update
# ============================================================
_process_update() {
    local raw="$1"
    local parsed
    parsed=$(python3 -c "
import sys, json
try:
    u = json.loads(sys.argv[1])
    if 'message' in u:
        m = u['message']
        print('MSG|'+str(m['chat']['id'])+'|'+m['from'].get('first_name','User')+'|'+m.get('text',''))
    elif 'callback_query' in u:
        cq = u['callback_query']
        print('CB|'+str(cq['id'])+'|'+str(cq['message']['chat']['id'])+'|'+str(cq['message']['message_id'])+'|'+cq['from'].get('first_name','User')+'|'+cq.get('data',''))
except: pass
" "$raw" 2>/dev/null)

    [[ -z "$parsed" ]] && return
    local kind; kind=$(echo "$parsed" | cut -d'|' -f1)

    if [[ "$kind" == "MSG" ]]; then
        local chat_id first_name text cmd
        IFS='|' read -r _ chat_id first_name text <<< "$parsed"
        cmd=$(echo "$text" | awk '{print $1}' | cut -d'@' -f1 | tr '[:upper:]' '[:lower:]')
        _log "MSG: $chat_id cmd=$cmd from=$first_name"
        [[ "$cmd" == "/start" ]] && _handle_start "$chat_id" "$first_name" || \
            _send "$chat_id" "Ketuk /start untuk membuka menu 👇"

    elif [[ "$kind" == "CB" ]]; then
        local cb_id chat_id msg_id first_name data
        IFS='|' read -r _ cb_id chat_id msg_id first_name data <<< "$parsed"
        _log "CB: $chat_id data=$data from=$first_name"

        # Parse callback data
        local action proto server_name
        action=$(echo "$data" | cut -d'_' -f1)
        local part2; part2=$(echo "$data" | cut -d'_' -f2)
        local part3; part3=$(echo "$data" | cut -d'_' -f3-)

        case "$data" in
            home)       _cb_home       "$chat_id" "$cb_id" "$msg_id" "$first_name" ;;
            menu_buat)  _cb_menu_buat  "$chat_id" "$cb_id" "$msg_id" ;;
            menu_info)  _cb_menu_info  "$chat_id" "$cb_id" "$msg_id" ;;
            buat_ssh)   _cb_buat_ssh   "$chat_id" "$cb_id" "$msg_id" ;;
            info_ssh)   _cb_info_ssh   "$chat_id" "$cb_id" "$msg_id" ;;
            howto)      _cb_howto      "$chat_id" "$cb_id" "$msg_id" ;;
            dobuat_ssh_*)
                server_name="${data#dobuat_ssh_}"
                _cb_dobuat "$chat_id" "$cb_id" "$msg_id" "ssh" "$server_name" ;;
            doinfo_ssh_*)
                server_name="${data#doinfo_ssh_}"
                _cb_doinfo "$chat_id" "$cb_id" "$msg_id" "ssh" "$server_name" ;;
            *)
                _answer "$cb_id" "❓"
                ;;
        esac
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
