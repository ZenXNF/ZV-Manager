#!/bin/bash
# ============================================================
#   ZV-Manager - Full Backup Harian
#   Jalan tiap hari jam 02:00
#   Backup brain VPS + semua remote VPS → kirim ke Telegram admin
# ============================================================

source /etc/zv-manager/core/telegram.sh
source /etc/zv-manager/utils/colors.sh 2>/dev/null
source /etc/zv-manager/utils/logger.sh 2>/dev/null
source /etc/zv-manager/utils/remote.sh 2>/dev/null

BASE_DIR="/etc/zv-manager"
TMP_DIR="/tmp/zv-backup-$$"
BACKUP_DIR="/var/backups/zv-manager"
DATE=$(TZ="Asia/Jakarta" date +"%Y-%m-%d_%H-%M")
BACKUP_FILE="${BACKUP_DIR}/zv-backup-${DATE}.tar.gz"

mkdir -p "$TMP_DIR" "$BACKUP_DIR"

# ── Fungsi kirim file ke Telegram ─────────────────────────
_tg_send_file() {
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

# ── Fungsi kirim pesan ─────────────────────────────────────
_tg_msg() {
    tg_load || return
    local text="$1"
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -d "chat_id=${TG_ADMIN_ID}" \
        -d "text=${text}" \
        -d "parse_mode=HTML" \
        --max-time 10 &>/dev/null
}

# ── Backup brain VPS ───────────────────────────────────────
backup_brain() {
    local dst="${TMP_DIR}/brain"
    mkdir -p "$dst"

    # Data akun & user
    [[ -d "${BASE_DIR}/accounts" ]] && cp -r "${BASE_DIR}/accounts" "$dst/"

    # Data server
    [[ -d "${BASE_DIR}/servers" ]] && cp -r "${BASE_DIR}/servers" "$dst/"

    # Config penting (tanpa SSL private key dikirim terpisah)
    for f in telegram.conf config.conf license.info; do
        [[ -f "${BASE_DIR}/${f}" ]] && cp "${BASE_DIR}/${f}" "$dst/"
    done

    # SSL cert (bukan key — key sensitif)
    mkdir -p "${dst}/ssl"
    [[ -f "${BASE_DIR}/ssl/cert.pem" ]] && cp "${BASE_DIR}/ssl/cert.pem" "${dst}/ssl/"

    # Log transaksi (100 baris terakhir)
    local logf="/var/log/zv-manager/bot.log"
    [[ -f "$logf" ]] && tail -n 100 "$logf" > "${dst}/bot-log-tail.txt"
}

# ── Backup remote VPS (passwd + shadow) ───────────────────
backup_remote() {
    [[ ! -d "${BASE_DIR}/servers" ]] && return
    local srv_dir="${TMP_DIR}/remote-servers"
    mkdir -p "$srv_dir"

    for conf in "${BASE_DIR}/servers"/*.conf; do
        [[ -f "$conf" ]] || continue
        local sname; sname=$(basename "$conf" .conf)
        local srv_dst="${srv_dir}/${sname}"
        mkdir -p "$srv_dst"

        # Ambil info server
        unset IP PORT USER PASS AUTH_TYPE SSH_KEY_PATH
        source "$conf"

        # Ambil /etc/passwd dan /etc/shadow via SSH
        local ssh_opts="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=no"
        local ok=true

        if [[ "${AUTH_TYPE}" == "key" && -f "${SSH_KEY_PATH}" ]]; then
            ssh -i "$SSH_KEY_PATH" $ssh_opts -p "${PORT:-22}" "${USER:-root}@${IP}" \
                "cat /etc/passwd" > "${srv_dst}/passwd" 2>/dev/null || ok=false
            ssh -i "$SSH_KEY_PATH" $ssh_opts -p "${PORT:-22}" "${USER:-root}@${IP}" \
                "cat /etc/shadow" > "${srv_dst}/shadow" 2>/dev/null || ok=false
        else
            sshpass -p "$PASS" ssh $ssh_opts -p "${PORT:-22}" "${USER:-root}@${IP}" \
                "cat /etc/passwd" > "${srv_dst}/passwd" 2>/dev/null || ok=false
            sshpass -p "$PASS" ssh $ssh_opts -p "${PORT:-22}" "${USER:-root}@${IP}" \
                "cat /etc/shadow" > "${srv_dst}/shadow" 2>/dev/null || ok=false
        fi

        [[ "$ok" == false ]] && echo "WARN: Gagal backup remote ${sname}" \
            > "${srv_dst}/backup-error.txt"
    done
}

# ── Bersihkan backup lama (simpan 7 hari) ─────────────────
cleanup_old() {
    find "$BACKUP_DIR" -name "zv-backup-*.tar.gz" -mtime +7 -delete 2>/dev/null
}

# ── Main ───────────────────────────────────────────────────
zv_log "BACKUP: Mulai backup harian..." 2>/dev/null || true

backup_brain
backup_remote

# Kompres semua
tar -czf "$BACKUP_FILE" -C "$TMP_DIR" . 2>/dev/null
rm -rf "$TMP_DIR"

# Hitung ukuran
SIZE=$(du -sh "$BACKUP_FILE" 2>/dev/null | cut -f1)

# Hitung statistik
TOTAL_AKUN=$(ls /etc/zv-manager/accounts/ssh/*.conf 2>/dev/null | wc -l)
TOTAL_USER=$(ls /etc/zv-manager/accounts/users/*.user 2>/dev/null | wc -l)
TOTAL_SERVER=$(ls /etc/zv-manager/servers/*.conf 2>/dev/null | wc -l)

# Kirim ke Telegram
CAPTION="🗄 <b>Backup Harian ZV-Manager</b>
━━━━━━━━━━━━━━━━━━━
📅 Waktu  : ${DATE}
📦 Ukuran : ${SIZE}
👤 Akun SSH  : ${TOTAL_AKUN}
👥 User Bot  : ${TOTAL_USER}
🖥 Server    : ${TOTAL_SERVER}
━━━━━━━━━━━━━━━━━━━
<i>Simpan file ini untuk restore ke VPS baru.</i>"

_tg_send_file "$BACKUP_FILE" "$CAPTION"

cleanup_old

zv_log "BACKUP: Selesai. File: ${BACKUP_FILE} (${SIZE})" 2>/dev/null || true
