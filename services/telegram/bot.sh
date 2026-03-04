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

# Format angka: 100000 → 100.000
_fmt() {
    python3 -c "
n=int('${1}'.strip() or 0)
s='{:,}'.format(n).replace(',','.')
print(s)
" 2>/dev/null || echo "${1}"
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
# Saldo — file terpisah, isi angka saja
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
# HTTP helpers
# ============================================================
_jstr() { python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$1" 2>/dev/null; }

_send() {
    local body="{\"chat_id\":\"${1}\",\"text\":$(_jstr "$2"),\"parse_mode\":\"HTML\""
    [[ -n "$3" ]] && body="${body},\"reply_markup\":{\"inline_keyboard\":${3}}"
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -H "Content-Type: application/json" -d "${body}}" --max-time 10 &>/dev/null
}

_edit() {
    local body="{\"chat_id\":\"${1}\",\"message_id\":\"${2}\",\"text\":$(_jstr "$3"),\"parse_mode\":\"HTML\""
    [[ -n "$4" ]] && body="${body},\"reply_markup\":{\"inline_keyboard\":${4}}"
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/editMessageText" \
        -H "Content-Type: application/json" -d "${body}}" --max-time 10 &>/dev/null
}

_answer() {
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/answerCallbackQuery" \
        -d "callback_query_id=${1}" --data-urlencode "text=${2}" --max-time 5 &>/dev/null
}

# ============================================================
# Server helpers
# ============================================================
_load_tg_conf() {
    TG_SERVER_LABEL="$1"; TG_HARGA_HARI="0"; TG_HARGA_BULAN="0"
    TG_QUOTA="Unlimited"; TG_LIMIT_IP="2"; TG_MAX_AKUN="500"
    [[ -f "${SERVER_DIR}/${1}.tg.conf" ]] && source "${SERVER_DIR}/${1}.tg.conf"
}

_count_accounts() {
    local ip="$1" local_ip count=0
    local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null)
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
    echo "$count"
}

