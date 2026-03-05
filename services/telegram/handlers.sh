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
# Tambah Kuota
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
        _edit "$chat_id" "$msg_id" "📶 <b>Tambah Kuota</b>

Tidak ada akun yang mendukung fitur kuota." "$(_kb_home_btn)"
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
    _edit "$chat_id" "$msg_id" "➕ <b>Tambah Kuota</b>

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

    _edit "$chat_id" "$msg_id" "➕ <b>Tambah Kuota</b>
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

    _edit "$chat_id" "$msg_id" "➕ <b>Konfirmasi Tambah Kuota</b>
━━━━━━━━━━━━━━━━━━━
👤 Username : <code>${username}</code>
📶 Tambah Kuota : ${gb} GB
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

    _edit "$chat_id" "$msg_id" "✅ Kuota ditambahkan!" ""
    local new_quota; new_quota=$(_bw_get_quota "$username")
    local new_used; new_used=$(_bw_get_used "$username")
    local new_saldo; new_saldo=$(_saldo_get "$chat_id")
    _send "$chat_id" "➕ <b>Kuota Berhasil Ditambahkan</b>
━━━━━━━━━━━━━━━━━━━
👤 Username : <code>${username}</code>
📶 Ditambah : ${gb} GB
📊 Total Kuota : $(_bw_fmt "$new_quota")
📈 Terpakai    : $(_bw_fmt "$new_used")
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
        # Gunakan _jstr pure bash, tanpa python3
        local body="{"chat_id":"${uid}","text":$(_jstr "$text"),"parse_mode":"HTML"}"
        local result
        result=$(curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
            -H "Content-Type: application/json" -d "$body" --max-time 10 2>/dev/null)

        if echo "$result" | grep -q '"ok":true'; then
            ok=$(( ok + 1 ))
            _log "BROADCAST OK uid=$uid"
        else
            local err; err=$(echo "$result" | grep -oP '(?<="description":")[^"]+' 2>/dev/null || echo "?")
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
    local chat_id="$1" cb_id="$2" msg_id="$3" fname="$4" sname="$5"
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
        adm_topup_uid)
            _is_admin "$chat_id" || { _state_clear "$chat_id"; return 0; }
            if ! [[ "$text" =~ ^[0-9]{5,15}$ ]]; then
                _send "$chat_id" "❌ User ID tidak valid. Harus berupa angka 5-15 digit.

Ketik User ID:"
                return 0
            fi
            _state_set "$chat_id" "ADM_TARGET" "$text"
            _state_set "$chat_id" "STATE" "adm_topup_amount"
            local t_name="(belum terdaftar)"
            [[ -f "${USERS_DIR}/${text}.user" ]] && t_name=$(grep "^NAME=" "${USERS_DIR}/${text}.user" | cut -d= -f2)
            local t_saldo; t_saldo=$(_saldo_get "$text")
            _send "$chat_id" "💰 <b>Top Up Saldo</b>
━━━━━━━━━━━━━━━━━━━
🆔 User ID : <code>${text}</code>
👤 Nama    : ${t_name}
💰 Saldo   : Rp$(_fmt "$t_saldo")
━━━━━━━━━━━━━━━━━━━
Ketik <b>jumlah</b> top up (angka, tanpa titik):
Contoh: <code>50000</code>"
            return 0
            ;;
        adm_topup_amount)
            _is_admin "$chat_id" || { _state_clear "$chat_id"; return 0; }
            if ! [[ "$text" =~ ^[0-9]+$ ]] || [[ "$text" -eq 0 ]]; then
                _send "$chat_id" "❌ Jumlah tidak valid. Masukkan angka lebih dari 0.

