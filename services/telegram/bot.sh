#!/bin/bash
# ============================================================
#   ZV-Manager - Telegram Bot
#   Flow: /start → menu → COBA GRATIS → protokol → server → akun
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
# Server helpers
# ============================================================
_load_tg_conf() {
    local name="$1"
    TG_SERVER_LABEL="$name"
    TG_HARGA_HARI="0"
    TG_HARGA_BULAN="0"
    TG_QUOTA="Unlimited"
    TG_LIMIT_IP="2"
    TG_MAX_AKUN="500"
    local f="${SERVER_DIR}/${name}.tg.conf"
    [[ -f "$f" ]] && source "$f"
}

_count_accounts() {
    local ip="$1"
    local local_ip
    local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null)
    local count=0
    if [[ "$ip" == "$local_ip" ]]; then
        for f in "$ACCOUNT_DIR"/*.conf; do [[ -f "$f" ]] && count=$((count+1)); done
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
            count=$(echo "$raw" | grep -c '|' || echo 0)
            break
        done
    fi
    echo "$count"
}

# Ambil list server sebagai array: "NAME|DOMAIN|IP"
_get_server_list() {
    for conf in "$SERVER_DIR"/*.conf; do
        [[ -f "$conf" && "$conf" != *.tg.conf ]] || continue
        unset NAME IP DOMAIN; source "$conf"
        [[ -n "$NAME" ]] && echo "${NAME}|${DOMAIN:-$IP}|${IP}"
    done
}

# ============================================================
# Keyboard builders
# ============================================================

# Menu utama
_kb_home() {
    echo '[[{"text":"⚡ BUAT AKUN","callback_data":"m_buat"},{"text":"♻️ PERPANJANG","callback_data":"m_perpanjang"}],[{"text":"🎁 COBA GRATIS","callback_data":"m_trial"},{"text":"💰 ISI SALDO","callback_data":"m_saldo"}],[{"text":"📋 ISI SALDO MANUAL","callback_data":"m_saldo_manual"}]]'
}

# Pilih protokol trial
_kb_trial_proto() {
    echo '[[{"text":"TRIAL SSH","callback_data":"trial_ssh"},{"text":"TRIAL VMESS","callback_data":"trial_na"}],[{"text":"TRIAL VLESS","callback_data":"trial_na"},{"text":"TRIAL TROJAN","callback_data":"trial_na"}],[{"text":"↩️ Kembali","callback_data":"home"}]]'
}

# List server dengan pagination (8 per halaman, 2 kolom)
# _kb_server_list <action_prefix> <page>
_kb_server_list() {
    local prefix="$1" page="${2:-0}"
    local per_page=8
    local start=$(( page * per_page ))

    # Baca semua server
    local all_servers=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && all_servers+=("$line")
    done < <(_get_server_list)

    local total=${#all_servers[@]}
    local rows='['
    local first=true
    local i=$start
    local count=0

    while [[ $i -lt $total && $count -lt $per_page ]]; do
        IFS='|' read -r name domain ip <<< "${all_servers[$i]}"
        _load_tg_conf "$name"
        local label="${TG_SERVER_LABEL}"

        if $first; then
            rows="${rows}[{\"text\":\"${label}\",\"callback_data\":\"${prefix}_${name}\"}]"
            first=false
        else
            # Tambah ke baris terakhir jika baris ganjil, buat baris baru jika genap
            if (( count % 2 == 1 )); then
                rows="${rows%]},{\""text\":\"${label}\",\"callback_data\":\"${prefix}_${name}\"}]"
            else
                rows="${rows},[{\"text\":\"${label}\",\"callback_data\":\"${prefix}_${name}\"}]"
            fi
        fi

        i=$((i+1))
        count=$((count+1))
    done

    # Navigasi Next / Prev
    local nav='['
    local nav_first=true
    if [[ $page -gt 0 ]]; then
        nav="${nav}{\"text\":\"⬅️ Prev\",\"callback_data\":\"${prefix}_page_$((page-1))\"}"
        nav_first=false
    fi
    if [[ $((start + per_page)) -lt $total ]]; then
        $nav_first || nav="${nav},"
        nav="${nav}{\"text\":\"➡️ Next\",\"callback_data\":\"${prefix}_page_$((page+1))\"}"
        nav_first=false
    fi
    nav="${nav}]"

    $nav_first || rows="${rows},${nav}"
    rows="${rows},[{\"text\":\"↩️ Kembali ke Menu Utama\",\"callback_data\":\"home\"}]]"
    echo "$rows"
}

_kb_back_home() {
    echo '[[{"text":"🏠 Menu Utama","callback_data":"home"}]]'
}

# ============================================================
# Teks menu utama
# ============================================================
_text_home() {
    local first_name="$1" user_id="$2"
    local server_count=0
    for conf in "$SERVER_DIR"/*.conf; do
        [[ -f "$conf" && "$conf" != *.tg.conf ]] && server_count=$((server_count+1))
    done

    cat <<EOF
⚡ VPN PREMIUM SERVICE ⚡
〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓

📊 STATUS SYSTEM
━━━━━━━━━━━━━━━━━━━
🖥️  Server Tersedia  : ${server_count}
🆔  User ID          : ${user_id}
👤  Halo, ${first_name}!
━━━━━━━━━━━━━━━━━━━

⚙️ LAYANAN TERSEDIA
━━━━━━━━━━━━━━━━━━━
🔹 SSH Tunnel (OpenSSH + Dropbear)
🔹 WebSocket WS / WSS
🔹 UDP Custom
🔹 Support Bug Host / SNI
🔹 Support Wildcard Host

💎 FITUR PREMIUM
━━━━━━━━━━━━━━━━━━━
⚡ Full Speed & Low Ping
📡 Support Bug Host / SNI
📆 Masa Aktif Fleksibel
🤖 Auto Deploy Akun 24 Jam
━━━━━━━━━━━━━━━━━━━
EOF
}

# Teks daftar server + info untuk protokol tertentu
_text_server_list() {
    local proto_label="$1"
    local out="🌐 <b>SERVER ${proto_label}</b>\n\n"

    local found=false
    while IFS='|' read -r name domain ip; do
        [[ -z "$name" ]] && continue
        found=true
        _load_tg_conf "$name"

        local count
        count=$(_count_accounts "$ip")

        local harga_hari harga_bulan
        if [[ "$TG_HARGA_HARI" == "0" ]]; then
            harga_hari="Belum diset"
            harga_bulan="Belum diset"
        else
            harga_hari="Rp${TG_HARGA_HARI}"
            harga_bulan="Rp${TG_HARGA_BULAN}"
        fi

        out+="🌐 <b>${TG_SERVER_LABEL}</b> 🇮🇩
💰 Harga per hari: ${harga_hari}
📅 Harga per 30 hari: ${harga_bulan}
📊 Quota: ${TG_QUOTA}
🔢 Limit IP: ${TG_LIMIT_IP} IP
👥 Total Create Akun: ${count}/${TG_MAX_AKUN}

"
    done < <(_get_server_list)

    if ! $found; then
        out+="❌ Belum ada server yang tersedia."
    fi

    out+="Pilih server di bawah 👇"
    echo -e "$out"
}

# ============================================================
# Handlers
# ============================================================

_handle_start() {
    local chat_id="$1" first_name="$2"
    _send "$chat_id" "$(_text_home "$first_name" "$chat_id")" "$(_kb_home)"
}

_cb_home() {
    local chat_id="$1" cb_id="$2" msg_id="$3" first_name="$4"
    _answer "$cb_id" ""
    _edit "$chat_id" "$msg_id" "$(_text_home "$first_name" "$chat_id")" "$(_kb_home)"
}

_cb_trial_proto() {
    local chat_id="$1" cb_id="$2" msg_id="$3"
    _answer "$cb_id" ""
    _edit "$chat_id" "$msg_id" "🎁 <b>COBA GRATIS</b>

Pilih protokol yang ingin kamu coba 👇" "$(_kb_trial_proto)"
}

_cb_trial_na() {
    local chat_id="$1" cb_id="$2"
    _answer "$cb_id" "⚠️ Protokol ini belum tersedia"
}

# Trial SSH → tampil list server
_cb_trial_ssh() {
    local chat_id="$1" cb_id="$2" msg_id="$3" page="${4:-0}"
    _answer "$cb_id" ""

    local servers
    servers=$(_get_server_list)
    if [[ -z "$servers" ]]; then
        _edit "$chat_id" "$msg_id" "🔑 <b>Trial SSH</b>

❌ Belum ada server yang tersedia.
Hubungi admin untuk info lebih lanjut." "$(_kb_back_home)"
        return
    fi

    _edit "$chat_id" "$msg_id" \
        "$(_text_server_list "SSH TRIAL")" \
        "$(_kb_server_list "dotrial_ssh" "$page")"
}

# Buat akun trial SSH
_already_trial_today() {
    local uid="$1"
    local f="${TRIAL_DIR}/${uid}.used"
    [[ -f "$f" ]] && [[ "$(cat "$f")" == "$(date +"%Y-%m-%d")" ]]
}

_cb_dotrial_ssh() {
    local chat_id="$1" cb_id="$2" msg_id="$3" server_name="$4"
    _answer "$cb_id" "⏳ Membuat akun trial..."

    if _already_trial_today "$chat_id"; then
        _edit "$chat_id" "$msg_id" "❌ <b>Sudah Trial Hari Ini</b>

Kamu sudah menggunakan trial hari ini.
Trial hanya bisa digunakan <b>1x per hari</b>.

Coba lagi besok! 😊" "$(_kb_back_home)"
        return
    fi

    local conf="${SERVER_DIR}/${server_name}.conf"
    if [[ ! -f "$conf" ]]; then
        _edit "$chat_id" "$msg_id" "❌ Server tidak ditemukan." "$(_kb_back_home)"
        return
    fi

    unset NAME IP DOMAIN PORT USER PASS
    source "$conf"
    _load_tg_conf "$server_name"

    local domain="${DOMAIN:-$IP}"
    local local_ip
    local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null)

    # Cek kapasitas
    local count
    count=$(_count_accounts "$IP")
    if [[ "$count" -ge "$TG_MAX_AKUN" ]]; then
        _edit "$chat_id" "$msg_id" "❌ <b>Server Penuh</b>

Server <b>${TG_SERVER_LABEL}</b> sudah penuh (${TG_MAX_AKUN} akun).
Silakan pilih server lain." "$(_kb_back_home)"
        return
    fi

    # Generate
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
EOF
    else
        local result
        result=$(sshpass -p "$PASS" ssh \
            -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=no \
            -p "$PORT" "${USER}@${IP}" \
            "zv-agent add $username $password $TG_LIMIT_IP 1" 2>/dev/null)
        if [[ "$result" != ADD-OK* ]]; then
            _edit "$chat_id" "$msg_id" "❌ Gagal membuat akun di server <b>${TG_SERVER_LABEL}</b>.
Coba lagi nanti atau pilih server lain." "$(_kb_back_home)"
            return
        fi
    fi

    date +"%Y-%m-%d" > "${TRIAL_DIR}/${chat_id}.used"
    _log "TRIAL: chat_id=$chat_id server=$server_name username=$username"

    _edit "$chat_id" "$msg_id" "🌟 TRIAL SSH PREMIUM 🌟

💠 <b>Informasi Akun</b>
━━━━━━━━━━━━━━━━━━━
Username : <code>${username}</code>
Password : <code>${password}</code>
Host     : <code>${domain}</code>
Server   : ${TG_SERVER_LABEL}
━━━━━━━━━━━━━━━━━━━
💠 <b>Port Configuration</b>
━━━━━━━━━━━━━━━━━━━
OpenSSH  : 22, 500, 40000
Dropbear : 143, 109
BadVPN   : 7300
SSH WS   : 80
SSH WSS  : 443
━━━━━━━━━━━━━━━━━━━
🔗 <b>Format HTTP Custom</b>
━━━━━━━━━━━━━━━━━━━
Port 80  : <code>${domain}:80@${username}:${password}</code>
Port 443 : <code>${domain}:443@${username}:${password}</code>
━━━━━━━━━━━━━━━━━━━
⏱️ Expired : ${exp_display}
⚠️ Trial 1x/hari • Limit ${TG_LIMIT_IP} perangkat" "$(_kb_back_home)"
}

# Belum tersedia (perpanjang, saldo, dll)
_cb_soon() {
    local cb_id="$1" label="$2"
    _answer "$cb_id" "🚧 ${label} segera hadir!"
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
        _log "MSG: $chat_id cmd=$cmd"
        [[ "$cmd" == "/start" ]] && _handle_start "$chat_id" "$first_name" || \
            _send "$chat_id" "Ketuk /start untuk membuka menu 👇"

    elif [[ "$kind" == "CB" ]]; then
        local cb_id chat_id msg_id first_name data
        IFS='|' read -r _ cb_id chat_id msg_id first_name data <<< "$parsed"
        _log "CB: $chat_id data=$data"

        case "$data" in
            home)            _cb_home        "$chat_id" "$cb_id" "$msg_id" "$first_name" ;;
            m_trial)         _cb_trial_proto "$chat_id" "$cb_id" "$msg_id" ;;
            m_buat)          _cb_soon        "$cb_id" "Buat Akun" ;;
            m_perpanjang)    _cb_soon        "$cb_id" "Perpanjang" ;;
            m_saldo)         _cb_soon        "$cb_id" "Isi Saldo" ;;
            m_saldo_manual)  _cb_soon        "$cb_id" "Isi Saldo Manual" ;;
            trial_ssh)       _cb_trial_ssh   "$chat_id" "$cb_id" "$msg_id" ;;
            trial_na)        _cb_trial_na    "$chat_id" "$cb_id" ;;
            # Pagination server list
            dotrial_ssh_page_*)
                local page="${data#dotrial_ssh_page_}"
                _cb_trial_ssh "$chat_id" "$cb_id" "$msg_id" "$page"
                ;;
            # Pilih server untuk trial
            dotrial_ssh_*)
                local sname="${data#dotrial_ssh_}"
                _cb_dotrial_ssh "$chat_id" "$cb_id" "$msg_id" "$sname"
                ;;
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
