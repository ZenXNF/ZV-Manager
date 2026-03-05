#!/bin/bash
# ============================================================
#   ZV-Manager - Telegram Bot Handlers
#   _cb_*, _handle_*, _do_broadcast, _already_trial
# ============================================================

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
        local sconf="${SERVER_DIR}/${server}.conf"
        local srv_domain srv_ip
        if [[ -f "$sconf" ]]; then
            srv_domain=$(grep "^DOMAIN=" "$sconf" | cut -d= -f2 | tr -d "[:space:]")
            srv_ip=$(grep     "^IP="     "$sconf" | cut -d= -f2 | tr -d "[:space:]")
            domain="${srv_domain:-$srv_ip}"
        else
            domain=$(grep "^DOMAIN=" "$conf" | cut -d= -f2)
        fi

        [[ -z "$uname" ]] && continue

        local status sisa_label
        if [[ -n "$exp_ts" && "$exp_ts" =~ ^[0-9]+$ ]]; then
            local sisa_detik=$(( exp_ts - now_ts ))
            if [[ $sisa_detik -le 0 ]]; then
                status="❌ Expired"; sisa_label="Sudah habis"
            elif [[ $sisa_detik -lt 3600 ]]; then
                status="⚠️ Aktif"; sisa_label="Kurang dari 1 jam"
            elif [[ $sisa_detik -lt 86400 ]]; then
                local sisa_jam=$(( sisa_detik / 3600 ))
                status="⚠️ Aktif"; sisa_label="${sisa_jam} jam lagi"
            else
                local sisa_hari=$(( sisa_detik / 86400 ))
                status="✅ Aktif"; sisa_label="${sisa_hari} hari lagi"
            fi
        else
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
        out+="\n👤 <b>${uname}</b> <i>(${tipe})</i>\n🌐 Host    : <code>${domain}</code>\n🔑 Pass    : <code>${pass}</code>\n⏳ Expired : ${exp_display}\n📊 Status  : ${status} · ${sisa_label}\n━━━━━━━━━━━━━━━━━━━"
    done

    if ! $found; then
        out+="\nKamu belum punya akun aktif.\n\nTekan <b>Buat Akun</b> untuk membeli."
    fi

    _edit "$chat_id" "$msg_id" "$(echo -e "$out")" "$(_kb_home_btn)"
}

# ============================================================
# Perpanjang Akun
# ============================================================
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

    local kb='[' i=0 total=${#akun_list[@]}
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
    local chat_id="$1" cb_id="$2" msg_id="$3" username="$4" fname="$5"
    _answer "$cb_id" ""

    local conf="${ACCOUNT_DIR}/${username}.conf"
    [[ ! -f "$conf" ]] && { _edit "$chat_id" "$msg_id" "❌ Akun tidak ditemukan." "$(_kb_home_btn)"; return; }

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
    _state_set "$chat_id" "FNAME"    "${fname:-User}"

    _edit "$chat_id" "$msg_id" "🔄 <b>Perpanjang Akun</b>
━━━━━━━━━━━━━━━━━━━
👤 Username : <code>${username}</code>
🌐 Server   : ${TG_SERVER_LABEL}
⏳ Expired  : ${exp_display}
💰 Harga    : ${hh}
━━━━━━━━━━━━━━━━━━━
Berapa hari ingin diperpanjang? (1-365)" '[[{"text":"↩ Kembali","callback_data":"m_perpanjang"}]]'
}

