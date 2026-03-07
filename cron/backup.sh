#!/bin/bash
# ============================================================
#   ZV-Manager - Full Backup Harian
#   Jalan tiap hari jam 02:00
#   1. Backup otak (semua data)
#   2. Backup per-server SSH (passwd + shadow)
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

# ── 1. Backup Otak ────────────────────────────────────────
backup_otak() {
    local dst="${TMP_DIR}/otak"
    mkdir -p "$dst"
    [[ -d "${BASE_DIR}/accounts" ]] && cp -r "${BASE_DIR}/accounts" "$dst/"
    [[ -d "${BASE_DIR}/servers"  ]] && cp -r "${BASE_DIR}/servers"  "$dst/"
    for f in telegram.conf config.conf license.info; do
        [[ -f "${BASE_DIR}/${f}" ]] && cp "${BASE_DIR}/${f}" "$dst/"
    done
    mkdir -p "${dst}/ssl"
    [[ -f "${BASE_DIR}/ssl/cert.pem" ]] && cp "${BASE_DIR}/ssl/cert.pem" "${dst}/ssl/"
    local logf="/var/log/zv-manager/bot.log"
    [[ -f "$logf" ]] && tail -n 200 "$logf" > "${dst}/bot-log-tail.txt"
}

# ── 2. Backup per-server SSH ──────────────────────────────
backup_server() {
    local sname="$1"
    local conf="${BASE_DIR}/servers/${sname}.conf"
    [[ -f "$conf" ]] || return

    unset IP PORT USER PASS AUTH_TYPE SSH_KEY_PATH
    source "$conf"

    local dst="${TMP_DIR}/ssh-${sname}"
    mkdir -p "$dst"
    cp "$conf" "${dst}/server.conf"

    local ssh_opts="-o StrictHostKeyChecking=no -o ConnectTimeout=10"
    local ok=true

    if [[ "${AUTH_TYPE}" == "key" && -f "${SSH_KEY_PATH}" ]]; then
        ssh -i "$SSH_KEY_PATH" $ssh_opts -p "${PORT:-22}" "${USER:-root}@${IP}"             "cat /etc/passwd" > "${dst}/passwd" 2>/dev/null || ok=false
        ssh -i "$SSH_KEY_PATH" $ssh_opts -p "${PORT:-22}" "${USER:-root}@${IP}"             "cat /etc/shadow" > "${dst}/shadow" 2>/dev/null || ok=false
    else
        sshpass -p "$PASS" ssh $ssh_opts -p "${PORT:-22}" "${USER:-root}@${IP}"             "cat /etc/passwd" > "${dst}/passwd" 2>/dev/null || ok=false
        sshpass -p "$PASS" ssh $ssh_opts -p "${PORT:-22}" "${USER:-root}@${IP}"             "cat /etc/shadow" > "${dst}/shadow" 2>/dev/null || ok=false
    fi

    [[ "$ok" == false ]] && echo "GAGAL: koneksi ke ${sname}" > "${dst}/error.txt"
    echo "$ok"
}

# ── Bersihkan backup lama (> 7 hari) ──────────────────────
cleanup_old() {
    find "$BACKUP_DIR" -name "zv-backup-*.tar.gz" -mtime +7 -delete 2>/dev/null
    find "$BACKUP_DIR" -name "zv-ssh-*.tar.gz"    -mtime +7 -delete 2>/dev/null
}

# ── Hapus file realtime setelah backup full selesai ────────
cleanup_realtime() {
    [[ -d "$REALTIME_DIR" ]] && rm -f "${REALTIME_DIR}"/*.conf 2>/dev/null
    # Hapus juga notif realtime lama di backup dir
    find "$BACKUP_DIR" -name "*.conf" -mtime +1 -delete 2>/dev/null
}

# ══════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════
zv_log "BACKUP: Mulai backup harian..." 2>/dev/null || true

# Kirim header notif
TOTAL_AKUN=$(ls /etc/zv-manager/accounts/ssh/*.conf 2>/dev/null | wc -l)
TOTAL_USER=$(ls /etc/zv-manager/accounts/users/*.user 2>/dev/null | wc -l)
TOTAL_SRV=$(ls /etc/zv-manager/servers/*.conf 2>/dev/null | wc -l)

_tg_msg "🗄 <b>Backup Harian Dimulai</b>
━━━━━━━━━━━━━━━━━━━
📅 Waktu     : $(TZ=\"Asia/Jakarta\" date +\"%Y-%m-%d %H:%M\") WIB
👤 Akun SSH  : ${TOTAL_AKUN}
👥 User Bot  : ${TOTAL_USER}
🖥 Server    : ${TOTAL_SRV}
━━━━━━━━━━━━━━━━━━━
<i>Mengirim file backup...</i>"

# ── Backup & kirim otak ────────────────────────────────────
backup_otak
OTAK_FILE="${BACKUP_DIR}/zv-backup-otak-${DATE}.tar.gz"
tar -czf "$OTAK_FILE" -C "${TMP_DIR}/otak" . 2>/dev/null
OTAK_SIZE=$(du -sh "$OTAK_FILE" | cut -f1)

_tg_file "$OTAK_FILE" "🧠 <b>Backup Otak VPS</b>
━━━━━━━━━━━━━━━━━━━
📅 ${DATE}
📦 Ukuran : ${OTAK_SIZE}
👤 Akun SSH  : ${TOTAL_AKUN}
👥 User Bot  : ${TOTAL_USER}
━━━━━━━━━━━━━━━━━━━
<i>Berisi: akun, saldo, config, server list, SSL</i>"

# ── Backup & kirim per-server SSH ─────────────────────────
for conf in "${BASE_DIR}/servers"/*.conf; do
    [[ -f "$conf" ]] || continue
    # Skip file .tg.conf — bukan server config
    [[ "$conf" == *.tg.conf ]] && continue
    sname=$(basename "$conf" .conf)

    result=$(backup_server "$sname")

    SRV_FILE="${BACKUP_DIR}/zv-ssh-${sname}-${DATE}.tar.gz"
    tar -czf "$SRV_FILE" -C "${TMP_DIR}/ssh-${sname}" . 2>/dev/null
    SRV_SIZE=$(du -sh "$SRV_FILE" | cut -f1)

    # Hitung jumlah user SSH di server ini
    USR_COUNT=$(grep -c "^" "${TMP_DIR}/ssh-${sname}/passwd" 2>/dev/null || echo "?")

    if [[ "$result" == "true" ]]; then
        STATUS="✅ Berhasil"
    else
        STATUS="⚠️ Gagal konek (file mungkin kosong)"
    fi

    _tg_file "$SRV_FILE" "🖥 <b>Backup Server SSH: ${sname}</b>
━━━━━━━━━━━━━━━━━━━
📅 ${DATE}
📦 Ukuran   : ${SRV_SIZE}
👥 User     : ${USR_COUNT} akun Linux
📊 Status   : ${STATUS}
━━━━━━━━━━━━━━━━━━━
<i>Berisi: passwd, shadow, server config</i>
<i>Gunakan untuk restore ke VPS baru jika suspend</i>"
done

rm -rf "$TMP_DIR"

# ── Hapus realtime + backup lama ──────────────────────────
cleanup_realtime
cleanup_old

zv_log "BACKUP: Selesai. Otak: ${OTAK_SIZE}" 2>/dev/null || true
