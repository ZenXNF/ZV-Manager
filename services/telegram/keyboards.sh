#!/bin/bash
# ============================================================
#   ZV-Manager - Telegram Bot Keyboards & Teks
#   _kb_*, _text_*, _send_akun
# ============================================================

_kb_home() {
    echo '[[{"text":"⚡ Buat Akun","callback_data":"m_buat"},{"text":"🎁 Coba Gratis","callback_data":"m_trial"}],[{"text":"📋 Akun Saya","callback_data":"m_akun"},{"text":"🔄 Perpanjang","callback_data":"m_perpanjang"}],[{"text":"📋 Riwayat Saldo","callback_data":"m_saldo_history"}]]'
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
_kb_for_user() {
    local uid="$1"
    if _is_admin "$uid"; then
        echo '[[{"text":"⚡ Buat Akun","callback_data":"m_buat"},{"text":"🎁 Coba Gratis","callback_data":"m_trial"}],[{"text":"📋 Akun Saya","callback_data":"m_akun"},{"text":"🔄 Perpanjang","callback_data":"m_perpanjang"}],[{"text":"📋 Riwayat Saldo","callback_data":"m_saldo_history"},{"text":"🔧 Admin","callback_data":"m_admin"}]]'
    else
        echo "$(_kb_home)"
    fi
}

_kb_admin_panel() {
    echo '[[{"text":"💰 Top Up Saldo","callback_data":"adm_topup"},{"text":"➖ Kurangi Saldo","callback_data":"adm_kurangi"}],[{"text":"🗑️ Hapus Akun","callback_data":"adm_hapus_akun"},{"text":"📢 Broadcast","callback_data":"m_broadcast"}],[{"text":"👥 Daftar User","callback_data":"adm_daftar_user"},{"text":"🔍 Cek User","callback_data":"adm_cek_user"}],[{"text":"📊 History Transaksi","callback_data":"adm_history"},{"text":"🏠 Menu Utama","callback_data":"home"}]]'
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
        # Hitung kuota harian & 30hr dari TG_BW_PER_HARI
        local bw_hr=$(( 10#${TG_BW_PER_HARI:-5} ))
        local bw_30=$(( bw_hr * 30 ))
        local kuota_label
        [[ $bw_hr -eq 0 ]] && kuota_label="Unlimited" || kuota_label="${bw_hr} GB/hari · ${bw_30} GB/30hr"
        out+="🌐 <b>${TG_SERVER_LABEL}</b>
💰 Harga/hari  : ${hh}
📅 Harga/30hr  : ${hb}
📶 Kuota       : ${kuota_label}
🔢 Limit IP    : ${TG_LIMIT_IP} IP/akun
👥 Total Akun  : ${count}/${TG_MAX_AKUN}

"
    done < <(_get_server_list)
    $found || out+="❌ Belum ada server.\n\n"
    out+="Pilih server:"
    echo -e "$out"
}

# ============================================================
# Kirim info akun
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
