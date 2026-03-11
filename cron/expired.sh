#!/bin/bash
# ============================================================
#   ZV-Manager - Auto Delete Expired Users
#   Dipanggil via cron setiap hari jam 00:02
#   Menghapus akun expired di lokal + semua remote server
#   + Kirim notifikasi Telegram ke user
# ============================================================

source /etc/zv-manager/core/telegram.sh
source /etc/zv-manager/core/bandwidth.sh
tg_load 2>/dev/null || true

LOG="/var/log/zv-manager/install.log"
today=$(date +"%Y-%m-%d")

_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG" 2>/dev/null
}

_tg_send() {
    local chat_id="$1" text="$2"
    [[ -z "$TG_TOKEN" || -z "$chat_id" ]] && return
    printf '%b' "$text" | curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -F "chat_id=${chat_id}" \
        -F "parse_mode=HTML" \
        -F "text=<-" --max-time 10 &>/dev/null
}

# Kirim notif ke user bahwa akun dihapus
_notify_deleted() {
    local tg_uid="$1" username="$2" server="$3"
    _tg_send "$tg_uid" "🗑️ <b>Akun Dihapus</b>\n\nUsername : <code>${username}</code>\nServer   : ${server}\n\nAkun kamu sudah expired dan telah dihapus otomatis.\nBuat akun baru atau perpanjang lewat bot."
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
            rm -f "/etc/zv-manager/accounts/notified/${USERNAME}.bw_warn"
            # Cleanup iptables chain bandwidth
            _bw_cleanup_user "$USERNAME" 2>/dev/null
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
                    rm -f "/etc/zv-manager/accounts/notified/${r_user}.bw_warn"
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
# VMESS: hapus akun VMess expired (lokal + remote via agent)
# ============================================================
_sweep_vmess() {
    local vmess_dir="/etc/zv-manager/accounts/vmess"
    [[ -d "$vmess_dir" ]] || return
    source /etc/zv-manager/utils/remote.sh 2>/dev/null
    local count=0
    local now_ts; now_ts=$(date +%s)
    for conf_file in "$vmess_dir"/*.conf; do
        [[ -f "$conf_file" ]] || continue
        unset USERNAME EXPIRED_TS TG_USER_ID IS_TRIAL SERVER
        source "$conf_file"
        [[ -z "$EXPIRED_TS" ]] && continue
        if [[ "$EXPIRED_TS" -lt "$now_ts" ]]; then
            local sname="${SERVER:-local}"
            # Hapus dari Xray via agent (lokal/remote)
            local result
            result=$(remote_vmess_agent "$sname" del "$USERNAME" 2>/dev/null)
            _log "VMESS [$sname]: Auto-deleted expired: $USERNAME ($result)"
            # Hapus conf lokal di brain
            rm -f "$conf_file"
            rm -f "/tmp/zv-tg-state/vmess_${USERNAME}.notified"
            # Notif ke user (hanya akun premium)
            if [[ "$IS_TRIAL" != "1" && -n "$TG_USER_ID" && "$TG_USER_ID" != "0" ]]; then
                _tg_send "$TG_USER_ID" "🗑️ <b>Akun VMess Dihapus</b>

Username : <code>${USERNAME}</code>
Server   : ${sname}

Akun VMess kamu sudah expired dan telah dihapus otomatis.
Buat akun baru lewat bot."
            fi
            count=$((count + 1))
        fi
    done
    [[ $count -gt 0 ]] && _log "VMESS: Total dihapus: $count akun"
}

# ============================================================
# Main
# ============================================================
_log "=== Mulai cron expired sweep ==="
_sweep_local
_sweep_remote
_sweep_vmess

_log "=== Selesai ==="
