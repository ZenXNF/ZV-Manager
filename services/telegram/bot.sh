#!/bin/bash
# ============================================================
#   ZV-Manager - Telegram Bot
#   Flow: /start → inline keyboard → callback
#   Dipanggil sebagai service: zv-telegram
# ============================================================

source /etc/zv-manager/core/telegram.sh

ACCOUNT_DIR="/etc/zv-manager/accounts/ssh"
TRIAL_DIR="/etc/zv-manager/accounts/trial"
LOG="/var/log/zv-manager/telegram-bot.log"
OFFSET_FILE="/tmp/zv-tg-offset"

mkdir -p "$TRIAL_DIR" "$(dirname "$LOG")"

_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"; }

# ============================================================
# Kirim pesan biasa
# ============================================================
_reply() {
    local chat_id="$1" text="$2"
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -d "chat_id=${chat_id}" \
        --data-urlencode "text=${text}" \
        -d "parse_mode=HTML" \
        --max-time 10 &>/dev/null
}

# Kirim pesan dengan inline keyboard
# _reply_kb <chat_id> <text> <json_keyboard>
_reply_kb() {
    local chat_id="$1" text="$2" keyboard="$3"
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -H "Content-Type: application/json" \
        -d "{
            \"chat_id\": \"${chat_id}\",
            \"text\": $(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$text"),
            \"parse_mode\": \"HTML\",
            \"reply_markup\": {\"inline_keyboard\": ${keyboard}}
        }" \
        --max-time 10 &>/dev/null
}

# Answer callback query (hilangkan loading spinner di tombol)
_answer_callback() {
    local callback_id="$1" text="$2"
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/answerCallbackQuery" \
        -d "callback_query_id=${callback_id}" \
        --data-urlencode "text=${text}" \
        --max-time 5 &>/dev/null
}

# Edit pesan lama (setelah callback)
_edit_message() {
    local chat_id="$1" message_id="$2" text="$3"
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/editMessageText" \
        -H "Content-Type: application/json" \
        -d "{
            \"chat_id\": \"${chat_id}\",
            \"message_id\": \"${message_id}\",
            \"text\": $(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$text"),
            \"parse_mode\": \"HTML\"
        }" \
        --max-time 10 &>/dev/null
}

# ============================================================
# Keyboard home — muncul setelah /start
# ============================================================
_keyboard_home() {
    echo '[[{"text":"🎁 Trial Gratis 30 Menit","callback_data":"trial"}],[{"text":"ℹ️ Info Server","callback_data":"info"},{"text":"📋 Cara Pakai","callback_data":"howto"}]]'
}

# ============================================================
# /start — pesan utama dengan tombol
# ============================================================
_handle_start() {
    local chat_id="$1" first_name="$2"
    local domain
    domain=$(cat /etc/zv-manager/domain 2>/dev/null || echo "VPS")

    local text="👋 Halo, <b>${first_name}</b>!

Selamat datang di <b>ZV-Manager SSH Tunnel</b> 🚀

━━━━━━━━━━━━━━━━━━━
⚡ <b>Layanan</b>
• SSH Tunnel (OpenSSH + Dropbear)
• WebSocket (WS + WSS)
• UDP Custom
━━━━━━━━━━━━━━━━━━━
🖥️ <b>Server</b> : <code>${domain}</code>
━━━━━━━━━━━━━━━━━━━
Pilih menu di bawah 👇"

    _reply_kb "$chat_id" "$text" "$(_keyboard_home)"
}

# ============================================================
# Callback: info server
# ============================================================
_cb_info() {
    local chat_id="$1" cb_id="$2" message_id="$3"
    local domain
    domain=$(cat /etc/zv-manager/domain 2>/dev/null || echo "VPS")

    _answer_callback "$cb_id" ""
    _edit_message "$chat_id" "$message_id" "🖥️ <b>Info Server</b>

━━━━━━━━━━━━━━━━━━━
🌐 <b>Host</b>    : <code>${domain}</code>
━━━━━━━━━━━━━━━━━━━
🔌 <b>Port SSH</b>
• OpenSSH  : 22, 500, 40000
• Dropbear : 109, 143
━━━━━━━━━━━━━━━━━━━
🌐 <b>Port Tunnel</b>
• WS  (HTTP) : 80
• WSS (SSL)  : 443
• UDP Custom : 1-65535
━━━━━━━━━━━━━━━━━━━

⬅️ Tekan /start untuk kembali"
}

# ============================================================
# Callback: cara pakai
# ============================================================
_cb_howto() {
    local chat_id="$1" cb_id="$2" message_id="$3"
    local domain
    domain=$(cat /etc/zv-manager/domain 2>/dev/null || echo "VPS")

    _answer_callback "$cb_id" ""
    _edit_message "$chat_id" "$message_id" "📋 <b>Cara Pakai</b>

━━━━━━━━━━━━━━━━━━━
<b>1. HTTP Custom / NetMod</b>
Format WS:
<code>${domain}:80@user:pass</code>

Format WSS:
<code>${domain}:443@user:pass</code>

━━━━━━━━━━━━━━━━━━━
<b>2. Payload WS (Non-SSL)</b>
<code>GET / HTTP/1.1[crlf]Host: ${domain}[crlf]Upgrade: websocket[crlf][crlf]</code>

<b>3. Payload WSS (CONNECT)</b>
<code>CONNECT ${domain}:443 HTTP/1.0[crlf][crlf]</code>
━━━━━━━━━━━━━━━━━━━

⬅️ Tekan /start untuk kembali"
}

