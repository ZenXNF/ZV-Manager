#!/bin/bash
# ============================================================
#   ZV-Manager - Telegram Bot
#   Flow: /start → BUAT AKUN/COBA GRATIS → server → akun
# ============================================================

source /etc/zv-manager/core/telegram.sh

ACCOUNT_DIR="/etc/zv-manager/accounts/ssh"
TRIAL_DIR="/etc/zv-manager/accounts/trial"
SERVER_DIR="/etc/zv-manager/servers"
STATE_DIR="/tmp/zv-tg-state"
LOG="/var/log/zv-manager/telegram-bot.log"
OFFSET_FILE="/tmp/zv-tg-offset"

mkdir -p "$TRIAL_DIR" "$STATE_DIR" "$(dirname "$LOG")"

_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"; }

# ============================================================
# State management per user
# ============================================================
_state_set() {
    local uid="$1" key="$2" val="$3"
    local f="${STATE_DIR}/${uid}"
    # Hapus baris lama kalau ada
    touch "$f"
    grep -v "^${key}=" "$f" > "${f}.tmp" 2>/dev/null && mv "${f}.tmp" "$f"
    echo "${key}=${val}" >> "$f"
}

_state_get() {
    local uid="$1" key="$2"
    local f="${STATE_DIR}/${uid}"
    [[ -f "$f" ]] && grep "^${key}=" "$f" | cut -d= -f2- | head -1
}

_state_clear() {
    rm -f "${STATE_DIR}/${1}"
}

_state_exists() {
    local uid="$1" key="$2"
    local f="${STATE_DIR}/${uid}"
    [[ -f "$f" ]] && grep -q "^${key}=" "$f"
}

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

