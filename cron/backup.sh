#!/bin/bash
# ============================================================
#   ZV-Manager - Full Backup Harian
#   Jalan tiap hari jam 02:00
#   1. Backup otak (akun, config, SSL)
#   2. Backup per-server tunneling (conf akun + xray config)
#   3. Kirim semua ke Telegram admin
#   4. Hapus file backup realtime (.conf individual)
# ============================================================

source /etc/zv-manager/core/telegram.sh
source /etc/zv-manager/utils/logger.sh 2>/dev/null
source /etc/zv-manager/utils/remote.sh 2>/dev/null

BASE_DIR="/etc/zv-manager"
TMP_DIR="/tmp/zv-backup-$$"
BACKUP_DIR="/var/backups/zv-manager"
REALTIME_DIR="/var/backups/zv-manager/realtime"
DATE=$(TZ="Asia/Jakarta" date +"%Y-%m-%d_%H-%M")
mkdir -p "$TMP_DIR" "$BACKUP_DIR"

# ── Kirim file ke Telegram ─────────────────────────────────
_tg_file() {
    local file="$1" caption="$2"
    tg_load || return 1
    [[ -f "$file" ]] || return 1
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendDocument" \
        -F "chat_id=${TG_ADMIN_ID}" \
        -F "document=@${file}" \
        -F "caption=${caption}" \
        -F "parse_mode=HTML" \
        --max-time 60 &>/dev/null
}

_tg_msg() {
    tg_load || return
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -d "chat_id=${TG_ADMIN_ID}" \
        -d "text=$1" \
        -d "parse_mode=HTML" \
        --max-time 10 &>/dev/null
}

# ── Format ukuran file (bytes → B/KB/MB) ──────────────────
_fmt_size() {
    local bytes
    bytes=$(stat -c%s "$1" 2>/dev/null || echo 0)
    if   [[ $bytes -ge 1048576 ]]; then printf "%.1f MB" "$(echo "scale=1; $bytes/1048576" | bc)"
    elif [[ $bytes -ge 1024    ]]; then printf "%.1f KB" "$(echo "scale=1; $bytes/1024" | bc)"
    else printf "%d B" "$bytes"
    fi
}

