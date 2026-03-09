#!/bin/bash
# ============================================================
#   ZV-Manager - Backup Real-time (per transaksi)
#   Dipanggil dari bot.py setelah akun baru dibuat/diubah
#   Hanya kirim file .conf akun yang baru — ringan & cepat
# ============================================================

source /etc/zv-manager/core/telegram.sh

ACCOUNT_DIR="/etc/zv-manager/accounts/ssh"
VMESS_DIR="/etc/zv-manager/accounts/vmess"
SALDO_DIR="/etc/zv-manager/accounts/saldo"

# Argumen: username akun yang baru dibuat/diubah
USERNAME="$1"
ACTION="${2:-update}"   # create / renew / edit / delete
PROTO="${3:-ssh}"       # ssh / vmess

[[ -z "$USERNAME" ]] && exit 0
tg_load || exit 0

# Pilih direktori conf berdasarkan protokol
if [[ "$PROTO" == "vmess" ]]; then
    CONF="${VMESS_DIR}/${USERNAME}.conf"
    PROTO_LABEL="VMess"
else
    CONF="${ACCOUNT_DIR}/${USERNAME}.conf"
    PROTO_LABEL="SSH"
fi

_tg_send_doc() {
    local file="$1" caption="$2"
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendDocument" \
        -F "chat_id=${TG_ADMIN_ID}" \
        -F "document=@${file}" \
        -F "caption=${caption}" \
        -F "parse_mode=HTML" \
        --max-time 30 &>/dev/null
}

_tg_msg() {
    local text="$1"
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -d "chat_id=${TG_ADMIN_ID}" \
        -d "text=${text}" \
        -d "parse_mode=HTML" \
        --max-time 10 &>/dev/null
}

DATE=$(TZ="Asia/Jakarta" date +"%Y-%m-%d %H:%M")

# Untuk delete — hanya kirim notif, file sudah tidak ada
if [[ "$ACTION" == "delete" ]]; then
    _tg_msg "🗑 <b>Backup Notif: ${PROTO_LABEL} Dihapus</b>
━━━━━━━━━━━━━━━━━━━
👤 Username : <code>${USERNAME}</code>
📅 Waktu    : ${DATE}
━━━━━━━━━━━━━━━━━━━
<i>Akun telah dihapus dari sistem.</i>"
    exit 0
fi

# Untuk create/renew/edit — kirim file .conf
[[ ! -f "$CONF" ]] && exit 0

# Baca saldo user (kalau ada TG_USER_ID)
unset TG_USER_ID EXPIRED EXPIRED_TS LIMIT SERVER
source "$CONF" 2>/dev/null

# VMess pakai EXPIRED_TS (unix timestamp), SSH pakai EXPIRED (date string)
if [[ -z "$EXPIRED" && -n "$EXPIRED_TS" && "$EXPIRED_TS" =~ ^[0-9]+$ ]]; then
    EXPIRED=$(date -d "@${EXPIRED_TS}" "+%Y-%m-%d" 2>/dev/null || \
              python3 -c "import datetime; print(datetime.datetime.fromtimestamp(${EXPIRED_TS}).strftime('%Y-%m-%d'))" 2>/dev/null)
fi

SALDO="0"
[[ -n "$TG_USER_ID" && -f "${SALDO_DIR}/${TG_USER_ID}.saldo" ]] && \
    SALDO=$(cat "${SALDO_DIR}/${TG_USER_ID}.saldo" | tr -d '[:space:]')
SALDO="${SALDO#SALDO=}"
[[ ! "$SALDO" =~ ^[0-9]+$ ]] && SALDO="0"

ACTION_LABEL="Dibuat"
ACTION_ICON="🆕"
[[ "$ACTION" == "renew" ]] && ACTION_LABEL="Diperpanjang" && ACTION_ICON="🔄"
[[ "$ACTION" == "edit"  ]] && ACTION_LABEL="Diedit"       && ACTION_ICON="✏️"

CAPTION="${ACTION_ICON} <b>Backup Real-time: ${PROTO_LABEL} ${ACTION_LABEL}</b>
━━━━━━━━━━━━━━━━━━━
👤 Username : <code>${USERNAME}</code>
📅 Expired  : ${EXPIRED:-?}
🖥 Server   : ${SERVER:-local}
📅 Waktu    : ${DATE}
━━━━━━━━━━━━━━━━━━━
<i>File conf ini untuk restore akun jika VPS suspend.</i>"

_tg_send_doc "$CONF" "$CAPTION"
