#!/bin/bash
# ============================================================
#   ZV-Manager - Auto Delete Expired Users
#   Dipanggil via cron setiap hari jam 00:02
#   Menghapus akun expired di lokal + semua remote server
#   + Kirim notifikasi Telegram ke user
# ============================================================

source /etc/zv-manager/core/telegram.sh
tg_load 2>/dev/null || true

LOG="/var/log/zv-manager/install.log"
today=$(date +"%Y-%m-%d")

_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG" 2>/dev/null
}

# Kirim notif ke user bahwa akun dihapus
_notify_deleted() {
    local tg_uid="$1" username="$2" server="$3"
    [[ -z "$tg_uid" || -z "$TG_TOKEN" ]] && return
    local jfile; jfile=$(mktemp)
    python3 - "$tg_uid" "$username" "$server" > "$jfile" << 'PYINLINE'
import json, sys
uid, user, srv = sys.argv[1], sys.argv[2], sys.argv[3]
text = (
    "🗑️ <b>Akun Dihapus</b>\n\n"
    f"Username : <code>{user}</code>\n"
    f"Server   : {srv}\n\n"
    "Akun kamu sudah expired dan telah dihapus otomatis.\n"
    "Buat akun baru atau perpanjang lewat bot."
)
print(json.dumps({"chat_id": uid, "text": text, "parse_mode": "HTML"}))
PYINLINE
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage"         -H "Content-Type: application/json"         -d "@${jfile}" --max-time 10 &>/dev/null
    rm -f "$jfile"
}

# ============================================================
# LOCAL: hapus akun expired di VPS ini
# ============================================================
_sweep_local() {
    local count=0
    for conf_file in /etc/zv-manager/accounts/ssh/*.conf; do
        [[ -f "$conf_file" ]] || continue
        unset USERNAME EXPIRED
        source "$conf_file"

        if [[ "$EXPIRED" < "$today" ]]; then
            local tg_uid_del; tg_uid_del=$(grep "^TG_USER_ID=" "$conf_file" | cut -d= -f2 | tr -d "[:space:]")
            local server_del; server_del=$(grep "^SERVER=" "$conf_file" | cut -d= -f2 | tr -d "[:space:]")
            # Hapus file notified agar slot bersih
            rm -f "/etc/zv-manager/accounts/notified/${USERNAME}.notified"
            pkill -u "$USERNAME" &>/dev/null
            userdel -r "$USERNAME" &>/dev/null 2>&1
            rm -f "$conf_file"
            _notify_deleted "$tg_uid_del" "$USERNAME" "$server_del"
            _log "LOCAL: Auto-deleted expired user: $USERNAME (expired: $EXPIRED)"
            count=$((count + 1))
        fi
    done
    [[ $count -gt 0 ]] && _log "LOCAL: Total dihapus: $count akun"
}

# ============================================================
# REMOTE: sweep via zv-agent ke semua server terdaftar
# ============================================================
_sweep_remote() {
    local server_dir="/etc/zv-manager/servers"
    [[ -d "$server_dir" ]] || return

    # Pastikan sshpass tersedia
    if ! command -v sshpass &>/dev/null; then
        apt-get install -y sshpass &>/dev/null
    fi

    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=no"
    local local_ip
    local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null)

    for conf in "$server_dir"/*.conf; do
        [[ -f "$conf" ]] || continue
        unset NAME IP PORT USER PASS
        source "$conf"

        # Skip lokal
        [[ "$IP" == "$local_ip" ]] && continue

        _log "REMOTE [$NAME]: Mulai sweep expired..."

        # Ambil list akun dari remote
        local raw
        raw=$(sshpass -p "$PASS" ssh $ssh_opts -p "$PORT" "${USER}@${IP}" \
            "zv-agent list" 2>&1)

        # Skip jika agent belum diinstall atau koneksi gagal
        if echo "$raw" | grep -qi "command not found\|not found\|Connection refused\|No route"; then
            _log "REMOTE [$NAME]: Skip — agent tidak tersedia atau koneksi gagal"
            continue
        fi

        [[ "$raw" == "LIST-EMPTY" || -z "$raw" ]] && {
            _log "REMOTE [$NAME]: Tidak ada akun, skip"
            continue
        }

        local count=0
        while IFS='|' read -r r_user r_pass r_limit r_exp r_created; do
            [[ -z "$r_user" ]] && continue

            if [[ "$r_exp" < "$today" ]]; then
                local result
                result=$(sshpass -p "$PASS" ssh $ssh_opts -p "$PORT" "${USER}@${IP}" \
                    "zv-agent del $r_user" 2>&1)

                if [[ "$result" == DEL-OK* ]]; then
                    # Cari TG_USER_ID dari conf lokal kalau ada
                    local r_tg_uid=""
                    local r_conf="/etc/zv-manager/accounts/ssh/${r_user}.conf"
                    [[ -f "$r_conf" ]] && r_tg_uid=$(grep "^TG_USER_ID=" "$r_conf" | cut -d= -f2 | tr -d "[:space:]")
                    [[ -n "$r_tg_uid" ]] && _notify_deleted "$r_tg_uid" "$r_user" "$NAME"
                    rm -f "/etc/zv-manager/accounts/notified/${r_user}.notified"
                    _log "REMOTE [$NAME]: Auto-deleted expired user: $r_user (expired: $r_exp)"
                    count=$((count + 1))
                else
                    _log "REMOTE [$NAME]: Gagal hapus $r_user — $result"
                fi
            fi
        done <<< "$raw"

        [[ $count -gt 0 ]] && _log "REMOTE [$NAME]: Total dihapus: $count akun"
        [[ $count -eq 0 ]] && _log "REMOTE [$NAME]: Tidak ada akun expired"
    done
}

# ============================================================
# Main
# ============================================================
_log "=== Mulai cron expired sweep ==="
_sweep_local
_sweep_remote
_log "=== Selesai ==="