_cb_konfirm_renew() {
    local chat_id="$1" cb_id="$2" msg_id="$3"
    [[ "$(_state_get "$chat_id" "STATE")" != "renew_confirm" ]] && {
        _answer "$cb_id" "⚠️ Sesi habis, mulai ulang"
        _state_clear "$chat_id"; return
    }
    _answer "$cb_id" "⏳ Memperpanjang akun..."

    local username sname days fname
    username=$(_state_get "$chat_id" "USERNAME")
    sname=$(_state_get "$chat_id" "SERVER")
    days=$(_state_get "$chat_id" "DAYS")
    fname=$(_state_get "$chat_id" "FNAME")

    _load_tg_conf "$sname"
    local harga=$(( 10#${TG_HARGA_HARI} ))
    local total=$(( harga * days ))

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
    if [[ -n "$old_exp_ts" && "$old_exp_ts" =~ ^[0-9]+$ && $old_exp_ts -gt $now_ts ]]; then
        base_ts=$old_exp_ts
    else
        base_ts=$now_ts
    fi

    local new_exp_ts=$(( base_ts + days * 86400 ))
    local new_exp_date; new_exp_date=$(date -d "@${new_exp_ts}" +"%Y-%m-%d")
    local new_exp_display; new_exp_display=$(TZ="Asia/Jakarta" date -d "@${new_exp_ts}" +"%d %b %Y %H:%M WIB")

    local sconf_r="${SERVER_DIR}/${sname}.conf"
    local domain
    if [[ -f "$sconf_r" ]]; then
        local sd; sd=$(grep "^DOMAIN=" "$sconf_r" | cut -d= -f2 | tr -d "[:space:]")
        local si; si=$(grep "^IP="     "$sconf_r" | cut -d= -f2 | tr -d "[:space:]")
        domain="${sd:-$si}"
    else
        domain=$(grep "^DOMAIN=" "$conf" | cut -d= -f2)
    fi

    local tmp; tmp=$(mktemp)
    grep -v "^EXPIRED=\|^EXPIRED_TS=" "$conf" > "$tmp"
    echo "EXPIRED=$new_exp_date"    >> "$tmp"
    echo "EXPIRED_TS=$new_exp_ts"   >> "$tmp"
    mv "$tmp" "$conf"

    chage -E "$new_exp_date" "$username" &>/dev/null
    rm -f "/etc/zv-manager/accounts/notified/${username}.notified"

    _state_clear "$chat_id"
    _log "RENEW: $chat_id user=$username days=$days total=$total"
    _notify_admin_beli "RENEW" "${fname:-User}" "$chat_id" "$username" "$TG_SERVER_LABEL" "$days" "$total"

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
# Tambah Bandwidth
# ============================================================
_cb_tambah_bw() {
    local chat_id="$1" cb_id="$2" msg_id="$3"
    _answer "$cb_id" ""

    local akun_list=()
    for conf in "$ACCOUNT_DIR"/*.conf; do
        [[ -f "$conf" ]] || continue
        local tg_uid; tg_uid=$(grep "^TG_USER_ID=" "$conf" | cut -d= -f2 | tr -d "[:space:]")
        [[ "$tg_uid" != "$chat_id" ]] && continue
        local is_trial; is_trial=$(grep "^IS_TRIAL=" "$conf" | cut -d= -f2 | tr -d "[:space:]")
        [[ "$is_trial" == "1" ]] && continue
        local bw_quota; bw_quota=$(grep "^BW_QUOTA_BYTES=" "$conf" | cut -d= -f2 | tr -d "[:space:]")
        [[ -z "$bw_quota" || "$bw_quota" -eq 0 ]] && continue
        local uname; uname=$(grep "^USERNAME=" "$conf" | cut -d= -f2 | tr -d "[:space:]")
        [[ -n "$uname" ]] && akun_list+=("$uname")
    done

    if [[ ${#akun_list[@]} -eq 0 ]]; then
        _edit "$chat_id" "$msg_id" "📶 <b>Tambah Bandwidth</b>

Tidak ada akun yang mendukung fitur bandwidth." "$(_kb_home_btn)"
        return
    fi

    local kb='[' i=0 total=${#akun_list[@]}
    while [[ $i -lt $total ]]; do
        local u1="${akun_list[$i]}"
        local row="[{\"text\":\"${u1}\",\"callback_data\":\"bw_akun_${u1}\"}"
        if [[ $(( i + 1 )) -lt $total ]]; then
            local u2="${akun_list[$(( i + 1 ))]}"
            row="${row},{\"text\":\"${u2}\",\"callback_data\":\"bw_akun_${u2}\"}"
            i=$(( i + 2 ))
        else
            i=$(( i + 1 ))
        fi
        row="${row}]"
        [[ "$kb" == "[" ]] && kb="${kb}${row}" || kb="${kb},${row}"
    done
    kb="${kb},[{\"text\":\"\u21a9 Kembali\",\"callback_data\":\"m_akun\"}]]"
    _edit "$chat_id" "$msg_id" "➕ <b>Tambah Bandwidth</b>

Pilih akun:" "$kb"
}

_cb_tambah_bw_akun() {
    local chat_id="$1" cb_id="$2" msg_id="$3" username="$4"
    _answer "$cb_id" ""

    local conf="${ACCOUNT_DIR}/${username}.conf"
    [[ ! -f "$conf" ]] && { _edit "$chat_id" "$msg_id" "❌ Akun tidak ditemukan." "$(_kb_home_btn)"; return; }
    local tg_uid; tg_uid=$(grep "^TG_USER_ID=" "$conf" | cut -d= -f2 | tr -d "[:space:]")
    [[ "$tg_uid" != "$chat_id" ]] && { _answer "$cb_id" "❌ Bukan akun kamu"; return; }

    local sname; sname=$(grep "^SERVER=" "$conf" | cut -d= -f2 | tr -d "[:space:]")
    _load_tg_conf "$sname"

    local bw_quota bw_used bw_blocked
    bw_quota=$(grep "^BW_QUOTA_BYTES=" "$conf" | cut -d= -f2 | tr -d "[:space:]")
    bw_used=$(grep  "^BW_USED_BYTES="  "$conf" | cut -d= -f2 | tr -d "[:space:]")
    bw_blocked=$(grep "^BW_BLOCKED="   "$conf" | cut -d= -f2 | tr -d "[:space:]")

    local used_fmt quota_fmt bar
    used_fmt=$(_bw_fmt "${bw_used:-0}")
    quota_fmt=$(_bw_fmt "${bw_quota:-0}")
    bar=$(_bw_progress_bar "${bw_used:-0}" "${bw_quota:-0}")

    local harga_hari=$(( 10#${TG_HARGA_HARI:-0} ))
    local bw_per_hari=$(( 10#${TG_BW_PER_HARI:-5} ))
    local harga_per_gb=0
    [[ $bw_per_hari -gt 0 ]] && harga_per_gb=$(( harga_hari / bw_per_hari ))

    local status_str="✅ Aktif"
    [[ "$bw_blocked" == "1" ]] && status_str="🚫 Diblokir (BW habis)"

    local p1=$(( harga_per_gb * 1 ))
    local p5=$(( harga_per_gb * 5 ))
    local p10=$(( harga_per_gb * 10 ))
    local saldo; saldo=$(_saldo_get "$chat_id")

    _state_clear "$chat_id"
    _state_set "$chat_id" "STATE"    "bw_pilih_paket"
    _state_set "$chat_id" "USERNAME" "$username"
    _state_set "$chat_id" "SERVER"   "$sname"

    local kb="[[{\"text\":\"➕ 1 GB — Rp$(_fmt "$p1")\",\"callback_data\":\"bw_beli_1_${username}\"},{\"text\":\"➕ 5 GB — Rp$(_fmt "$p5")\",\"callback_data\":\"bw_beli_5_${username}\"}],[{\"text\":\"➕ 10 GB — Rp$(_fmt "$p10")\",\"callback_data\":\"bw_beli_10_${username}\"}],[{\"text\":\"\u21a9 Kembali\",\"callback_data\":\"m_tambah_bw\"}]]"

    _edit "$chat_id" "$msg_id" "➕ <b>Tambah Bandwidth</b>
━━━━━━━━━━━━━━━━━━━
👤 Username : <code>${username}</code>
📶 Terpakai : ${used_fmt} / ${quota_fmt}
${bar}
📊 Status   : ${status_str}
💰 Saldo    : Rp$(_fmt "$saldo")
━━━━━━━━━━━━━━━━━━━
Pilih paket tambahan:" "$kb"
}

_cb_bw_beli() {
    local chat_id="$1" cb_id="$2" msg_id="$3" gb="$4" username="$5"
    _answer "$cb_id" ""

    local conf="${ACCOUNT_DIR}/${username}.conf"
    [[ ! -f "$conf" ]] && { _edit "$chat_id" "$msg_id" "❌ Akun tidak ditemukan." "$(_kb_home_btn)"; return; }

    local sname; sname=$(grep "^SERVER=" "$conf" | cut -d= -f2 | tr -d "[:space:]")
    _load_tg_conf "$sname"

    local harga_hari=$(( 10#${TG_HARGA_HARI:-0} ))
    local bw_per_hari=$(( 10#${TG_BW_PER_HARI:-5} ))
    local harga_per_gb=0
    [[ $bw_per_hari -gt 0 ]] && harga_per_gb=$(( harga_hari / bw_per_hari ))
    local total=$(( harga_per_gb * gb ))
    local saldo; saldo=$(( 10#$(_saldo_get "$chat_id") ))

    if [[ $total -gt 0 && $saldo -lt $total ]]; then
        _edit "$chat_id" "$msg_id" "❌ Saldo tidak cukup.
Saldo  : Rp$(_fmt "$saldo")
Butuh  : Rp$(_fmt "$total")

Hubungi admin untuk top up." "$(_kb_home_btn)"
        _state_clear "$chat_id"; return
    fi

    _state_set "$chat_id" "STATE"    "bw_confirm"
    _state_set "$chat_id" "USERNAME" "$username"
    _state_set "$chat_id" "SERVER"   "$sname"
    _state_set "$chat_id" "BW_GB"    "$gb"
    _state_set "$chat_id" "BW_TOTAL" "$total"

    _edit "$chat_id" "$msg_id" "➕ <b>Konfirmasi Tambah BW</b>
━━━━━━━━━━━━━━━━━━━
👤 Username : <code>${username}</code>
📶 Tambah   : ${gb} GB
💸 Total    : Rp$(_fmt "$total")
💰 Saldo    : Rp$(_fmt "$saldo")
━━━━━━━━━━━━━━━━━━━
Lanjutkan?" "$(_kb_confirm "bw_konfirm")"
}

_cb_konfirm_bw() {
    local chat_id="$1" cb_id="$2" msg_id="$3"
    [[ "$(_state_get "$chat_id" "STATE")" != "bw_confirm" ]] && {
        _answer "$cb_id" "⚠️ Sesi habis"; _state_clear "$chat_id"; return
    }
    _answer "$cb_id" "⏳ Memproses..."

    local username gb total sname
    username=$(_state_get "$chat_id" "USERNAME")
    gb=$(_state_get "$chat_id" "BW_GB")
    total=$(_state_get "$chat_id" "BW_TOTAL")
    sname=$(_state_get "$chat_id" "SERVER")

    if [[ $total -gt 0 ]]; then
        _saldo_deduct "$chat_id" "$total" || {
            _edit "$chat_id" "$msg_id" "❌ Saldo tidak cukup." ""; _state_clear "$chat_id"; return
        }
    fi

    local add_bytes; add_bytes=$(( gb * 1024 * 1024 * 1024 ))
    _bw_add_quota "$username" "$add_bytes"
    _bw_unblock "$username" 2>/dev/null

    _state_clear "$chat_id"
    _log "BW_BELI: $chat_id user=$username gb=$gb total=$total"

    _edit "$chat_id" "$msg_id" "✅ Bandwidth ditambahkan!" ""
    local new_quota; new_quota=$(_bw_get_quota "$username")
    local new_used; new_used=$(_bw_get_used "$username")
    local new_saldo; new_saldo=$(_saldo_get "$chat_id")
    _send "$chat_id" "➕ <b>Bandwidth Berhasil Ditambahkan</b>
━━━━━━━━━━━━━━━━━━━
👤 Username : <code>${username}</code>
📶 Ditambah : ${gb} GB
📊 Total BW : $(_bw_fmt "$new_quota")
📈 Terpakai : $(_bw_fmt "$new_used")
💸 Dibayar  : Rp$(_fmt "$total")
💰 Sisa Saldo: Rp$(_fmt "$new_saldo")
━━━━━━━━━━━━━━━━━━━
Koneksi sudah aktif kembali!"
}

# ============================================================
# Broadcast (Admin Only)
# ============================================================
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

    local uid_file; uid_file=$(mktemp)
    {
        for ufile in "$USERS_DIR"/*.user; do
            [[ -f "$ufile" ]] || continue
            grep "^UID=" "$ufile" | cut -d= -f2 | tr -d "[:space:]"
        done
        for conf in "$ACCOUNT_DIR"/*.conf; do
            [[ -f "$conf" ]] || continue
            grep "^TG_USER_ID=" "$conf" | cut -d= -f2 | tr -d "[:space:]"
        done
    } | sort -u > "$uid_file"

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
        local jfile; jfile=$(mktemp)
        python3 - "$uid" "$text" > "$jfile" << 'PYINLINE'
import json, sys
uid, text = sys.argv[1], sys.argv[2]
print(json.dumps({"chat_id": uid, "text": text, "parse_mode": "HTML"}))
PYINLINE
        local result
        result=$(curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
            -H "Content-Type: application/json" -d "@${jfile}" --max-time 10 2>/dev/null)
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

# ============================================================
# /saldo
# ============================================================
_handle_saldo() {
    local chat_id="$1"
    local saldo; saldo=$(_saldo_get "$chat_id")
    _send "$chat_id" "💰 <b>Saldo Kamu</b>
━━━━━━━━━━━━━━━━━━━
💳 Saldo : Rp$(_fmt "$saldo")
━━━━━━━━━━━━━━━━━━━
Hubungi admin untuk top up." '[[{"text":"🏠 Menu Utama","callback_data":"home"}]]'
}

# ============================================================
# /history
# ============================================================
_handle_history() {
    local chat_id="$1"
    local entries=()

    if [[ -f "$LOG" ]]; then
        while IFS= read -r line; do
            echo "$line" | grep -qE "^\[.+\] (BELI|RENEW|BW_BELI): ${chat_id} " || continue
            local ts; ts=$(echo "$line" | grep -oP "^\[\K[^\]]+")
            if echo "$line" | grep -q "^\[.+\] BELI:"; then
                local user days total
                user=$(echo  "$line" | grep -oP "user=\K\S+")
                days=$(echo  "$line" | grep -oP "days=\K[0-9]+")
                total=$(echo "$line" | grep -oP "total=\K[0-9]+")
                entries+=("${ts}|🛒 Buat Akun|${user}|${days} hari|Rp$(_fmt "$total")")
            elif echo "$line" | grep -q "^\[.+\] RENEW:"; then
                local user days total
                user=$(echo  "$line" | grep -oP "user=\K\S+")
                days=$(echo  "$line" | grep -oP "days=\K[0-9]+")
                total=$(echo "$line" | grep -oP "total=\K[0-9]+")
                entries+=("${ts}|🔄 Perpanjang|${user}|+${days} hari|Rp$(_fmt "$total")")
            elif echo "$line" | grep -q "^\[.+\] BW_BELI:"; then
                local user gb total
                user=$(echo  "$line" | grep -oP "user=\K\S+")
                gb=$(echo    "$line" | grep -oP "gb=\K[0-9]+")
                total=$(echo "$line" | grep -oP "total=\K[0-9]+")
                entries+=("${ts}|📶 Tambah BW|${user}|+${gb} GB|Rp$(_fmt "$total")")
            fi
        done < "$LOG"
    fi

    if [[ ${#entries[@]} -eq 0 ]]; then
        _send "$chat_id" "📝 <b>Riwayat Transaksi</b>

Belum ada transaksi." '[[{"text":"🏠 Menu Utama","callback_data":"home"}]]'
        return
    fi

    local total_entry=${#entries[@]}
    local start=$(( total_entry > 10 ? total_entry - 10 : 0 ))
    local msg="📝 <b>Riwayat Transaksi</b> (${total_entry} total)
━━━━━━━━━━━━━━━━━━━
"
    local i=$start
    while [[ $i -lt $total_entry ]]; do
        IFS="|" read -r ts tipe user keterangan jumlah <<< "${entries[$i]}"
        msg+="${tipe} <code>${user}</code>
"
        msg+="   ${keterangan} — ${jumlah}
"
        msg+="   <i>${ts}</i>
"
        [[ $i -lt $(( total_entry - 1 )) ]] && msg+="─────────────────
"
        i=$(( i + 1 ))
    done

    local saldo; saldo=$(_saldo_get "$chat_id")
    msg+="━━━━━━━━━━━━━━━━━━━
💳 Saldo saat ini: Rp$(_fmt "$saldo")"
    _send "$chat_id" "$(echo -e "$msg")" '[[{"text":"🏠 Menu Utama","callback_data":"home"}]]'
}

# ============================================================
# /topup (Admin only)
# ============================================================
_handle_topup() {
    local chat_id="$1" text="$2"
    _is_admin "$chat_id" || {
        _send "$chat_id" "❌ Perintah ini hanya untuk admin."
        return
    }

    local target_id amount
    target_id=$(echo "$text" | awk '{print $2}')
    amount=$(echo "$text"   | awk '{print $3}')

    if [[ -z "$target_id" || -z "$amount" ]]; then
        _send "$chat_id" "❌ Format salah.
Gunakan: <code>/topup &lt;user_id&gt; &lt;jumlah&gt;</code>
Contoh : <code>/topup 123456789 50000</code>"
        return
    fi

    if ! [[ "$target_id" =~ ^[0-9]+$ && "$amount" =~ ^[0-9]+$ ]]; then
        _send "$chat_id" "❌ User ID dan jumlah harus berupa angka."
        return
    fi

    if [[ "$amount" -eq 0 ]]; then
        _send "$chat_id" "❌ Jumlah top up tidak boleh 0."
        return
    fi

    local cur; cur=$(( 10#$(_saldo_get "$target_id") ))
    local new=$(( cur + amount ))
    _saldo_set "$target_id" "$new"
    _log "TOPUP: admin=$chat_id target=$target_id amount=$amount new=$new"

    _send "$chat_id" "✅ <b>Top Up Berhasil</b>
━━━━━━━━━━━━━━━━━━━
🆔 User ID  : <code>${target_id}</code>
💳 Ditambah : Rp$(_fmt "$amount")
💰 Saldo    : Rp$(_fmt "$cur") → Rp$(_fmt "$new")
━━━━━━━━━━━━━━━━━━━"

    _send "$target_id" "💰 <b>Saldo Kamu Bertambah!</b>
━━━━━━━━━━━━━━━━━━━
💳 Ditambah : Rp$(_fmt "$amount")
💰 Saldo    : Rp$(_fmt "$new")
━━━━━━━━━━━━━━━━━━━
Terima kasih sudah top up! 🙏" '[[{"text":"🏠 Menu Utama","callback_data":"home"}]]'
}

# ============================================================
# /start
# ============================================================
_handle_start() {
    _state_clear "$1"
    _register_user "$1" "$2"
    _send "$1" "$(_text_home "$2" "$1")" "$(_kb_for_user "$1")"
}

# ============================================================
# Callback navigasi
# ============================================================
_cb_saldo_history() {
    local chat_id="$1" cb_id="$2" msg_id="$3"
    _answer "$cb_id" ""
    local saldo; saldo=$(_saldo_get "$chat_id")
    _edit "$chat_id" "$msg_id" "💰 <b>Saldo & Riwayat</b>
━━━━━━━━━━━━━━━━━━━
💳 Saldo kamu: Rp$(_fmt "$saldo")
━━━━━━━━━━━━━━━━━━━
Pilih menu:" '[[{"text":"📝 Riwayat Transaksi","callback_data":"m_history"},{"text":"🏠 Menu Utama","callback_data":"home"}]]'
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

_cb_s_buat() {
    local chat_id="$1" cb_id="$2" fname="$3" sname="$4"
    local conf="${SERVER_DIR}/${sname}.conf"
    [[ ! -f "$conf" ]] && { _answer "$cb_id" "❌ Server tidak ditemukan"; return; }
    unset NAME IP DOMAIN; source "$conf"; _load_tg_conf "$sname"
    [[ $(_count_accounts "$IP") -ge $TG_MAX_AKUN ]] && { _answer "$cb_id" "❌ Server penuh!"; return; }

    _answer "$cb_id" ""
    _state_clear "$chat_id"
    _state_set "$chat_id" "STATE"  "await_user"
    _state_set "$chat_id" "SERVER" "$sname"
    _state_set "$chat_id" "FNAME"  "$fname"

    _send "$chat_id" "Server : <b>${TG_SERVER_LABEL}</b>

Ketik username yang kamu inginkan.
Hanya huruf kecil dan angka, minimal 3 karakter."
}

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
    local suffix; suffix=$(tr -dc '0-9' </dev/urandom | head -c 4)
    local username="Trial${suffix}"
    local password="ZenXNF"
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
            if ! echo "$text" | grep -qE '^[a-zA-Z0-9]{3,20}$'; then
                _send "$chat_id" "❌ Username tidak valid. Huruf (besar/kecil) dan angka, 3-20 karakter.

Ketik username:"; return 0
            fi
            id "$text" &>/dev/null && {
                _send "$chat_id" "❌ Username <b>${text}</b> sudah digunakan.

Ketik username lain:"; return 0
            }
            _state_set "$chat_id" "USERNAME" "$text"
            _state_set "$chat_id" "STATE" "await_pass"
            _send "$chat_id" "Ketik password:
(Minimal 4 karakter, boleh huruf besar/kecil dan angka)"
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

            local bw_per_hari_k=$(( 10#${TG_BW_PER_HARI:-5} ))
            local bw_total_gb_k=$(( days * bw_per_hari_k ))
            local bw_line=""; [[ $bw_per_hari_k -gt 0 ]] && bw_line="
📶 Bandwidth  : ${bw_total_gb_k} GB"

            _send "$chat_id" "📋 <b>Konfirmasi Pesanan</b>
━━━━━━━━━━━━━━━━━━━
🌐 Server     : ${TG_SERVER_LABEL}
👤 Username   : <code>${username}</code>
🔑 Password   : <code>${password}</code>
📅 Masa Aktif : ${days} hari${bw_line}
💰 Harga      : ${hh}
💸 Total      : Rp$(_fmt "$total")${saldo_line}
━━━━━━━━━━━━━━━━━━━
Lanjutkan?" "$(_kb_confirm "konfirm")"
            ;;
    esac
    return 0
}

# ============================================================
# Konfirmasi buat akun
# ============================================================
_cb_konfirm() {
    local chat_id="$1" cb_id="$2" msg_id="$3"
    [[ "$(_state_get "$chat_id" "STATE")" != "await_confirm" ]] && {
        _answer "$cb_id" "⚠️ Sesi habis, mulai ulang"
        _state_clear "$chat_id"; return
    }
    _answer "$cb_id" "⏳ Membuat akun..."

    local sname username password days fname
    sname=$(_state_get "$chat_id" "SERVER")
    username=$(_state_get "$chat_id" "USERNAME")
    password=$(_state_get "$chat_id" "PASSWORD")
    days=$(_state_get "$chat_id" "DAYS")
    fname=$(_state_get "$chat_id" "FNAME")

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
        local bw_per_hari=$(( 10#${TG_BW_PER_HARI:-5} ))
        local bw_quota_bytes; bw_quota_bytes=$(( days * bw_per_hari * 1024 * 1024 * 1024 ))
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
BW_QUOTA_BYTES=$bw_quota_bytes
BW_USED_BYTES=0
BW_BLOCKED=0
EOF
        _bw_init_user "$username" 2>/dev/null
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
    _notify_admin_beli "BELI" "$fname" "$chat_id" "$username" "$TG_SERVER_LABEL" "$days" "$total"
    _edit "$chat_id" "$msg_id" "✅ Akun sedang dibuat..." ""
    _send_akun "$chat_id" "BELI" "$username" "$password" "$domain" \
        "$exp_display" "${TG_LIMIT_IP}" "${TG_SERVER_LABEL}" "$days" "$total"
}