# ── 1. Backup Otak ─────────────────────────────────────────
# Yang di-backup:
# - accounts/ssh/*.conf   → USERNAME, PASSWORD, EXPIRED → recreate akun Linux
# - accounts/vmess/*.conf → USERNAME, UUID, EXPIRED, BW → inject ke Xray baru
# - accounts/saldo/       → saldo user bot
# - accounts/users/       → data user bot
# - telegram.conf         → token bot, admin ID
# - config.conf           → config global
# - license.info          → lisensi
# - ssl/cert.pem + key    → berguna jika domain sama setelah suspend
# - domain, web-host      → info domain otak VPS
# - servers/*.conf        → HANYA NAME+DOMAIN+ISP (strip IP/PORT/USER/PASS yang tidak valid)
# TIDAK di-backup: log (tidak berguna untuk restore)
backup_otak() {
    local dst="${TMP_DIR}/otak"
    mkdir -p "$dst"

    # Akun semua — paling penting untuk restore
    [[ -d "${BASE_DIR}/accounts" ]] && cp -r "${BASE_DIR}/accounts" "$dst/"

    # Server conf — strip IP/PORT/USER/PASS, simpan NAME/DOMAIN/ISP/TYPE saja
    if [[ -d "${BASE_DIR}/servers" ]]; then
        mkdir -p "${dst}/servers"
        for sc in "${BASE_DIR}/servers"/*.conf; do
            [[ -f "$sc" ]] || continue
            local fname; fname=$(basename "$sc")
            # Salin hanya field yang masih berguna setelah suspend
            grep -E "^(NAME|DOMAIN|ISP|AUTH_TYPE|TG_SERVER_TYPE)=" "$sc" \
                > "${dst}/servers/${fname}" 2>/dev/null
            echo "# IP/PORT/USER/PASS tidak disimpan (tidak valid setelah suspend)" \
                >> "${dst}/servers/${fname}"
        done
        # Salin .tg.conf apa adanya (berisi label, max akun, dll — tidak ada IP/PASS)
        for tgsc in "${BASE_DIR}/servers"/*.tg.conf; do
            [[ -f "$tgsc" ]] || continue
            cp "$tgsc" "${dst}/servers/"
        done
        cat > "${dst}/servers/RESTORE-NOTE.txt" << 'NOTETXT'
CATATAN RESTORE SERVER:
- File .conf di sini hanya menyimpan NAME, DOMAIN, ISP sebagai referensi.
- IP, PORT, USER, PASS tidak disimpan karena tidak valid setelah VPS suspend/ganti.
- Saat restore ke VPS baru:
  1. Tambah server baru via Menu Server → Tambah Server (IP/PASS baru)
  2. Gunakan DOMAIN lama atau ganti domain di sini
  3. Recreate akun SSH dari ssh-accounts/ di backup server (username+pass sama)
  4. Recreate akun VMess dari vmess-accounts/ di backup server (UUID sama)
NOTETXT
    fi

    # Config utama
    for f in telegram.conf config.conf license.info; do
        [[ -f "${BASE_DIR}/${f}" ]] && cp "${BASE_DIR}/${f}" "$dst/"
    done

    # SSL cert + key (berguna jika domain sama setelah suspend)
    mkdir -p "${dst}/ssl"
    [[ -f "${BASE_DIR}/ssl/cert.pem" ]] && cp "${BASE_DIR}/ssl/cert.pem" "${dst}/ssl/"
    [[ -f "${BASE_DIR}/ssl/key.pem"  ]] && cp "${BASE_DIR}/ssl/key.pem"  "${dst}/ssl/"

    # Domain config + banner
    [[ -f "${BASE_DIR}/web-host"    ]] && cp "${BASE_DIR}/web-host"    "$dst/"
    [[ -f "${BASE_DIR}/domain"      ]] && cp "${BASE_DIR}/domain"      "$dst/"
    [[ -f "${BASE_DIR}/banner.conf" ]] && cp "${BASE_DIR}/banner.conf" "$dst/"
}

# ── 2. Backup per-server tunneling ─────────────────────────
# Isi: conf akun SSH+VMess (dari brain) + xray config.json (dari remote)
# TIDAK di-backup: passwd/shadow Linux (tidak berguna, VPS baru = OS baru)
# DOMAIN di conf akun tidak diubah — user tinggal ganti domain via bot
backup_server() {
    local sname="$1"
    local conf="${BASE_DIR}/servers/${sname}.conf"
    [[ -f "$conf" ]] || return

    unset IP PORT USER PASS AUTH_TYPE SSH_KEY_PATH NAME DOMAIN ISP
    source "$conf"

    local dst="${TMP_DIR}/ssh-${sname}"
    mkdir -p "$dst"

    # Simpan info referensi server (bukan credential)
    local backup_date; backup_date=$(TZ="Asia/Jakarta" date +"%Y-%m-%d %H:%M WIB")
    cat > "${dst}/server-info.txt" << SRVTXT
============================
  ZV-Manager Server Backup
============================
SERVER  : ${sname}
DOMAIN  : ${DOMAIN:-?}
ISP     : ${ISP:-?}
TANGGAL : ${backup_date}
SSH     : ${ssh_count} akun
VMESS   : ${vmess_count} akun
SRVTXT

    # Conf akun SSH yang terkait server ini
    local ssh_count=0
    mkdir -p "${dst}/ssh-accounts"
    for ac in "${BASE_DIR}/accounts/ssh"/*.conf; do
        [[ -f "$ac" ]] || continue
        local srv; srv=$(grep "^SERVER=" "$ac" | cut -d= -f2 | tr -d '"')
        if [[ "$srv" == "$sname" ]]; then
            cp "$ac" "${dst}/ssh-accounts/"
            ssh_count=$((ssh_count + 1))
        fi
    done

    # Conf akun VMess yang terkait server ini
    local vmess_count=0
    mkdir -p "${dst}/vmess-accounts"
    for vc in "${BASE_DIR}/accounts/vmess"/*.conf; do
        [[ -f "$vc" ]] || continue
        local srv; srv=$(grep "^SERVER=" "$vc" | cut -d= -f2 | tr -d '"')
        if [[ "$srv" == "$sname" ]]; then
            cp "$vc" "${dst}/vmess-accounts/"
            vmess_count=$((vmess_count + 1))
        fi
    done

    # Ambil xray config.json dari remote (berisi UUID list aktif)
    local ssh_opts="-o StrictHostKeyChecking=no -o ConnectTimeout=10"
    local ok=true
    if [[ "${AUTH_TYPE}" == "key" && -f "${SSH_KEY_PATH}" ]]; then
        ssh -i "$SSH_KEY_PATH" $ssh_opts -p "${PORT:-22}" "${USER:-root}@${IP}" \
            "cat /usr/local/etc/xray/config.json" > "${dst}/xray-config.json" 2>/dev/null || ok=false
    else
        sshpass -p "$PASS" ssh $ssh_opts -p "${PORT:-22}" "${USER:-root}@${IP}" \
            "cat /usr/local/etc/xray/config.json" > "${dst}/xray-config.json" 2>/dev/null || ok=false
    fi

    # Catatan restore
    cat > "${dst}/RESTORE-NOTE.txt" << NOTETXT
============================
  PANDUAN RESTORE SERVER
============================
Server  : ${sname}
Domain  : ${DOMAIN:-?}
ISP     : ${ISP:-?}
Dibackup: ${backup_date}

CARA RESTORE OTOMATIS (Direkomendasikan):
------------------------------------------
1. Beli VPS baru, install ZV-Manager
2. Menu Server → Tambah Server → isi IP/PASS/domain baru
   → Setelah berhasil, bot otomatis tanya "Restore dari backup?"
   → Pilih file backup ini → semua akun SSH+VMess di-push otomatis

CARA RESTORE MANUAL:
------------------------------------------
1. Menu System → Backup & Restore → [5] Restore Server Tunneling
2. Pilih file backup ini
3. Pilih server tujuan (yang baru ditambah)
4. Bot akan recreate semua akun SSH+VMess ke server baru

CATATAN:
- Domain akun diupdate otomatis ke domain server baru
- EXPIRED_TS yang sudah lewat di-extend otomatis
- UUID VMess tetap sama (tidak berubah)
- Password SSH tetap sama (tidak berubah)
NOTETXT

    [[ "$ok" == false ]] && echo "GAGAL: koneksi ke ${sname}" > "${dst}/error.txt"
    echo "${ok}|${ssh_count}|${vmess_count}"
}

# ── Bersihkan backup lama (> 7 hari) ───────────────────────
cleanup_old() {
    find "$BACKUP_DIR" -name "zv-backup-*.tar.gz" -mtime +7 -delete 2>/dev/null
    find "$BACKUP_DIR" -name "zv-ssh-*.tar.gz"    -mtime +7 -delete 2>/dev/null
}

# ── Hapus file realtime setelah backup full selesai ─────────
cleanup_realtime() {
    [[ -d "$REALTIME_DIR" ]] && rm -f "${REALTIME_DIR}"/*.conf 2>/dev/null
    find "$BACKUP_DIR" -name "*.conf" -mtime +1 -delete 2>/dev/null
}

# ══════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════
zv_log "BACKUP: Mulai backup harian..." 2>/dev/null || true

TOTAL_SSH=$(ls "${BASE_DIR}/accounts/ssh/"*.conf 2>/dev/null | wc -l)
TOTAL_VMESS=$(ls "${BASE_DIR}/accounts/vmess/"*.conf 2>/dev/null | wc -l)
TOTAL_USER=$(ls "${BASE_DIR}/accounts/users/"*.user 2>/dev/null | wc -l)
TOTAL_SRV=$(ls "${BASE_DIR}/servers/"*.conf 2>/dev/null | grep -v "\.tg\.conf" | wc -l)

NOW=$(TZ="Asia/Jakarta" date +"%Y-%m-%d %H:%M")
_tg_msg "🗄 <b>Backup Harian Dimulai</b>
━━━━━━━━━━━━━━━━━━━
📅 Waktu      : ${NOW} WIB
🔑 Akun SSH   : ${TOTAL_SSH}
⚡ Akun VMess : ${TOTAL_VMESS}
👥 User Bot   : ${TOTAL_USER}
🖥 Server     : ${TOTAL_SRV}
━━━━━━━━━━━━━━━━━━━
<i>Mengirim file backup...</i>"

# ── Backup & kirim otak ─────────────────────────────────────
backup_otak
OTAK_FILE="${BACKUP_DIR}/zv-backup-otak-${DATE}.tar.gz"
tar -czf "$OTAK_FILE" -C "${TMP_DIR}/otak" . 2>/dev/null
OTAK_SIZE=$(_fmt_size "$OTAK_FILE")

_tg_file "$OTAK_FILE" "🧠 <b>Backup Otak VPS</b>
━━━━━━━━━━━━━━━━━━━
📅 ${DATE}
📦 Ukuran     : ${OTAK_SIZE}
🔑 Akun SSH   : ${TOTAL_SSH}
⚡ Akun VMess : ${TOTAL_VMESS}
👥 User Bot   : ${TOTAL_USER}
━━━━━━━━━━━━━━━━━━━
<i>Berisi: akun SSH+VMess, saldo, config, SSL</i>
<i>Server conf: hanya NAME+DOMAIN+ISP (IP/PASS tidak disimpan)</i>"

# ── Backup & kirim per-server tunneling ─────────────────────
for conf in "${BASE_DIR}/servers"/*.conf; do
    [[ -f "$conf" ]] || continue
    [[ "$conf" == *.tg.conf ]] && continue
    sname=$(basename "$conf" .conf)

    result=$(backup_server "$sname")
    ok=$(echo "$result" | cut -d'|' -f1)
    ssh_c=$(echo "$result" | cut -d'|' -f2)
    vmess_c=$(echo "$result" | cut -d'|' -f3)

    SRV_FILE="${BACKUP_DIR}/zv-ssh-${sname}-${DATE}.tar.gz"
    tar -czf "$SRV_FILE" -C "${TMP_DIR}/ssh-${sname}" . 2>/dev/null
    SRV_SIZE=$(_fmt_size "$SRV_FILE")

    if [[ "$ok" == "true" ]]; then
        STATUS="✅ Berhasil"
    else
        STATUS="⚠️ Gagal konek (xray config tidak terambil)"
    fi

    _tg_file "$SRV_FILE" "🖥 <b>Backup Server: ${sname}</b>
━━━━━━━━━━━━━━━━━━━
📅 ${DATE}
📦 Ukuran     : ${SRV_SIZE}
🔑 Akun SSH   : ${ssh_c}
⚡ Akun VMess : ${vmess_c}
📊 Status     : ${STATUS}
━━━━━━━━━━━━━━━━━━━
<i>Berisi: conf akun SSH+VMess, xray UUID config</i>
<i>Ganti domain saja saat restore, user+UUID tetap sama</i>"
done

rm -rf "$TMP_DIR"

cleanup_realtime
cleanup_old

zv_log "BACKUP: Selesai. Otak: ${OTAK_SIZE}" 2>/dev/null || true