# ============================================================
# Callback: trial
# ============================================================
_already_trial_today() {
    local user_id="$1"
    local today
    today=$(date +"%Y-%m-%d")
    local f="${TRIAL_DIR}/${user_id}.used"
    [[ -f "$f" ]] && [[ "$(cat "$f")" == "$today" ]]
}

_cb_trial() {
    local chat_id="$1" cb_id="$2" message_id="$3" first_name="$4"

    _answer_callback "$cb_id" "⏳ Membuat akun trial..."

    if _already_trial_today "$chat_id"; then
        _edit_message "$chat_id" "$message_id" "❌ <b>Sudah Trial Hari Ini</b>

Kamu sudah menggunakan trial hari ini.
Trial hanya bisa digunakan <b>1x per hari</b>.

Coba lagi besok! 😊

⬅️ Tekan /start untuk kembali"
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

    useradd -e "$exp_date" -s /bin/false -M "$username" &>/dev/null
    echo "$username:$password" | chpasswd &>/dev/null

    mkdir -p "$ACCOUNT_DIR"
    cat > "${ACCOUNT_DIR}/${username}.conf" <<EOF
USERNAME=$username
PASSWORD=$password
LIMIT=1
EXPIRED=$exp_date
EXPIRED_TS=$exp_ts
CREATED=$(date +"%Y-%m-%d")
IS_TRIAL=1
TG_USER_ID=$chat_id
EOF

    date +"%Y-%m-%d" > "${TRIAL_DIR}/${chat_id}.used"

    local domain
    domain=$(cat /etc/zv-manager/domain 2>/dev/null || echo "VPS")

    _log "TRIAL: chat_id=$chat_id username=$username exp=${exp_display}"

    _edit_message "$chat_id" "$message_id" "✅ <b>Akun Trial Berhasil!</b>

━━━━━━━━━━━━━━━━━━━
🖥️ <b>Host</b>     : <code>${domain}</code>
👤 <b>Username</b> : <code>${username}</code>
🔑 <b>Password</b> : <code>${password}</code>
⏱️ <b>Durasi</b>   : 30 menit
⌛ <b>Expired</b>  : ${exp_display}
━━━━━━━━━━━━━━━━━━━
🔌 <b>Port SSH</b>
• OpenSSH  : 22, 500, 40000
• Dropbear : 109, 143
• WS  : 80  |  WSS : 443
━━━━━━━━━━━━━━━━━━━
🌐 <b>HTTP Custom</b>
WS  : <code>${domain}:80@${username}:${password}</code>
WSS : <code>${domain}:443@${username}:${password}</code>
━━━━━━━━━━━━━━━━━━━
⚠️ 1x/hari • Limit 1 perangkat

⬅️ Tekan /start untuk kembali"
}

# ============================================================
# Process update dari Telegram (message + callback_query)
# ============================================================
_process_update() {
    local raw="$1"

    # Parse via python3
    local parsed
    parsed=$(python3 -c "
import sys, json
try:
    u = json.loads(sys.argv[1])
    # message
    if 'message' in u:
        m = u['message']
        chat_id = str(m['chat']['id'])
        first   = m['from'].get('first_name','User')
        text    = m.get('text','')
        print('MSG|' + chat_id + '|' + first + '|' + text)
    # callback_query
    elif 'callback_query' in u:
        cq      = u['callback_query']
        cb_id   = str(cq['id'])
        chat_id = str(cq['message']['chat']['id'])
        msg_id  = str(cq['message']['message_id'])
        first   = cq['from'].get('first_name','User')
        data    = cq.get('data','')
        print('CB|' + cb_id + '|' + chat_id + '|' + msg_id + '|' + first + '|' + data)
except Exception as e:
    pass
" "$raw" 2>/dev/null)

    [[ -z "$parsed" ]] && return

    local kind
    kind=$(echo "$parsed" | cut -d'|' -f1)

    if [[ "$kind" == "MSG" ]]; then
        local chat_id first_name text
        IFS='|' read -r _ chat_id first_name text <<< "$parsed"
        local cmd
        cmd=$(echo "$text" | awk '{print $1}' | cut -d'@' -f1 | tr '[:upper:]' '[:lower:]')
        _log "MSG: chat_id=$chat_id cmd=$cmd from=$first_name"
        case "$cmd" in
            /start) _handle_start "$chat_id" "$first_name" ;;
            *)      _reply "$chat_id" "Ketuk /start untuk membuka menu 👇" ;;
        esac

    elif [[ "$kind" == "CB" ]]; then
        local cb_id chat_id msg_id first_name data
        IFS='|' read -r _ cb_id chat_id msg_id first_name data <<< "$parsed"
        _log "CB: chat_id=$chat_id data=$data from=$first_name"
        case "$data" in
            trial) _cb_trial  "$chat_id" "$cb_id" "$msg_id" "$first_name" ;;
            info)  _cb_info   "$chat_id" "$cb_id" "$msg_id" ;;
            howto) _cb_howto  "$chat_id" "$cb_id" "$msg_id" ;;
            *)     _answer_callback "$cb_id" "❓ Tidak dikenal" ;;
        esac
    fi
}

# ============================================================
# Main polling loop
# ============================================================
main() {
    tg_load || { _log "ERROR: Telegram config tidak ditemukan!"; exit 1; }
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