Ketik jumlah top up:"
                return 0
            fi
            local target_id; target_id=$(_state_get "$chat_id" "ADM_TARGET")
            _state_clear "$chat_id"
            _adm_do_topup "$chat_id" "$target_id" "$text"
            return 0
            ;;
        adm_cek_uid)
            _is_admin "$chat_id" || { _state_clear "$chat_id"; return 0; }
            if ! [[ "$text" =~ ^[0-9]{5,15}$ ]]; then
                _send "$chat_id" "❌ User ID tidak valid.

Ketik User ID:"
                return 0
            fi
            _state_clear "$chat_id"
            _adm_do_cek_user "$chat_id" "$text"
            return 0
            ;;
        adm_kurangi_uid)
            _is_admin "$chat_id" || { _state_clear "$chat_id"; return 0; }
            if ! [[ "$text" =~ ^[0-9]{5,15}$ ]]; then
                _send "$chat_id" "❌ User ID tidak valid.

Ketik User ID:"
                return 0
            fi
            _state_set "$chat_id" "ADM_TARGET" "$text"
            _state_set "$chat_id" "STATE" "adm_kurangi_amount"
            local t_name="(belum terdaftar)"
            [[ -f "${USERS_DIR}/${text}.user" ]] && t_name=$(grep "^NAME=" "${USERS_DIR}/${text}.user" | cut -d= -f2)
            local t_saldo; t_saldo=$(_saldo_get "$text")
            _send "$chat_id" "➖ <b>Kurangi Saldo</b>
━━━━━━━━━━━━━━━━━━━
🆔 User ID : <code>${text}</code>
👤 Nama    : ${t_name}
💰 Saldo   : Rp$(_fmt "$t_saldo")
━━━━━━━━━━━━━━━━━━━
Ketik <b>jumlah</b> yang ingin dikurangi (angka):
Contoh: <code>5000</code>"
            return 0
            ;;
        adm_kurangi_amount)
            _is_admin "$chat_id" || { _state_clear "$chat_id"; return 0; }
            if ! [[ "$text" =~ ^[0-9]+$ ]] || [[ "$text" -eq 0 ]]; then
                _send "$chat_id" "❌ Jumlah tidak valid. Masukkan angka lebih dari 0.

Ketik jumlah yang dikurangi:"
                return 0
            fi
            local target_id; target_id=$(_state_get "$chat_id" "ADM_TARGET")
            _state_clear "$chat_id"
            _adm_do_kurangi "$chat_id" "$target_id" "$text"
            return 0
            ;;
        adm_hapus_username)
            _is_admin "$chat_id" || { _state_clear "$chat_id"; return 0; }
            if ! echo "$text" | grep -qE "^[a-zA-Z0-9]{3,20}$"; then
                _send "$chat_id" "❌ Username tidak valid.

Ketik username:"
                return 0
            fi
            _state_clear "$chat_id"
            _adm_do_hapus_akun "$chat_id" "$text"
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
📶 Kuota      : ${bw_total_gb_k} GB"

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