_get_server_list() {
    for conf in "$SERVER_DIR"/*.conf; do
        [[ -f "$conf" && "$conf" != *.tg.conf ]] || continue
        unset NAME IP DOMAIN; source "$conf"
        [[ -n "$NAME" ]] && echo "${NAME}|${DOMAIN:-$IP}|${IP}"
    done
}

# Cek apakah username sudah ada di server
_username_exists() {
    local ip="$1" uname="$2"
    local local_ip
    local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null)
    if [[ "$ip" == "$local_ip" ]]; then
        id "$uname" &>/dev/null && return 0
    else
        for conf in "$SERVER_DIR"/*.conf; do
            [[ -f "$conf" && "$conf" != *.tg.conf ]] || continue
            unset IP PASS PORT USER; source "$conf"
            [[ "$IP" != "$ip" ]] && continue
            local result
            result=$(sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no \
                -o ConnectTimeout=8 -o BatchMode=no \
                -p "$PORT" "${USER}@${IP}" "zv-agent info $uname" 2>/dev/null)
            [[ "$result" == INFO-OK* ]] && return 0
            break
        done
    fi
    return 1
}

# ============================================================
# Keyboards
# ============================================================
_kb_home() {
    echo '[[{"text":"⚡ BUAT AKUN","callback_data":"m_buat"}],[{"text":"🎁 COBA GRATIS","callback_data":"m_trial"}]]'
}

_kb_buat_proto() {
    echo '[[{"text":"🔑 CREATE SSH","callback_data":"buat_ssh"},{"text":"❌ CREATE VMESS","callback_data":"proto_na"}],[{"text":"❌ CREATE VLESS","callback_data":"proto_na"},{"text":"❌ CREATE TROJAN","callback_data":"proto_na"}],[{"text":"↩️ Kembali","callback_data":"home"}]]'
}

_kb_trial_proto() {
    echo '[[{"text":"🔑 TRIAL SSH","callback_data":"trial_ssh"},{"text":"❌ TRIAL VMESS","callback_data":"proto_na"}],[{"text":"❌ TRIAL VLESS","callback_data":"proto_na"},{"text":"❌ TRIAL TROJAN","callback_data":"proto_na"}],[{"text":"↩️ Kembali","callback_data":"home"}]]'
}

# List server 2 kolom + pagination
_kb_server_list() {
    local prefix="$1" page="${2:-0}"
    local per_page=6  # 3 baris × 2 kolom
    local start=$(( page * per_page ))

    local all_servers=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && all_servers+=("$line")
    done < <(_get_server_list)

    local total=${#all_servers[@]}
    local rows='['
    local i=$start
    local count=0
    local row_buf=""

    while [[ $i -lt $total && $count -lt $per_page ]]; do
        IFS='|' read -r name domain ip <<< "${all_servers[$i]}"
        _load_tg_conf "$name"
        local label="${TG_SERVER_LABEL} 🇮🇩"
        local btn="{\"text\":\"${label}\",\"callback_data\":\"${prefix}_${name}\"}"

        if [[ $((count % 2)) -eq 0 ]]; then
            # Baris baru
            [[ $count -gt 0 ]] && rows="${rows},[${row_buf}]"
            [[ $count -eq 0 ]] && rows="${rows}[${btn}"
            [[ $count -gt 0 ]] && row_buf="$btn"
        else
            if [[ $count -eq 1 && -z "$row_buf" ]]; then
                rows="${rows},${btn}]"
                row_buf=""
            else
                rows="${rows},[${row_buf},${btn}]"
                row_buf=""
            fi
        fi

        i=$((i+1))
        count=$((count+1))
    done

    # Tutup baris ganjil yang tersisa
    if [[ $((count % 2)) -eq 1 && $count -gt 0 ]]; then
        if [[ $count -eq 1 ]]; then
            rows="${rows}]"
        else
            rows="${rows},[${row_buf}]"
        fi
    fi

    # Navigasi
    local have_prev=false have_next=false
    [[ $page -gt 0 ]] && have_prev=true
    [[ $((start + per_page)) -lt $total ]] && have_next=true

    if $have_prev || $have_next; then
        local nav='['
        if $have_prev; then
            nav="${nav}{\"text\":\"⬅️ Back\",\"callback_data\":\"${prefix}_page_$((page-1))\"}"
            $have_next && nav="${nav},"
        fi
        $have_next && nav="${nav}{\"text\":\"➡️ Next\",\"callback_data\":\"${prefix}_page_$((page+1))\"}"
        nav="${nav}]"
        rows="${rows},${nav}"
    fi

    rows="${rows},[{\"text\":\"↩️ Kembali ke Menu Utama\",\"callback_data\":\"home\"}]]"
    echo "$rows"
}

_kb_back_home() {
    echo '[[{"text":"🏠 Menu Utama","callback_data":"home"}]]'
}

_kb_konfirmasi() {
    local prefix="$1"
    echo "[[{\"text\":\"✅ Konfirmasi\",\"callback_data\":\"${prefix}_confirm\"},{\"text\":\"❌ Batal\",\"callback_data\":\"home\"}]]"
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

# Teks daftar server + info
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
            harga_hari="Hubungi admin"
            harga_bulan="Hubungi admin"
        else
            harga_hari="Rp${TG_HARGA_HARI}"
            harga_bulan="Rp${TG_HARGA_BULAN}"
        fi
        out+="🌐 <b>${TG_SERVER_LABEL}</b> 🇮🇩
💰 Harga per hari: ${harga_hari}
📅 Harga per 30 hari: ${harga_bulan}
📊 Quota: ${TG_QUOTA}
🔢 Limit IP: ${TG_LIMIT_IP} IP
👥 Role: Member
👥 Total Create Akun: ${count}/${TG_MAX_AKUN}

"
    done < <(_get_server_list)

    $found || out+="❌ Belum ada server yang tersedia.\n\n"
    out+="Pilih server di bawah 👇"
    echo -e "$out"
}

# ============================================================
# Handlers
# ============================================================
_handle_start() {
    local chat_id="$1" first_name="$2"
    _state_clear "$chat_id"
    _send "$chat_id" "$(_text_home "$first_name" "$chat_id")" "$(_kb_home)"
}

_cb_home() {
    local chat_id="$1" cb_id="$2" msg_id="$3" first_name="$4"
    _answer "$cb_id" ""
    _state_clear "$chat_id"
    _edit "$chat_id" "$msg_id" "$(_text_home "$first_name" "$chat_id")" "$(_kb_home)"
}

_cb_menu_buat() {
    local chat_id="$1" cb_id="$2" msg_id="$3"
    _answer "$cb_id" ""
    _edit "$chat_id" "$msg_id" "⚡ <b>BUAT AKUN</b>

Pilih protokol yang ingin kamu buat 👇" "$(_kb_buat_proto)"
}

_cb_menu_trial() {
    local chat_id="$1" cb_id="$2" msg_id="$3"
    _answer "$cb_id" ""
    _edit "$chat_id" "$msg_id" "🎁 <b>COBA GRATIS</b>

Pilih protokol yang ingin kamu coba 👇" "$(_kb_trial_proto)"
}

_cb_proto_na() {
    local cb_id="$1"
    _answer "$cb_id" "⚠️ Protokol ini belum tersedia"
}

# ── Buat SSH: tampil list server ──
_cb_buat_ssh() {
    local chat_id="$1" cb_id="$2" msg_id="$3" page="${4:-0}"
    _answer "$cb_id" ""
    local servers; servers=$(_get_server_list)
    if [[ -z "$servers" ]]; then
        _edit "$chat_id" "$msg_id" "❌ Belum ada server yang tersedia." "$(_kb_back_home)"
        return
    fi
    _edit "$chat_id" "$msg_id" \
        "$(_text_server_list "SSH")" \
        "$(_kb_server_list "dobuat_ssh" "$page")"
}

# ── Pilih server → minta username ──
_cb_dobuat_ssh_server() {
    local chat_id="$1" cb_id="$2" msg_id="$3" server_name="$4"
    _answer "$cb_id" ""

    local conf="${SERVER_DIR}/${server_name}.conf"
    if [[ ! -f "$conf" ]]; then
        _edit "$chat_id" "$msg_id" "❌ Server tidak ditemukan." "$(_kb_back_home)"
        return
    fi

    unset NAME IP DOMAIN; source "$conf"
    _load_tg_conf "$server_name"

    local count; count=$(_count_accounts "$IP")
    if [[ "$count" -ge "$TG_MAX_AKUN" ]]; then
        _edit "$chat_id" "$msg_id" "❌ <b>Server Penuh</b>

Server <b>${TG_SERVER_LABEL}</b> sudah penuh (${TG_MAX_AKUN} akun).
Silakan pilih server lain." "$(_kb_back_home)"
        return
    fi

    # Simpan state
    _state_set "$chat_id" "STATE" "await_username"
    _state_set "$chat_id" "SERVER" "$server_name"
    _state_set "$chat_id" "TYPE" "buat"

    _edit "$chat_id" "$msg_id" "🔑 <b>Buat Akun SSH</b>
Server: <b>${TG_SERVER_LABEL}</b>

━━━━━━━━━━━━━━━━━━━
Ketik username yang kamu inginkan 👇
<i>(Hanya huruf kecil, angka, minimal 3 karakter)</i>" "$(_kb_back_home)"

    _send "$chat_id" "👤 Masukkan username:"
}

# ── Trial SSH: tampil list server ──
_cb_trial_ssh() {
    local chat_id="$1" cb_id="$2" msg_id="$3" page="${4:-0}"
    _answer "$cb_id" ""
    local servers; servers=$(_get_server_list)
    if [[ -z "$servers" ]]; then
        _edit "$chat_id" "$msg_id" "❌ Belum ada server yang tersedia." "$(_kb_back_home)"
        return
    fi
    _edit "$chat_id" "$msg_id" \
        "$(_text_server_list "SSH TRIAL")" \
        "$(_kb_server_list "dotrial_ssh" "$page")"
}

# ── Pilih server trial → langsung buat ──
_already_trial_today() {
    local uid="$1"
    local f="${TRIAL_DIR}/${uid}.used"
    [[ -f "$f" ]] && [[ "$(cat "$f")" == "$(date +"%Y-%m-%d")" ]]
}

_cb_dotrial_ssh_server() {
    local chat_id="$1" cb_id="$2" msg_id="$3" server_name="$4"
    _answer "$cb_id" "⏳ Membuat akun trial..."

    if _already_trial_today "$chat_id"; then
        _edit "$chat_id" "$msg_id" "❌ <b>Sudah Trial Hari Ini</b>

Trial hanya bisa digunakan <b>1x per hari</b>.
Coba lagi besok! 😊" "$(_kb_back_home)"
        return
    fi

    local conf="${SERVER_DIR}/${server_name}.conf"
    [[ ! -f "$conf" ]] && { _edit "$chat_id" "$msg_id" "❌ Server tidak ditemukan." "$(_kb_back_home)"; return; }

    unset NAME IP DOMAIN PORT USER PASS; source "$conf"
    _load_tg_conf "$server_name"
    local domain="${DOMAIN:-$IP}"
    local local_ip; local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null)

    local count; count=$(_count_accounts "$IP")
    if [[ "$count" -ge "$TG_MAX_AKUN" ]]; then
        _edit "$chat_id" "$msg_id" "❌ Server penuh. Pilih server lain." "$(_kb_back_home)"
        return
    fi

    local suffix; suffix=$(tr -dc 'a-z0-9' </dev/urandom | head -c 5)
    local username="trial${suffix}"
    local password; password=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 8)
    local now_ts exp_ts exp_display exp_date
    now_ts=$(date +%s); exp_ts=$(( now_ts + 1800 ))
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
        result=$(sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no \
            -o ConnectTimeout=10 -o BatchMode=no \
            -p "$PORT" "${USER}@${IP}" \
            "zv-agent add $username $password $TG_LIMIT_IP 1" 2>/dev/null)
        [[ "$result" != ADD-OK* ]] && {
            _edit "$chat_id" "$msg_id" "❌ Gagal membuat akun. Coba lagi nanti." "$(_kb_back_home)"
            return
        }
    fi

    date +"%Y-%m-%d" > "${TRIAL_DIR}/${chat_id}.used"
    _log "TRIAL: $chat_id server=$server_name user=$username"
    _send_akun_info "$chat_id" "$msg_id" "TRIAL" "$username" "$password" "$domain" "$exp_display" "${TG_LIMIT_IP}" "${TG_SERVER_LABEL}" "0" "0"
}

# ── Kirim info akun (buat & trial) ──
_send_akun_info() {
    local chat_id="$1" msg_id="$2" type="$3"
    local username="$4" password="$5" domain="$6"
    local expired_display="$7" limit="$8" server_label="$9"
    local days="${10}" total_harga="${11}"

    local header
    [[ "$type" == "TRIAL" ]] && header="🌟 TRIAL SSH PREMIUM 🌟" || header="🌟 AKUN SSH PREMIUM 🌟"

    local extra=""
    if [[ "$type" == "BUAT" ]]; then
        extra="
⏳ Masa Aktif  : ${days} hari
💰 Total Harga : Rp${total_harga}"
    fi

    _edit "$chat_id" "$msg_id" "${header}

💠 <b>Informasi Akun</b>
━━━━━━━━━━━━━━━━━━━
Username : <code>${username}</code>
Password : <code>${password}</code>
Host     : <code>${domain}</code>
Server   : ${server_label}${extra}
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
⌛ Expired  : ${expired_display}
🔢 Limit    : ${limit} perangkat
⚠️ Dilarang share akun!" "$(_kb_back_home)"
}

# ============================================================
# Handler teks (multi-step input buat akun)
# ============================================================
_handle_text_input() {
    local chat_id="$1" text="$2"

    local state; state=$(_state_get "$chat_id" "STATE")
    [[ -z "$state" ]] && return 1  # bukan dalam proses input

    case "$state" in
        await_username)
            # Validasi username
            if [[ ! "$text" =~ ^[a-z0-9]{3,20}$ ]]; then
                _send "$chat_id" "❌ Username tidak valid!
Hanya huruf kecil & angka, 3-20 karakter.

👤 Masukkan username:"
                return 0
            fi

            local server_name; server_name=$(_state_get "$chat_id" "SERVER")
            local server_ip=""
            for conf in "$SERVER_DIR"/*.conf; do
                [[ -f "$conf" && "$conf" != *.tg.conf ]] || continue
                unset NAME IP; source "$conf"
                [[ "$NAME" == "$server_name" ]] && { server_ip="$IP"; break; }
            done

            if _username_exists "$server_ip" "$text"; then
                _send "$chat_id" "❌ Username <b>${text}</b> sudah digunakan!
Pilih username lain.

👤 Masukkan username:"
                return 0
            fi

            _state_set "$chat_id" "USERNAME" "$text"
            _state_set "$chat_id" "STATE" "await_password"
            _send "$chat_id" "🔑 Masukkan password:"
            ;;

        await_password)
            if [[ ${#text} -lt 4 ]]; then
                _send "$chat_id" "❌ Password minimal 4 karakter!

🔑 Masukkan password:"
                return 0
            fi
            _state_set "$chat_id" "PASSWORD" "$text"
            _state_set "$chat_id" "STATE" "await_days"
            _send "$chat_id" "⏳ Masukkan masa aktif (hari):
<i>Contoh: 1, 7, 30</i>"
            ;;

        await_days)
            if [[ ! "$text" =~ ^[0-9]+$ ]] || [[ "$text" -lt 1 ]] || [[ "$text" -gt 365 ]]; then
                _send "$chat_id" "❌ Masa aktif tidak valid! (1-365 hari)

⏳ Masukkan masa aktif (hari):"
                return 0
            fi

            local server_name; server_name=$(_state_get "$chat_id" "SERVER")
            local username; username=$(_state_get "$chat_id" "USERNAME")
            local password; password=$(_state_get "$chat_id" "PASSWORD")
            local days="$text"

            _load_tg_conf "$server_name"

            local total_harga=$(( TG_HARGA_HARI * days ))

            _state_set "$chat_id" "DAYS" "$days"
            _state_set "$chat_id" "STATE" "await_confirm"

            local harga_display
            [[ "$TG_HARGA_HARI" == "0" ]] && harga_display="Gratis" || harga_display="Rp${TG_HARGA_HARI}/hari"

            _send "$chat_id" "📋 <b>Konfirmasi Pesanan</b>
━━━━━━━━━━━━━━━━━━━
🌐 Server    : ${TG_SERVER_LABEL}
👤 Username  : <code>${username}</code>
🔑 Password  : <code>${password}</code>
📅 Masa Aktif: ${days} hari
💰 Harga     : ${harga_display}
💸 Total     : Rp${total_harga}
━━━━━━━━━━━━━━━━━━━
Lanjutkan pembelian?" "$(_kb_konfirmasi "konfirm_buat_ssh")"
            ;;
    esac
    return 0
}

# ── Konfirmasi buat akun ──
_cb_konfirm_buat_ssh() {
    local chat_id="$1" cb_id="$2" msg_id="$3"

    local state; state=$(_state_get "$chat_id" "STATE")
    if [[ "$state" != "await_confirm" ]]; then
        _answer "$cb_id" "⚠️ Sesi sudah expired, mulai ulang"
        _edit "$chat_id" "$msg_id" "⚠️ Sesi habis. Silakan mulai ulang." "$(_kb_back_home)"
        _state_clear "$chat_id"
        return
    fi

    _answer "$cb_id" "⏳ Membuat akun..."

    local server_name; server_name=$(_state_get "$chat_id" "SERVER")
    local username; username=$(_state_get "$chat_id" "USERNAME")
    local password; password=$(_state_get "$chat_id" "PASSWORD")
    local days; days=$(_state_get "$chat_id" "DAYS")

    local conf="${SERVER_DIR}/${server_name}.conf"
    unset NAME IP DOMAIN PORT USER PASS; source "$conf"
    _load_tg_conf "$server_name"

    local domain="${DOMAIN:-$IP}"
    local local_ip; local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null)
    local exp_date; exp_date=$(date -d "+${days} days" +"%Y-%m-%d")
    local exp_display="${exp_date}"
    local total_harga=$(( TG_HARGA_HARI * days ))

    if [[ "$IP" == "$local_ip" ]]; then
        useradd -e "$exp_date" -s /bin/false -M "$username" &>/dev/null
        echo "$username:$password" | chpasswd &>/dev/null
        mkdir -p "$ACCOUNT_DIR"
        cat > "${ACCOUNT_DIR}/${username}.conf" <<EOF
USERNAME=$username
PASSWORD=$password
LIMIT=${TG_LIMIT_IP}
EXPIRED=$exp_date
CREATED=$(date +"%Y-%m-%d")
IS_TRIAL=0
TG_USER_ID=$chat_id
EOF
    else
        local result
        result=$(sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no \
            -o ConnectTimeout=10 -o BatchMode=no \
            -p "$PORT" "${USER}@${IP}" \
            "zv-agent add $username $password $TG_LIMIT_IP $days" 2>/dev/null)
        if [[ "$result" != ADD-OK* ]]; then
            _edit "$chat_id" "$msg_id" "❌ Gagal membuat akun. Coba lagi nanti." "$(_kb_back_home)"
            _state_clear "$chat_id"
            return
        fi
    fi

    _state_clear "$chat_id"
    _log "BUAT: $chat_id server=$server_name user=$username days=$days"
    _send_akun_info "$chat_id" "$msg_id" "BUAT" "$username" "$password" "$domain" \
        "$exp_display" "${TG_LIMIT_IP}" "${TG_SERVER_LABEL}" "$days" "$total_harga"
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
        local chat_id first_name text
        IFS='|' read -r _ chat_id first_name text <<< "$parsed"
        local cmd; cmd=$(echo "$text" | awk '{print $1}' | cut -d'@' -f1 | tr '[:upper:]' '[:lower:]')
        _log "MSG: $chat_id text=${text:0:30}"

        if [[ "$cmd" == "/start" ]]; then
            _handle_start "$chat_id" "$first_name"
        else
            # Cek apakah sedang dalam proses input
            _handle_text_input "$chat_id" "$text" || \
                _send "$chat_id" "Ketuk /start untuk membuka menu 👇"
        fi

    elif [[ "$kind" == "CB" ]]; then
        local cb_id chat_id msg_id first_name data
        IFS='|' read -r _ cb_id chat_id msg_id first_name data <<< "$parsed"
        _log "CB: $chat_id data=$data"

        case "$data" in
            home)             _cb_home          "$chat_id" "$cb_id" "$msg_id" "$first_name" ;;
            m_buat)           _cb_menu_buat     "$chat_id" "$cb_id" "$msg_id" ;;
            m_trial)          _cb_menu_trial    "$chat_id" "$cb_id" "$msg_id" ;;
            proto_na)         _cb_proto_na      "$cb_id" ;;
            buat_ssh)         _cb_buat_ssh      "$chat_id" "$cb_id" "$msg_id" ;;
            trial_ssh)        _cb_trial_ssh     "$chat_id" "$cb_id" "$msg_id" ;;
            konfirm_buat_ssh_confirm)
                              _cb_konfirm_buat_ssh "$chat_id" "$cb_id" "$msg_id" ;;
            dobuat_ssh_page_*)
                local page="${data#dobuat_ssh_page_}"
                _cb_buat_ssh "$chat_id" "$cb_id" "$msg_id" "$page" ;;
            dobuat_ssh_*)
                local sname="${data#dobuat_ssh_}"
                _cb_dobuat_ssh_server "$chat_id" "$cb_id" "$msg_id" "$sname" ;;
            dotrial_ssh_page_*)
                local page="${data#dotrial_ssh_page_}"
                _cb_trial_ssh "$chat_id" "$cb_id" "$msg_id" "$page" ;;
            dotrial_ssh_*)
                local sname="${data#dotrial_ssh_}"
                _cb_dotrial_ssh_server "$chat_id" "$cb_id" "$msg_id" "$sname" ;;
            *)
                _answer "$cb_id" "❓" ;;
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