_get_server_list() {
    for conf in "$SERVER_DIR"/*.conf; do
        [[ -f "$conf" && "$conf" != *.tg.conf ]] || continue
        unset NAME IP DOMAIN; source "$conf"
        [[ -n "$NAME" ]] && echo "${NAME}|${DOMAIN:-$IP}|${IP}"
    done
}

# ============================================================
# Keyboards
# ============================================================
_kb_home() {
    echo '[[{"text":"⚡ Buat Akun","callback_data":"m_buat"},{"text":"🎁 Coba Gratis","callback_data":"m_trial"}],[{"text":"📋 Akun Saya","callback_data":"m_akun"},{"text":"🔄 Perpanjang","callback_data":"m_perpanjang"}]]'
}
_kb_proto_buat() {
    echo '[[{"text":"SSH","callback_data":"p_buat_ssh"},{"text":"↩ Kembali","callback_data":"home"}]]'
}
_kb_proto_trial() {
    echo '[[{"text":"SSH","callback_data":"p_trial_ssh"},{"text":"↩ Kembali","callback_data":"home"}]]'
}
_kb_server_list() {
    local prefix="$1" page="${2:-0}" per_page=6
    local start=$(( page * per_page )) all=()
    while IFS= read -r line; do [[ -n "$line" ]] && all+=("$line"); done < <(_get_server_list)
    local total=${#all[@]} rows='[' count=0 i=$start pair=""

    while [[ $i -lt $total && $count -lt $per_page ]]; do
        IFS='|' read -r name domain ip <<< "${all[$i]}"
        _load_tg_conf "$name"
        local btn="{\"text\":\"${TG_SERVER_LABEL}\",\"callback_data\":\"${prefix}_${name}\"}"
        if [[ $(( count % 2 )) -eq 0 ]]; then
            pair="$btn"
        else
            [[ $count -eq 1 ]] && rows="${rows}[${pair},${btn}]" || rows="${rows},[${pair},${btn}]"
            pair=""
        fi
        i=$(( i + 1 )); count=$(( count + 1 ))
    done
    [[ -n "$pair" ]] && { [[ $count -eq 1 ]] && rows="${rows}[${pair}]" || rows="${rows},[${pair}]"; }

    local nav=""
    [[ $page -gt 0 ]] && nav="{\"text\":\"← Prev\",\"callback_data\":\"${prefix}_pg_$(( page-1 ))\"}"
    if [[ $(( start + per_page )) -lt $total ]]; then
        local nx="{\"text\":\"Next →\",\"callback_data\":\"${prefix}_pg_$(( page+1 ))\"}"
        [[ -n "$nav" ]] && nav="${nav},${nx}" || nav="$nx"
    fi
    [[ -n "$nav" ]] && rows="${rows},[${nav}]"
    rows="${rows},[{\"text\":\"↩ Kembali\",\"callback_data\":\"home\"}]]"
    echo "$rows"
}
_kb_home_btn() { echo '[[{"text":"🏠 Menu Utama","callback_data":"home"}]]'; }
_kb_confirm() {
    echo "[[{\"text\":\"✅ Konfirmasi\",\"callback_data\":\"${1}_ok\"},{\"text\":\"❌ Batal\",\"callback_data\":\"home\"}]]"
}

# ============================================================
# Teks
# ============================================================
_text_home() {
    local sc=0
    for conf in "$SERVER_DIR"/*.conf; do [[ -f "$conf" && "$conf" != *.tg.conf ]] && sc=$(( sc+1 )); done
    local saldo; saldo=$(_saldo_get "$2")
    cat <<EOF
⚡ <b>ZV-Manager SSH Tunnel</b>
━━━━━━━━━━━━━━━━━━━
🖥️ Server   : ${sc} server
🆔 User ID  : <code>${2}</code>
💰 Saldo    : Rp$(_fmt "$saldo")
━━━━━━━━━━━━━━━━━━━
🔹 SSH Tunnel (OpenSSH + Dropbear)
🔹 WebSocket WS / WSS
🔹 UDP Custom
🔹 Support Bug Host / SNI
━━━━━━━━━━━━━━━━━━━
Halo, ${1}! Pilih menu 👇
EOF
}

_text_server_list() {
    local title="$1" out="<b>${title}</b>\n\n" found=false
    while IFS='|' read -r name domain ip; do
        [[ -z "$name" ]] && continue; found=true
        _load_tg_conf "$name"
        local count; count=$(_count_accounts "$ip")
        local hh hb
        [[ "$TG_HARGA_HARI" == "0" ]]  && hh="Hubungi admin" || hh="Rp$(_fmt "$TG_HARGA_HARI")"
        [[ "$TG_HARGA_BULAN" == "0" ]] && hb="Hubungi admin" || hb="Rp$(_fmt "$TG_HARGA_BULAN")"
        out+="🌐 <b>${TG_SERVER_LABEL}</b>
💰 Harga/hari  : ${hh}
📅 Harga/30hr  : ${hb}
📊 Quota       : ${TG_QUOTA}
🔢 Limit IP    : ${TG_LIMIT_IP} IP/akun
👥 Total Akun  : ${count}/${TG_MAX_AKUN}

"
    done < <(_get_server_list)
    $found || out+="❌ Belum ada server.\n\n"
    out+="Pilih server:"
    echo -e "$out"
}

# ============================================================
# Kirim info akun — tanpa tombol apapun
# ============================================================
_send_akun() {
    local chat_id="$1" type="$2" username="$3" password="$4" domain="$5"
    local exp_display="$6" limit="$7" server_label="$8" days="${9}" total_harga="${10}"
    local header extra=""
    [[ "$type" == "TRIAL" ]] && header="🎁 Akun Trial SSH — 30 Menit" || header="✅ Akun SSH Premium"
    [[ "$type" == "BELI" ]] && extra="
Masa Aktif  : ${days} hari
Total Bayar : Rp$(_fmt "$total_harga")"

    _send "$chat_id" "<b>${header}</b>
━━━━━━━━━━━━━━━━━━━
Username : <code>${username}</code>
Password : <code>${password}</code>
Host     : <code>${domain}</code>
Server   : ${server_label}${extra}
Expired  : ${exp_display}
━━━━━━━━━━━━━━━━━━━
<b>Port Tersedia</b>

OpenSSH  : 22, 500, 40000
Dropbear : 143, 109
BadVPN   : 7300
WS / WSS / UDP : Lihat format bawah
━━━━━━━━━━━━━━━━━━━
<b>Format Koneksi</b>

WS  : <code>${domain}:80@${username}:${password}</code>
WSS : <code>${domain}:443@${username}:${password}</code>
UDP : <code>${domain}@1-65535@${username}:${password}</code>
━━━━━━━━━━━━━━━━━━━
Limit : ${limit} perangkat"
}

# ============================================================
# Akun Saya
# ============================================================
_cb_akun_saya() {
    local chat_id="$1" cb_id="$2" msg_id="$3"
    _answer "$cb_id" ""

    local now_ts; now_ts=$(date +%s)
    local now_date; now_date=$(date +"%Y-%m-%d")
    local found=false
    local out="📋 <b>Akun Kamu</b>\n━━━━━━━━━━━━━━━━━━━\n"

    # Cari akun lokal berdasarkan TG_USER_ID
    for conf in "$ACCOUNT_DIR"/*.conf; do
        [[ -f "$conf" ]] || continue
        local tg_uid; tg_uid=$(grep "^TG_USER_ID=" "$conf" | cut -d= -f2)
        local tg_uid_clean; tg_uid_clean=$(echo "$tg_uid" | tr -d "[:space:]")
        [[ "$tg_uid_clean" != "$chat_id" ]] && continue

        local uname pass exp_ts exp_date limit is_trial server domain
        uname=$(grep    "^USERNAME="   "$conf" | cut -d= -f2)
        pass=$(grep     "^PASSWORD="   "$conf" | cut -d= -f2)
        exp_ts=$(grep   "^EXPIRED_TS=" "$conf" | cut -d= -f2)
        exp_date=$(grep "^EXPIRED="    "$conf" | cut -d= -f2)
        limit=$(grep    "^LIMIT="      "$conf" | cut -d= -f2)
        is_trial=$(grep "^IS_TRIAL="   "$conf" | cut -d= -f2)
        server=$(grep   "^SERVER="     "$conf" | cut -d= -f2)
        domain=$(grep   "^DOMAIN="     "$conf" | cut -d= -f2)

        [[ -z "$uname" ]] && continue

        # Hitung sisa waktu
        local status sisa_label
        if [[ -n "$exp_ts" && "$exp_ts" =~ ^[0-9]+$ ]]; then
            local sisa_detik=$(( exp_ts - now_ts ))
            if [[ $sisa_detik -le 0 ]]; then
                status="❌ Expired"
                sisa_label="Sudah habis"
            elif [[ $sisa_detik -lt 3600 ]]; then
                status="⚠️ Aktif"
                sisa_label="Kurang dari 1 jam"
            elif [[ $sisa_detik -lt 86400 ]]; then
                local sisa_jam=$(( sisa_detik / 3600 ))
                status="⚠️ Aktif"
                sisa_label="${sisa_jam} jam lagi"
            else
                local sisa_hari=$(( sisa_detik / 86400 ))
                status="✅ Aktif"
                sisa_label="${sisa_hari} hari lagi"
            fi
        else
            # Fallback ke tanggal
            if [[ "$exp_date" < "$now_date" ]]; then
                status="❌ Expired"; sisa_label="Sudah habis"
            else
                status="✅ Aktif"; sisa_label="-"
            fi
        fi

        local tipe; [[ "$is_trial" == "1" ]] && tipe="Trial" || tipe="Premium"
        local exp_display
        if [[ -n "$exp_ts" && "$exp_ts" =~ ^[0-9]+$ ]]; then
            exp_display=$(TZ="Asia/Jakarta" date -d "@${exp_ts}" +"%d %b %Y %H:%M WIB" 2>/dev/null || echo "$exp_date")
        else
            exp_display="$exp_date"
        fi

        found=true
        out+="
👤 <b>${uname}</b> <i>(${tipe})</i>
🌐 Host    : <code>${domain}</code>
🔑 Pass    : <code>${pass}</code>
⏳ Expired : ${exp_display}
📊 Status  : ${status} · ${sisa_label}
━━━━━━━━━━━━━━━━━━━"
    done

    if ! $found; then
        out+="\nKamu belum punya akun aktif.\n\nTekan <b>Buat Akun</b> untuk membeli."
    fi

    _edit "$chat_id" "$msg_id" "$(echo -e "$out")" "$(_kb_home_btn)"
}


# ============================================================
# Perpanjang Akun
# ============================================================

# Tampil list akun user untuk diperpanjang
_cb_perpanjang() {
    local chat_id="$1" cb_id="$2" msg_id="$3"
    _answer "$cb_id" ""

    local akun_list=()
    for conf in "$ACCOUNT_DIR"/*.conf; do
        [[ -f "$conf" ]] || continue
        local tg_uid; tg_uid=$(grep "^TG_USER_ID=" "$conf" | cut -d= -f2 | tr -d "[:space:]")
        [[ "$tg_uid" != "$chat_id" ]] && continue
        local uname is_trial
        uname=$(grep    "^USERNAME=" "$conf" | cut -d= -f2 | tr -d "[:space:]")
        is_trial=$(grep "^IS_TRIAL=" "$conf" | cut -d= -f2 | tr -d "[:space:]")
        [[ "$is_trial" == "1" ]] && continue
        [[ -n "$uname" ]] && akun_list+=("$uname")
    done

    if [[ ${#akun_list[@]} -eq 0 ]]; then
        _edit "$chat_id" "$msg_id" "📋 <b>Perpanjang Akun</b>

Kamu belum punya akun premium yang bisa diperpanjang." "$(_kb_home_btn)"
        return
    fi

    # Build JSON keyboard manual — hindari python3 untuk portabilitas
    local kb='['
    local i=0
    local total=${#akun_list[@]}
    while [[ $i -lt $total ]]; do
        local uname1="${akun_list[$i]}"
        local row="[{\"text\":\"${uname1}\",\"callback_data\":\"renew_${uname1}\"}"
        if [[ $(( i + 1 )) -lt $total ]]; then
            local uname2="${akun_list[$(( i + 1 ))]}"
            row="${row},{\"text\":\"${uname2}\",\"callback_data\":\"renew_${uname2}\"}"
            i=$(( i + 2 ))
        else
            i=$(( i + 1 ))
        fi
        row="${row}]"
        [[ "$kb" == "[" ]] && kb="${kb}${row}" || kb="${kb},${row}"
    done
    kb="${kb},[{\"text\":\"\u21a9 Kembali\",\"callback_data\":\"home\"}]]"

    _edit "$chat_id" "$msg_id" "🔄 <b>Perpanjang Akun</b>

Pilih akun yang ingin diperpanjang:" "$kb"
}
_cb_renew_akun() {
    local chat_id="$1" cb_id="$2" msg_id="$3" username="$4"
    _answer "$cb_id" ""

    # Cari conf akun ini
    local conf="${ACCOUNT_DIR}/${username}.conf"
    [[ ! -f "$conf" ]] && { _edit "$chat_id" "$msg_id" "❌ Akun tidak ditemukan." "$(_kb_home_btn)"; return; }

    # Trim whitespace agar perbandingan tidak gagal diam-diam
    local tg_uid; tg_uid=$(grep "^TG_USER_ID=" "$conf" | cut -d= -f2 | tr -d "[:space:]")
    local chat_id_clean; chat_id_clean=$(echo "$chat_id" | tr -d "[:space:]")
    [[ "$tg_uid" != "$chat_id_clean" ]] && {
        _edit "$chat_id" "$msg_id" "❌ Akun ini bukan milikmu." "$(_kb_home_btn)"
        return
    }

    local exp_ts exp_date exp_display sname
    exp_ts=$(grep "^EXPIRED_TS=" "$conf" | cut -d= -f2 | tr -d "[:space:]")
    exp_date=$(grep "^EXPIRED="    "$conf" | cut -d= -f2 | tr -d "[:space:]")
    sname=$(grep   "^SERVER="     "$conf" | cut -d= -f2 | tr -d "[:space:]")

    _load_tg_conf "$sname"
    local harga=$(( 10#${TG_HARGA_HARI} ))
    local hh; [[ $harga -eq 0 ]] && hh="Gratis" || hh="Rp$(_fmt "$harga")/hari"

    if [[ -n "$exp_ts" && "$exp_ts" =~ ^[0-9]+$ ]]; then
        exp_display=$(TZ="Asia/Jakarta" date -d "@${exp_ts}" +"%d %b %Y %H:%M WIB" 2>/dev/null || echo "$exp_date")
    else
        exp_display="$exp_date"
    fi

    _state_clear "$chat_id"
    _state_set "$chat_id" "STATE"    "renew_days"
    _state_set "$chat_id" "USERNAME" "$username"
    _state_set "$chat_id" "SERVER"   "$sname"

    _edit "$chat_id" "$msg_id" "🔄 <b>Perpanjang Akun</b>
━━━━━━━━━━━━━━━━━━━
👤 Username : <code>${username}</code>
🌐 Server   : ${TG_SERVER_LABEL}
⏳ Expired  : ${exp_display}
💰 Harga    : ${hh}
━━━━━━━━━━━━━━━━━━━
Berapa hari ingin diperpanjang? (1-365)" '[[{"text":"↩ Kembali","callback_data":"m_perpanjang"}]]'
}

# Konfirmasi perpanjang
_cb_konfirm_renew() {
    local chat_id="$1" cb_id="$2" msg_id="$3"
    [[ "$(_state_get "$chat_id" "STATE")" != "renew_confirm" ]] && {
        _answer "$cb_id" "⚠️ Sesi habis, mulai ulang"
        _state_clear "$chat_id"; return
    }
    _answer "$cb_id" "⏳ Memperpanjang akun..."

    local username sname days
    username=$(_state_get "$chat_id" "USERNAME")
    sname=$(_state_get "$chat_id" "SERVER")
    days=$(_state_get "$chat_id" "DAYS")

    _load_tg_conf "$sname"
    local harga=$(( 10#${TG_HARGA_HARI} ))
    local total=$(( harga * days ))

    # Potong saldo
    if [[ $harga -gt 0 && $total -gt 0 ]]; then
        _saldo_deduct "$chat_id" "$total" || {
            _edit "$chat_id" "$msg_id" "❌ Saldo tidak cukup. Hubungi admin untuk top up." ""
            _state_clear "$chat_id"; return
        }
    fi

    local conf="${ACCOUNT_DIR}/${username}.conf"
    local old_exp_ts; old_exp_ts=$(grep "^EXPIRED_TS=" "$conf" | cut -d= -f2)
    local now_ts; now_ts=$(date +%s)
    local base_ts
    # Kalau masih aktif, perpanjang dari expired lama. Kalau sudah habis, dari sekarang
    if [[ -n "$old_exp_ts" && "$old_exp_ts" =~ ^[0-9]+$ && $old_exp_ts -gt $now_ts ]]; then
        base_ts=$old_exp_ts
    else
        base_ts=$now_ts
    fi

    local new_exp_ts=$(( base_ts + days * 86400 ))
    local new_exp_date; new_exp_date=$(date -d "@${new_exp_ts}" +"%Y-%m-%d")
    local new_exp_display; new_exp_display=$(TZ="Asia/Jakarta" date -d "@${new_exp_ts}" +"%d %b %Y %H:%M WIB")

    local local_ip; local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null)
    local domain; domain=$(grep "^DOMAIN=" "$conf" | cut -d= -f2)

    # Update conf lokal
    local tmp; tmp=$(mktemp)
    grep -v "^EXPIRED=\|^EXPIRED_TS=" "$conf" > "$tmp"
    echo "EXPIRED=$new_exp_date"    >> "$tmp"
    echo "EXPIRED_TS=$new_exp_ts"   >> "$tmp"
    mv "$tmp" "$conf"

    # Update di sistem
    chage -E "$new_exp_date" "$username" &>/dev/null

    # Hapus notifikasi lama biar bisa kirim notif baru nanti
    rm -f "/etc/zv-manager/accounts/notified/${username}.notified"

    _state_clear "$chat_id"
    _log "RENEW: $chat_id user=$username days=$days total=$total"

    _edit "$chat_id" "$msg_id" "✅ Akun berhasil diperpanjang!" ""
    _send "$chat_id" "🔄 <b>Perpanjang Berhasil</b>
━━━━━━━━━━━━━━━━━━━
👤 Username  : <code>${username}</code>
📅 Tambah    : ${days} hari
⏳ Expired   : ${new_exp_display}
💸 Dibayar   : Rp$(_fmt "$total")
💰 Sisa Saldo: Rp$(_fmt "$(_saldo_get "$chat_id")")
━━━━━━━━━━━━━━━━━━━
Akun kamu sudah aktif sampai ${new_exp_display}!"
}


# ============================================================
# Broadcast (Admin Only)
# ============================================================
_is_admin() {
    local uid; uid=$(echo "$1" | tr -d "[:space:]")
    local admin; admin=$(echo "$TG_ADMIN_ID" | tr -d "[:space:]")
    [[ "$uid" == "$admin" ]]
}

_cb_broadcast() {
    local chat_id="$1" cb_id="$2" msg_id="$3"
    _is_admin "$chat_id" || { _answer "$cb_id" "❌ Akses ditolak"; return; }
    _answer "$cb_id" ""
    _state_clear "$chat_id"
    _state_set "$chat_id" "STATE" "broadcast_msg"
    _edit "$chat_id" "$msg_id" "📢 <b>Broadcast Pesan</b>

Ketik pesan yang akan dikirim ke semua user.
Bisa pakai format HTML: <code>&lt;b&gt;bold&lt;/b&gt;</code>, <code>&lt;i&gt;italic&lt;/i&gt;</code>

Ketik pesan:" '[[{"text":"❌ Batal","callback_data":"home"}]]'
}

_do_broadcast() {
    local chat_id="$1" text="$2"
    tg_load

    # Kumpulkan UID unik ke file
    local uid_file; uid_file=$(mktemp)
    for conf in "$ACCOUNT_DIR"/*.conf; do
        [[ -f "$conf" ]] || continue
        local uid; uid=$(grep "^TG_USER_ID=" "$conf" | cut -d= -f2 | tr -d "[:space:]")
        [[ -z "$uid" ]] && continue
        echo "$uid"
    done | sort -u > "$uid_file"

    local total; total=$(wc -l < "$uid_file" | tr -d "[:space:]")
    if [[ $total -eq 0 ]]; then
        rm -f "$uid_file"
        _send "$chat_id" "❌ Belum ada user terdaftar."
        return
    fi

    _send "$chat_id" "⏳ Mengirim ke ${total} user..."

    local ok=0 fail=0
    while IFS= read -r uid; do
        [[ -z "$uid" ]] && continue

        # Tulis JSON ke temp file — hindari quoting hell di bash
        local jfile; jfile=$(mktemp)
        python3 - "$uid" "$text" > "$jfile" << 'PYINLINE'
import json, sys
uid, text = sys.argv[1], sys.argv[2]
print(json.dumps({"chat_id": uid, "text": text, "parse_mode": "HTML"}))
PYINLINE

        local result
        result=$(curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage"             -H "Content-Type: application/json"             -d "@${jfile}"             --max-time 10 2>/dev/null)
        rm -f "$jfile"

        if echo "$result" | grep -q '"ok":true'; then
            ok=$(( ok + 1 ))
            _log "BROADCAST OK uid=$uid"
        else
            local err; err=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('description','?'))" 2>/dev/null)
            fail=$(( fail + 1 ))
            _log "BROADCAST FAIL uid=$uid err=${err}"
        fi
        sleep 0.1
    done < "$uid_file"
    rm -f "$uid_file"

    _log "BROADCAST DONE total=$total ok=$ok fail=$fail"
    _send "$chat_id" "📢 <b>Broadcast Selesai</b>
━━━━━━━━━━━━━━━━━━━
✅ Terkirim : ${ok} user
❌ Gagal    : ${fail} user
━━━━━━━━━━━━━━━━━━━
<i>Gagal biasanya karena user memblokir bot.</i>"
}


_kb_for_user() {
    local uid="$1"
    if _is_admin "$uid"; then
        echo '[[{"text":"⚡ Buat Akun","callback_data":"m_buat"},{"text":"🎁 Coba Gratis","callback_data":"m_trial"}],[{"text":"📋 Akun Saya","callback_data":"m_akun"},{"text":"🔄 Perpanjang","callback_data":"m_perpanjang"}],[{"text":"📢 Broadcast","callback_data":"m_broadcast"}]]'
    else
        echo "$(_kb_home)"
    fi
}

_handle_start() {
    _state_clear "$1"
    _send "$1" "$(_text_home "$2" "$1")" "$(_kb_for_user "$1")"
}


_cb_home() {
    _answer "$2" ""; _state_clear "$1"
    _edit "$1" "$3" "$(_text_home "$4" "$1")" "$(_kb_for_user "$1")"
}

_cb_menu_buat() {
    _answer "$2" ""
    _edit "$1" "$3" "⚡ <b>Buat Akun</b>

Pilih protokol:" "$(_kb_proto_buat)"
}

_cb_menu_trial() {
    _answer "$2" ""
    _edit "$1" "$3" "🎁 <b>Coba Gratis</b>

Pilih protokol:" "$(_kb_proto_trial)"
}

_cb_proto_buat_ssh() {
    local chat_id="$1" cb_id="$2" msg_id="$3" page="${4:-0}"
    _answer "$cb_id" ""
    [[ -z "$(_get_server_list)" ]] && { _edit "$chat_id" "$msg_id" "❌ Belum ada server." ""; return; }
    _edit "$chat_id" "$msg_id" "$(_text_server_list "Buat Akun SSH")" "$(_kb_server_list "s_buat" "$page")"
}

_cb_proto_trial_ssh() {
    local chat_id="$1" cb_id="$2" msg_id="$3" page="${4:-0}"
    _answer "$cb_id" ""
    [[ -z "$(_get_server_list)" ]] && { _edit "$chat_id" "$msg_id" "❌ Belum ada server." ""; return; }
    _edit "$chat_id" "$msg_id" "$(_text_server_list "Trial SSH Gratis")" "$(_kb_server_list "s_trial" "$page")"
}

# Pilih server buat → minta username, TANPA tombol
_cb_s_buat() {
    local chat_id="$1" cb_id="$2" sname="$4"
    local conf="${SERVER_DIR}/${sname}.conf"
    [[ ! -f "$conf" ]] && { _answer "$cb_id" "❌ Server tidak ditemukan"; return; }
    unset NAME IP DOMAIN; source "$conf"; _load_tg_conf "$sname"
    [[ $(_count_accounts "$IP") -ge $TG_MAX_AKUN ]] && { _answer "$cb_id" "❌ Server penuh!"; return; }

    _answer "$cb_id" ""
    _state_clear "$chat_id"
    _state_set "$chat_id" "STATE"  "await_user"
    _state_set "$chat_id" "SERVER" "$sname"

    # Kirim pesan baru TANPA tombol
    _send "$chat_id" "Server : <b>${TG_SERVER_LABEL}</b>

Ketik username yang kamu inginkan.
Hanya huruf kecil dan angka, minimal 3 karakter."
}

# Trial 24 jam per server
_already_trial() {
    local f="${TRIAL_DIR}/${1}_${2}.ts"
    [[ ! -f "$f" ]] && return 1
    local last; last=$(cat "$f" 2>/dev/null)
    [[ "$last" =~ ^[0-9]+$ ]] && [[ $(( $(date +%s) - last )) -lt 86400 ]]
}
_mark_trial() { date +%s > "${TRIAL_DIR}/${1}_${2}.ts"; }

_cb_s_trial() {
    local chat_id="$1" cb_id="$2" msg_id="$3" sname="$4"
    _answer "$cb_id" ""
    _already_trial "$chat_id" "$sname" && {
        _send "$chat_id" "⚠️ Kamu sudah trial di server ini dalam 24 jam terakhir.
Coba server lain atau tunggu 24 jam."
        return
    }
    local conf="${SERVER_DIR}/${sname}.conf"
    [[ ! -f "$conf" ]] && { _send "$chat_id" "❌ Server tidak ditemukan."; return; }
    unset NAME IP DOMAIN PORT USER PASS; source "$conf"
    _load_tg_conf "$sname"
    local domain="${DOMAIN:-$IP}"
    local local_ip; local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null)
    [[ $(_count_accounts "$IP") -ge $TG_MAX_AKUN ]] && {
        _send "$chat_id" "❌ Server <b>${TG_SERVER_LABEL}</b> penuh. Coba server lain."; return
    }
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
DOMAIN=$domain
EOF
    else
        local result
        result=$(sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
            -o BatchMode=no -p "$PORT" "${USER}@${IP}" \
            "zv-agent add $username $password $TG_LIMIT_IP 1" 2>/dev/null)
        [[ "$result" != ADD-OK* ]] && { _send "$chat_id" "❌ Gagal membuat akun."; return; }
    fi
    _mark_trial "$chat_id" "$sname"
    _log "TRIAL: $chat_id server=$sname user=$username"
    _send_akun "$chat_id" "TRIAL" "$username" "$password" "$domain" \
        "$exp_display" "${TG_LIMIT_IP}" "${TG_SERVER_LABEL}" "" ""
}

# ============================================================
# Multi-step: input buat akun
# ============================================================
_handle_input() {
    local chat_id="$1" text="$2"
    local state; state=$(_state_get "$chat_id" "STATE")
    [[ -z "$state" ]] && return 1

    case "$state" in
        broadcast_msg)
            _is_admin "$chat_id" || { _state_clear "$chat_id"; return 0; }
            _state_clear "$chat_id"
            _do_broadcast "$chat_id" "$text"
            return 0
            ;;
        await_user)
            if ! echo "$text" | grep -qE '^[a-z0-9]{3,20}$'; then
                _send "$chat_id" "❌ Username tidak valid. Huruf kecil dan angka, 3-20 karakter.

Ketik username:"; return 0
            fi
            id "$text" &>/dev/null && {
                _send "$chat_id" "❌ Username <b>${text}</b> sudah digunakan.

Ketik username lain:"; return 0
            }
            _state_set "$chat_id" "USERNAME" "$text"
            _state_set "$chat_id" "STATE" "await_pass"
            _send "$chat_id" "Ketik password (minimal 4 karakter):"
            ;;
        await_pass)
            [[ ${#text} -lt 4 ]] && {
                _send "$chat_id" "❌ Password minimal 4 karakter.

Ketik password:"; return 0
            }
            _state_set "$chat_id" "PASSWORD" "$text"
            _state_set "$chat_id" "STATE" "await_days"
            _send "$chat_id" "Berapa hari masa aktif? (1-365)"
            ;;
        renew_days)
            if ! echo "$text" | grep -qE '^[0-9]+$' || [[ $text -lt 1 || $text -gt 365 ]]; then
                _send "$chat_id" "❌ Masukkan angka antara 1 sampai 365.

Berapa hari perpanjang?"
                return 0
            fi
            local sname; sname=$(_state_get "$chat_id" "SERVER")
            local username; username=$(_state_get "$chat_id" "USERNAME")
            local days="$text"
            _load_tg_conf "$sname"
            local harga=$(( 10#${TG_HARGA_HARI} ))
            local total=$(( harga * days ))
            local saldo=$(( 10#$(_saldo_get "$chat_id") ))
            _state_set "$chat_id" "DAYS" "$days"
            _state_set "$chat_id" "STATE" "renew_confirm"
            local hh; [[ $harga -eq 0 ]] && hh="Gratis" || hh="Rp$(_fmt "$harga")/hari"
            if [[ $harga -gt 0 && $saldo -lt $total ]]; then
                _send "$chat_id" "📋 <b>Konfirmasi Perpanjang</b>
━━━━━━━━━━━━━━━━━━━
👤 Username  : <code>${username}</code>
📅 Tambah    : ${days} hari
💰 Harga     : ${hh}
💸 Total     : Rp$(_fmt "$total")
💳 Saldo     : Rp$(_fmt "$saldo")
❌ Kurang    : Rp$(_fmt "$(( total - saldo ))")
━━━━━━━━━━━━━━━━━━━
Saldo tidak cukup. Hubungi admin untuk top up."
                _state_clear "$chat_id"; return 0
            fi
            local saldo_line=""; [[ $harga -gt 0 ]] && saldo_line="
💳 Saldo     : Rp$(_fmt "$saldo")"
            _send "$chat_id" "📋 <b>Konfirmasi Perpanjang</b>
━━━━━━━━━━━━━━━━━━━
👤 Username  : <code>${username}</code>
🌐 Server    : ${TG_SERVER_LABEL}
📅 Tambah    : ${days} hari
💰 Harga     : ${hh}
💸 Total     : Rp$(_fmt "$total")${saldo_line}
━━━━━━━━━━━━━━━━━━━
Lanjutkan?" "$(_kb_confirm "konfirm_renew")"
            ;;
        await_days)
            if ! echo "$text" | grep -qE '^[0-9]+$' || [[ $text -lt 1 || $text -gt 365 ]]; then
                _send "$chat_id" "❌ Masukkan angka antara 1 sampai 365.

Berapa hari masa aktif?"; return 0
            fi

            local sname; sname=$(_state_get "$chat_id" "SERVER")
            local username; username=$(_state_get "$chat_id" "USERNAME")
            local password; password=$(_state_get "$chat_id" "PASSWORD")
            local days="$text"

            _load_tg_conf "$sname"
            local harga=$(( 10#${TG_HARGA_HARI} ))
            local total=$(( harga * days ))
            local saldo=$(( 10#$(_saldo_get "$chat_id") ))

            _state_set "$chat_id" "DAYS" "$days"
            _state_set "$chat_id" "STATE" "await_confirm"

            local hh
            [[ $harga -eq 0 ]] && hh="Gratis" || hh="Rp$(_fmt "$harga")/hari"

            # Saldo tidak cukup
            if [[ $harga -gt 0 && $saldo -lt $total ]]; then
                _send "$chat_id" "📋 <b>Konfirmasi Pesanan</b>
━━━━━━━━━━━━━━━━━━━
🌐 Server     : ${TG_SERVER_LABEL}
👤 Username   : <code>${username}</code>
🔑 Password   : <code>${password}</code>
📅 Masa Aktif : ${days} hari
💰 Harga      : ${hh}
💸 Total      : Rp$(_fmt "$total")
💳 Saldo kamu : Rp$(_fmt "$saldo")
❌ Kurang     : Rp$(_fmt "$(( total - saldo ))")
━━━━━━━━━━━━━━━━━━━
Saldo tidak cukup. Hubungi admin untuk top up."
                _state_clear "$chat_id"; return 0
            fi

            local saldo_line=""
            [[ $harga -gt 0 ]] && saldo_line="
💳 Saldo kamu : Rp$(_fmt "$saldo")"

            _send "$chat_id" "📋 <b>Konfirmasi Pesanan</b>
━━━━━━━━━━━━━━━━━━━
🌐 Server     : ${TG_SERVER_LABEL}
👤 Username   : <code>${username}</code>
🔑 Password   : <code>${password}</code>
📅 Masa Aktif : ${days} hari
💰 Harga      : ${hh}
💸 Total      : Rp$(_fmt "$total")${saldo_line}
━━━━━━━━━━━━━━━━━━━
Lanjutkan?" "$(_kb_confirm "konfirm")"
            ;;
    esac
    return 0
}

# Konfirmasi buat akun
_cb_konfirm() {
    local chat_id="$1" cb_id="$2" msg_id="$3"
    [[ "$(_state_get "$chat_id" "STATE")" != "await_confirm" ]] && {
        _answer "$cb_id" "⚠️ Sesi habis, mulai ulang"
        _state_clear "$chat_id"; return
    }
    _answer "$cb_id" "⏳ Membuat akun..."

    local sname username password days
    sname=$(_state_get "$chat_id" "SERVER")
    username=$(_state_get "$chat_id" "USERNAME")
    password=$(_state_get "$chat_id" "PASSWORD")
    days=$(_state_get "$chat_id" "DAYS")

    unset NAME IP DOMAIN PORT USER PASS
    source "${SERVER_DIR}/${sname}.conf"
    _load_tg_conf "$sname"

    local domain="${DOMAIN:-$IP}"
    local local_ip; local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null)
    local harga=$(( 10#${TG_HARGA_HARI} ))
    local total=$(( harga * days ))
    local now_ts exp_ts exp_display exp_date
    now_ts=$(date +%s); exp_ts=$(( now_ts + days * 86400 ))
    exp_display=$(TZ="Asia/Jakarta" date -d "@${exp_ts}" +"%d %b %Y %H:%M WIB")
    exp_date=$(date -d "@${exp_ts}" +"%Y-%m-%d")

    # Potong saldo
    if [[ $harga -gt 0 && $total -gt 0 ]]; then
        _saldo_deduct "$chat_id" "$total" || {
            _edit "$chat_id" "$msg_id" "❌ Saldo tidak cukup. Hubungi admin." "" 
            _state_clear "$chat_id"; return
        }
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
        result=$(sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
            -o BatchMode=no -p "$PORT" "${USER}@${IP}" \
            "zv-agent add $username $password $TG_LIMIT_IP $days" 2>/dev/null)
        if [[ "$result" != ADD-OK* ]]; then
            [[ $total -gt 0 ]] && {
                local cur=$(( 10#$(_saldo_get "$chat_id") ))
                _saldo_set "$chat_id" "$(( cur + total ))"
            }
            _edit "$chat_id" "$msg_id" "❌ Gagal membuat akun. Saldo dikembalikan." ""
            _state_clear "$chat_id"; return
        fi
    fi

    _state_clear "$chat_id"
    _log "BELI: $chat_id server=$sname user=$username days=$days total=$total"
    # Hapus inline keyboard dari pesan konfirmasi
    _edit "$chat_id" "$msg_id" "✅ Akun sedang dibuat..." ""
    _send_akun "$chat_id" "BELI" "$username" "$password" "$domain" \
        "$exp_display" "${TG_LIMIT_IP}" "${TG_SERVER_LABEL}" "$days" "$total"
}

# ============================================================
# Proses update
# ============================================================
_process_update() {
    local raw="$1" tmpf; tmpf=$(mktemp)
    python3 -c "
import sys, json
try:
    u = json.loads(sys.argv[1])
    if 'message' in u:
        m = u['message']
        lines = ['MSG',str(m['chat']['id']),m['from'].get('first_name','User'),m.get('text','')]
    elif 'callback_query' in u:
        cq = u['callback_query']
        lines = ['CB',str(cq['id']),str(cq['message']['chat']['id']),
                 str(cq['message']['message_id']),
                 cq['from'].get('first_name','User'),cq.get('data','')]
    else: sys.exit(0)
    [print(l) for l in lines]
except: pass
" "$raw" > "$tmpf" 2>/dev/null

    local kind; kind=$(sed -n '1p' "$tmpf")
    [[ -z "$kind" ]] && { rm -f "$tmpf"; return; }

    if [[ "$kind" == "MSG" ]]; then
        local chat_id fname text
        chat_id=$(sed -n '2p' "$tmpf"); fname=$(sed -n '3p' "$tmpf"); text=$(sed -n '4p' "$tmpf")
        rm -f "$tmpf"; _log "MSG $chat_id: ${text:0:40}"
        local cmd; cmd=$(echo "$text" | awk '{print $1}' | cut -d'@' -f1 | tr '[:upper:]' '[:lower:]')
        [[ "$cmd" == "/start" ]] && _handle_start "$chat_id" "$fname" || \
            { _handle_input "$chat_id" "$text" || _send "$chat_id" "Ketuk /start untuk membuka menu."; }

    elif [[ "$kind" == "CB" ]]; then
        local cb_id chat_id msg_id fname data
        cb_id=$(sed -n '2p' "$tmpf"); chat_id=$(sed -n '3p' "$tmpf")
        msg_id=$(sed -n '4p' "$tmpf"); fname=$(sed -n '5p' "$tmpf"); data=$(sed -n '6p' "$tmpf")
        rm -f "$tmpf"; _log "CB $chat_id: $data"

        case "$data" in
            home)          _cb_home           "$chat_id" "$cb_id" "$msg_id" "$fname" ;;
            m_buat)        _cb_menu_buat       "$chat_id" "$cb_id" "$msg_id" ;;
            m_akun)        _cb_akun_saya       "$chat_id" "$cb_id" "$msg_id" ;;
            m_perpanjang)  _cb_perpanjang      "$chat_id" "$cb_id" "$msg_id" ;;
            m_broadcast)   _cb_broadcast       "$chat_id" "$cb_id" "$msg_id" ;;
            konfirm_renew_ok) _cb_konfirm_renew "$chat_id" "$cb_id" "$msg_id" ;;
            renew_*)       _cb_renew_akun      "$chat_id" "$cb_id" "$msg_id" "${data#renew_}" ;;
            m_trial)       _cb_menu_trial      "$chat_id" "$cb_id" "$msg_id" ;;
            p_buat_ssh)    _cb_proto_buat_ssh  "$chat_id" "$cb_id" "$msg_id" ;;
            p_trial_ssh)   _cb_proto_trial_ssh "$chat_id" "$cb_id" "$msg_id" ;;
            konfirm_ok)    _cb_konfirm         "$chat_id" "$cb_id" "$msg_id" ;;
            s_buat_pg_*)   _cb_proto_buat_ssh  "$chat_id" "$cb_id" "$msg_id" "${data#s_buat_pg_}" ;;
            s_trial_pg_*)  _cb_proto_trial_ssh "$chat_id" "$cb_id" "$msg_id" "${data#s_trial_pg_}" ;;
            s_buat_*)      _cb_s_buat          "$chat_id" "$cb_id" "$msg_id" "${data#s_buat_}" ;;
            s_trial_*)     _cb_s_trial         "$chat_id" "$cb_id" "$msg_id" "${data#s_trial_}" ;;
            *)             _answer "$cb_id" "" ;;
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
            if [[ -n "$uid" ]]; then offset=$(( uid+1 )); echo "$offset" > "$OFFSET_FILE"; fi
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