# ============================================================
# Admin Panel
# ============================================================
_cb_admin_panel() {
    local chat_id="$1" cb_id="$2" msg_id="$3"
    _is_admin "$chat_id" || { _answer "$cb_id" "❌ Akses ditolak"; return; }
    _answer "$cb_id" ""

    local total_user=0
    for ufile in "$USERS_DIR"/*.user; do [[ -f "$ufile" ]] && total_user=$(( total_user + 1 )); done
    local total_akun=0
    for conf in "$ACCOUNT_DIR"/*.conf; do [[ -f "$conf" ]] && total_akun=$(( total_akun + 1 )); done

    _edit "$chat_id" "$msg_id" "🔧 <b>Admin Panel</b>
━━━━━━━━━━━━━━━━━━━
👥 User terdaftar : ${total_user} user
🖥️ Total akun SSH : ${total_akun} akun
━━━━━━━━━━━━━━━━━━━
💰 <b>Top Up Saldo</b> — Tambah saldo ke user
➖ <b>Kurangi Saldo</b> — Potong saldo dari user
🗑️ <b>Hapus Akun</b> — Hapus akun SSH dari bot
📢 <b>Broadcast</b> — Kirim pesan ke semua user
👥 <b>Daftar User</b> — Lihat semua user terdaftar
🔍 <b>Cek User</b> — Cek saldo & akun milik user
📊 <b>History Transaksi</b> — Log semua transaksi
━━━━━━━━━━━━━━━━━━━" "$(_kb_admin_panel)"
}

# ============================================================
# Admin: Top Up Saldo (inline flow)
# ============================================================
_cb_adm_topup() {
    local chat_id="$1" cb_id="$2" msg_id="$3"
    _is_admin "$chat_id" || { _answer "$cb_id" "❌ Akses ditolak"; return; }
    _answer "$cb_id" ""
    _state_clear "$chat_id"
    _state_set "$chat_id" "STATE" "adm_topup_uid"
    _edit "$chat_id" "$msg_id" "💰 <b>Top Up Saldo</b>
━━━━━━━━━━━━━━━━━━━
Ketik <b>User ID</b> yang ingin di-top up.

Contoh: <code>123456789</code>

💡 User ID bisa dilihat saat user kirim /start ke bot." '[[{"text":"❌ Batal","callback_data":"m_admin"}]]'
}

# ============================================================
# Admin: Daftar User Terdaftar
# ============================================================
_cb_adm_daftar_user() {
    local chat_id="$1" cb_id="$2" msg_id="$3"
    _is_admin "$chat_id" || { _answer "$cb_id" "❌ Akses ditolak"; return; }
    _answer "$cb_id" ""

    local users=()
    for ufile in "$USERS_DIR"/*.user; do
        [[ -f "$ufile" ]] || continue
        local uid name joined
        uid=$(grep    "^UID="    "$ufile" | cut -d= -f2)
        name=$(grep   "^NAME="   "$ufile" | cut -d= -f2)
        joined=$(grep "^JOINED=" "$ufile" | cut -d= -f2)
        users+=("${uid}|${name}|${joined}")
    done

    local total=${#users[@]}
    if [[ $total -eq 0 ]]; then
        _edit "$chat_id" "$msg_id" "👥 <b>Daftar User</b>

Belum ada user terdaftar." "$(_kb_admin_panel)"
        return
    fi

    # Ambil 20 terakhir
    local start=$(( total > 20 ? total - 20 : 0 ))
    local msg="👥 <b>Daftar User Terdaftar</b> (${total} total)
━━━━━━━━━━━━━━━━━━━
"
    local i=$start
    while [[ $i -lt $total ]]; do
        IFS="|" read -r uid name joined <<< "${users[$i]}"
        local saldo; saldo=$(_saldo_get "$uid")
        msg+="👤 <b>${name}</b> — <code>${uid}</code>
   💰 Saldo: Rp$(_fmt "$saldo") | 📅 ${joined:0:10}
"
        i=$(( i + 1 ))
    done
    msg+="━━━━━━━━━━━━━━━━━━━"

    _edit "$chat_id" "$msg_id" "$msg" '[[{"text":"↩ Kembali","callback_data":"m_admin"}]]'
}

# ============================================================
# Admin: Cek User
# ============================================================
_cb_adm_cek_user() {
    local chat_id="$1" cb_id="$2" msg_id="$3"
    _is_admin "$chat_id" || { _answer "$cb_id" "❌ Akses ditolak"; return; }
    _answer "$cb_id" ""
    _state_clear "$chat_id"
    _state_set "$chat_id" "STATE" "adm_cek_uid"
    _edit "$chat_id" "$msg_id" "🔍 <b>Cek User</b>
━━━━━━━━━━━━━━━━━━━
Ketik <b>User ID</b> yang ingin dicek.

Contoh: <code>123456789</code>" '[[{"text":"❌ Batal","callback_data":"m_admin"}]]'
}

# ============================================================
# Admin handle input (topup & cek user)
# ============================================================
_adm_do_topup() {
    local chat_id="$1" target_id="$2" amount="$3"
    local cur; cur=$(( 10#$(_saldo_get "$target_id") ))
    local new=$(( cur + amount ))
    _saldo_set "$target_id" "$new"
    _log "TOPUP: admin=$chat_id target=$target_id amount=$amount new=$new"

    # Notif admin
    _send "$chat_id" "✅ <b>Top Up Berhasil</b>
━━━━━━━━━━━━━━━━━━━
🆔 User ID  : <code>${target_id}</code>
💳 Ditambah : Rp$(_fmt "$amount")
💰 Saldo    : Rp$(_fmt "$cur") → Rp$(_fmt "$new")
━━━━━━━━━━━━━━━━━━━" '[[{"text":"💰 Top Up Lagi","callback_data":"adm_topup"},{"text":"↩ Admin Panel","callback_data":"m_admin"}]]'

    # Notif ke user
    local target_name="User"
    [[ -f "${USERS_DIR}/${target_id}.user" ]] && target_name=$(grep "^NAME=" "${USERS_DIR}/${target_id}.user" | cut -d= -f2)
    _send "$target_id" "💰 <b>Saldo Kamu Bertambah!</b>
━━━━━━━━━━━━━━━━━━━
💳 Ditambah : Rp$(_fmt "$amount")
💰 Saldo    : Rp$(_fmt "$new")
━━━━━━━━━━━━━━━━━━━
Terima kasih sudah top up! 🙏" '[[{"text":"🏠 Menu Utama","callback_data":"home"}]]'
}

_adm_do_cek_user() {
    local chat_id="$1" target_id="$2"
    local saldo; saldo=$(_saldo_get "$target_id")

    # Info user
    local name="(tidak terdaftar)" joined="-"
    if [[ -f "${USERS_DIR}/${target_id}.user" ]]; then
        name=$(grep   "^NAME="   "${USERS_DIR}/${target_id}.user" | cut -d= -f2)
        joined=$(grep "^JOINED=" "${USERS_DIR}/${target_id}.user" | cut -d= -f2)
    fi

    # Akun SSH milik user ini
    local now_ts; now_ts=$(date +%s)
    local akun_info="" akun_count=0
    for conf in "$ACCOUNT_DIR"/*.conf; do
        [[ -f "$conf" ]] || continue
        local tg_uid; tg_uid=$(grep "^TG_USER_ID=" "$conf" | cut -d= -f2 | tr -d "[:space:]")
        [[ "$tg_uid" != "$target_id" ]] && continue
        local uname exp_ts is_trial
        uname=$(grep    "^USERNAME="   "$conf" | cut -d= -f2)
        exp_ts=$(grep   "^EXPIRED_TS=" "$conf" | cut -d= -f2)
        is_trial=$(grep "^IS_TRIAL="   "$conf" | cut -d= -f2)
        local tipe; [[ "$is_trial" == "1" ]] && tipe="Trial" || tipe="Premium"
        local status
        if [[ -n "$exp_ts" && "$exp_ts" =~ ^[0-9]+$ && $exp_ts -gt $now_ts ]]; then
            status="✅ Aktif"
        else
            status="❌ Expired"
        fi
        akun_info+="   • <code>${uname}</code> (${tipe}) ${status}
"
        akun_count=$(( akun_count + 1 ))
    done
    [[ $akun_count -eq 0 ]] && akun_info="   Tidak ada akun\n"

    _send "$chat_id" "🔍 <b>Info User</b>
━━━━━━━━━━━━━━━━━━━
🆔 User ID  : <code>${target_id}</code>
👤 Nama     : ${name}
📅 Bergabung: ${joined:0:10}
💰 Saldo    : Rp$(_fmt "$saldo")
━━━━━━━━━━━━━━━━━━━
🖥️ Akun SSH (${akun_count}):
$(echo -e "$akun_info")━━━━━━━━━━━━━━━━━━━" '[[{"text":"💰 Top Up Saldo","callback_data":"adm_topup"},{"text":"↩ Admin Panel","callback_data":"m_admin"}]]'
}

# ============================================================
# Admin: Kurangi Saldo
# ============================================================
_cb_adm_kurangi() {
    local chat_id="$1" cb_id="$2" msg_id="$3"
    _is_admin "$chat_id" || { _answer "$cb_id" "❌ Akses ditolak"; return; }
    _answer "$cb_id" ""
    _state_clear "$chat_id"
    _state_set "$chat_id" "STATE" "adm_kurangi_uid"
    _edit "$chat_id" "$msg_id" "➖ <b>Kurangi Saldo</b>
━━━━━━━━━━━━━━━━━━━
Ketik <b>User ID</b> yang saldonya ingin dikurangi.

Contoh: <code>123456789</code>" '[[{"text":"❌ Batal","callback_data":"m_admin"}]]'
}

_adm_do_kurangi() {
    local chat_id="$1" target_id="$2" amount="$3"
    local cur; cur=$(( 10#$(_saldo_get "$target_id") ))

    if [[ $amount -gt $cur ]]; then
        _send "$chat_id" "❌ Saldo user tidak cukup.
💰 Saldo saat ini : Rp$(_fmt "$cur")
➖ Mau dikurangi  : Rp$(_fmt "$amount")

Masukkan jumlah yang lebih kecil atau sama dengan saldo." '[[{"text":"➖ Coba Lagi","callback_data":"adm_kurangi"},{"text":"↩ Admin Panel","callback_data":"m_admin"}]]'
        return
    fi

    local new=$(( cur - amount ))
    _saldo_set "$target_id" "$new"
    _log "KURANGI: admin=$chat_id target=$target_id amount=$amount new=$new"

    local t_name="User"
    [[ -f "${USERS_DIR}/${target_id}.user" ]] && t_name=$(grep "^NAME=" "${USERS_DIR}/${target_id}.user" | cut -d= -f2)

    _send "$chat_id" "✅ <b>Saldo Berhasil Dikurangi</b>
━━━━━━━━━━━━━━━━━━━
🆔 User ID  : <code>${target_id}</code>
👤 Nama     : ${t_name}
➖ Dikurangi : Rp$(_fmt "$amount")
💰 Saldo    : Rp$(_fmt "$cur") → Rp$(_fmt "$new")
━━━━━━━━━━━━━━━━━━━" '[[{"text":"➖ Kurangi Lagi","callback_data":"adm_kurangi"},{"text":"↩ Admin Panel","callback_data":"m_admin"}]]'

    _send "$target_id" "⚠️ <b>Saldo Kamu Berubah</b>
━━━━━━━━━━━━━━━━━━━
➖ Dikurangi : Rp$(_fmt "$amount")
💰 Saldo    : Rp$(_fmt "$new")
━━━━━━━━━━━━━━━━━━━
Hubungi admin jika ada pertanyaan." '[[{"text":"🏠 Menu Utama","callback_data":"home"}]]'
}

# ============================================================
# Admin: Hapus Akun SSH
# ============================================================
_cb_adm_hapus_akun() {
    local chat_id="$1" cb_id="$2" msg_id="$3"
    _is_admin "$chat_id" || { _answer "$cb_id" "❌ Akses ditolak"; return; }
    _answer "$cb_id" ""
    _state_clear "$chat_id"
    _state_set "$chat_id" "STATE" "adm_hapus_username"
    _edit "$chat_id" "$msg_id" "🗑️ <b>Hapus Akun SSH</b>
━━━━━━━━━━━━━━━━━━━
Ketik <b>username</b> akun yang ingin dihapus.

Contoh: <code>user123</code>

⚠️ Akun akan langsung dihapus dari sistem!" '[[{"text":"❌ Batal","callback_data":"m_admin"}]]'
}

_adm_do_hapus_akun() {
    local chat_id="$1" username="$2"
    local conf="${ACCOUNT_DIR}/${username}.conf"

    if [[ ! -f "$conf" ]]; then
        _send "$chat_id" "❌ Akun <code>${username}</code> tidak ditemukan." '[[{"text":"🗑️ Coba Lagi","callback_data":"adm_hapus_akun"},{"text":"↩ Admin Panel","callback_data":"m_admin"}]]'
        return
    fi

    local tg_uid server is_trial
    tg_uid=$(grep  "^TG_USER_ID=" "$conf" | cut -d= -f2 | tr -d "[:space:]")
    server=$(grep  "^SERVER="     "$conf" | cut -d= -f2 | tr -d "[:space:]")
    is_trial=$(grep "^IS_TRIAL="  "$conf" | cut -d= -f2 | tr -d "[:space:]")

    # Hapus dari sistem lokal
    local local_ip; local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null)
    local sconf="${SERVER_DIR}/${server}.conf"
    local srv_ip=""
    [[ -f "$sconf" ]] && srv_ip=$(grep "^IP=" "$sconf" | cut -d= -f2 | tr -d "[:space:]")

    if [[ "$srv_ip" == "$local_ip" || -z "$srv_ip" ]]; then
        pkill -u "$username" &>/dev/null
        userdel -r "$username" &>/dev/null
        source /etc/zv-manager/core/bandwidth.sh
        _bw_cleanup_user "$username" 2>/dev/null
    else
        # Remote server
        local spass sport suser
        spass=$(grep "^PASS=" "$sconf" | cut -d= -f2)
        sport=$(grep "^PORT=" "$sconf" | cut -d= -f2)
        suser=$(grep "^USER=" "$sconf" | cut -d= -f2)
        sshpass -p "$spass" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
            -o BatchMode=no -p "$sport" "${suser}@${srv_ip}" \
            "zv-agent delete $username" &>/dev/null
    fi

    rm -f "$conf"
    rm -f "/etc/zv-manager/accounts/notified/${username}.notified"
    rm -f "/etc/zv-manager/accounts/notified/${username}.bw_warn"
    _log "ADM_HAPUS: admin=$chat_id username=$username"

    _send "$chat_id" "✅ <b>Akun Berhasil Dihapus</b>
━━━━━━━━━━━━━━━━━━━
🗑️ Username : <code>${username}</code>
🌐 Server   : ${server}
━━━━━━━━━━━━━━━━━━━" '[[{"text":"🗑️ Hapus Lagi","callback_data":"adm_hapus_akun"},{"text":"↩ Admin Panel","callback_data":"m_admin"}]]'

    # Notif ke pemilik akun
    if [[ -n "$tg_uid" ]]; then
        _send "$tg_uid" "⚠️ <b>Akun Kamu Dihapus</b>
━━━━━━━━━━━━━━━━━━━
🗑️ Username : <code>${username}</code>
━━━━━━━━━━━━━━━━━━━
Hubungi admin untuk informasi lebih lanjut." '[[{"text":"🏠 Menu Utama","callback_data":"home"}]]'
    fi
}

# ============================================================
# Admin: History Transaksi
# ============================================================
_cb_adm_history() {
    local chat_id="$1" cb_id="$2" msg_id="$3"
    _is_admin "$chat_id" || { _answer "$cb_id" "❌ Akses ditolak"; return; }
    _answer "$cb_id" ""

    local entries=()
    if [[ -f "$LOG" ]]; then
        while IFS= read -r line; do
            echo "$line" | grep -qE "^\[.+\] (BELI|RENEW|BW_BELI|TOPUP|KURANGI):" || continue
            entries+=("$line")
        done < "$LOG"
    fi

    local total=${#entries[@]}
    if [[ $total -eq 0 ]]; then
        _edit "$chat_id" "$msg_id" "📊 <b>History Transaksi</b>

Belum ada transaksi tercatat." '[[{"text":"↩ Admin Panel","callback_data":"m_admin"}]]'
        return
    fi

    # Ambil 15 terakhir
    local start=$(( total > 15 ? total - 15 : 0 ))
    local msg="📊 <b>History Transaksi</b> (${total} total, 15 terakhir)
━━━━━━━━━━━━━━━━━━━
"
    local i=$start
    while [[ $i -lt $total ]]; do
        local line="${entries[$i]}"
        local ts; ts=$(echo "$line" | grep -oP "^\[\K[^\]]+")

        if echo "$line" | grep -q "\] BELI:"; then
            local uid user days total_harga server
            uid=$(echo "$line"         | grep -oP "(?<=BELI: )\S+")
            user=$(echo "$line"        | grep -oP "user=\K\S+")
            days=$(echo "$line"        | grep -oP "days=\K[0-9]+")
            total_harga=$(echo "$line" | grep -oP "total=\K[0-9]+")
            server=$(echo "$line"      | grep -oP "server=\K\S+")
            msg+="🛒 <b>Beli</b> — <code>${user}</code> (${server})
   ${days} hari · Rp$(_fmt "$total_harga") · uid:${uid}
   <i>${ts}</i>
"
        elif echo "$line" | grep -q "\] RENEW:"; then
            local uid user days total_harga
            uid=$(echo "$line"         | grep -oP "(?<=RENEW: )\S+")
            user=$(echo "$line"        | grep -oP "user=\K\S+")
            days=$(echo "$line"        | grep -oP "days=\K[0-9]+")
            total_harga=$(echo "$line" | grep -oP "total=\K[0-9]+")
            msg+="🔄 <b>Renew</b> — <code>${user}</code>
   +${days} hari · Rp$(_fmt "$total_harga") · uid:${uid}
   <i>${ts}</i>
"
        elif echo "$line" | grep -q "\] BW_BELI:"; then
            local uid user gb total_harga
            uid=$(echo "$line"         | grep -oP "(?<=BW_BELI: )\S+")
            user=$(echo "$line"        | grep -oP "user=\K\S+")
            gb=$(echo "$line"          | grep -oP "gb=\K[0-9]+")
            total_harga=$(echo "$line" | grep -oP "total=\K[0-9]+")
            msg+="📶 <b>Beli BW</b> — <code>${user}</code>
   +${gb} GB · Rp$(_fmt "$total_harga") · uid:${uid}
   <i>${ts}</i>
"
        elif echo "$line" | grep -q "\] TOPUP:"; then
            local admin target amount
            admin=$(echo "$line"  | grep -oP "admin=\K\S+")
            target=$(echo "$line" | grep -oP "target=\K\S+")
            amount=$(echo "$line" | grep -oP "amount=\K[0-9]+")
            msg+="💰 <b>Top Up</b> — uid:${target}
   +Rp$(_fmt "$amount") oleh admin:${admin}
   <i>${ts}</i>
"
        elif echo "$line" | grep -q "\] KURANGI:"; then
            local admin target amount
            admin=$(echo "$line"  | grep -oP "admin=\K\S+")
            target=$(echo "$line" | grep -oP "target=\K\S+")
            amount=$(echo "$line" | grep -oP "amount=\K[0-9]+")
            msg+="➖ <b>Kurangi</b> — uid:${target}
   -Rp$(_fmt "$amount") oleh admin:${admin}
   <i>${ts}</i>
"
        fi
        [[ $i -lt $(( total - 1 )) ]] && msg+="─────────────────
"
        i=$(( i + 1 ))
    done
    msg+="━━━━━━━━━━━━━━━━━━━"

    _edit "$chat_id" "$msg_id" "$msg" '[[{"text":"↩ Admin Panel","callback_data":"m_admin"}]]'
}

