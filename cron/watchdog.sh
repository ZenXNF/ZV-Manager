#!/bin/bash
# ============================================================
#   ZV-Manager - Watchdog Service Monitor
#   Cron: tiap 5 menit
#   - Cek semua service penting
#   - Auto-restart kalau mati
#   - Notif Telegram ke admin HANYA saat ada yang di-restart
#   - Tidak spam kalau service memang terus mati (cooldown 30 menit)
# ============================================================

source /etc/zv-manager/core/telegram.sh
tg_load 2>/dev/null || true

LOG="/var/log/zv-manager/watchdog.log"
STATE_DIR="/tmp/zv-watchdog"
mkdir -p "$STATE_DIR"

# Daftar service yang dipantau: "nama_service|nama_tampil"
SERVICES=(
    "ssh|OpenSSH"
    "dropbear|Dropbear"
    "nginx|Nginx"
    "xray|Xray (VMess)"
    "zv-stunnel|SSL (Stunnel)"
    "zv-wss|WebSocket"
    "zv-udp|UDP Custom"
    "zv-telegram|Telegram Bot"
)

_log() {
    echo "[$(TZ=Asia/Jakarta date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG" 2>/dev/null
}

_tg_msg() {
    local text="$1"
    [[ -z "$TG_TOKEN" || -z "$TG_ADMIN_ID" ]] && return
    printf '%b' "$text" | curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -F "chat_id=${TG_ADMIN_ID}" \
        -F "parse_mode=HTML" \
        -F "text=<-" --max-time 10 &>/dev/null
}

# Cek apakah service ini boleh dikirim notif
# (cooldown 30 menit per service agar tidak spam kalau terus mati)
_can_notify() {
    local svc="$1"
    local cooldown=1800   # 30 menit
    local state_file="${STATE_DIR}/notif_${svc}"
    local now; now=$(date +%s)

    if [[ -f "$state_file" ]]; then
        local last; last=$(cat "$state_file" 2>/dev/null)
        if (( now - last < cooldown )); then
            return 1  # masih cooldown, jangan notif
        fi
    fi

    echo "$now" > "$state_file"
    return 0
}

# ── Main check ────────────────────────────────────────────
restarted_list=""
failed_list=""

for entry in "${SERVICES[@]}"; do
    svc="${entry%%|*}"
    label="${entry##*|}"

    # Skip kalau service tidak ada di sistem (belum diinstall)
    systemctl list-units --type=service --all 2>/dev/null | grep -q "${svc}.service" || continue

    if ! systemctl is-active --quiet "$svc" 2>/dev/null; then
        _log "DOWN: $svc — mencoba restart..."

        systemctl restart "$svc" &>/dev/null
        sleep 3

        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            _log "RECOVERED: $svc berhasil di-restart"
            restarted_list="${restarted_list}✅ <b>${label}</b> — mati lalu berhasil di-restart\n"
        else
            _log "FAILED: $svc gagal restart"
            failed_list="${failed_list}❌ <b>${label}</b> — gagal restart!\n"
        fi
    fi
done

# ── Kirim notif hanya kalau ada yang bermasalah ──────────
if [[ -n "$restarted_list" || -n "$failed_list" ]]; then
    # Susun isi pesan
    now_wib=$(TZ=Asia/Jakarta date "+%d %b %Y %H:%M")
    body="🔧 <b>Watchdog Alert</b>\n━━━━━━━━━━━━━━━━━━━\n📅 ${now_wib} WIB\n━━━━━━━━━━━━━━━━━━━\n"

    [[ -n "$restarted_list" ]] && body="${body}${restarted_list}"
    [[ -n "$failed_list"    ]] && body="${body}${failed_list}"

    body="${body}━━━━━━━━━━━━━━━━━━━"

    # Cek cooldown — kirim hanya kalau ada service baru yang perlu dinotif
    # (Kalau semua service yang bermasalah masih dalam cooldown, skip)
    should_send=false
    for entry in "${SERVICES[@]}"; do
        svc="${entry%%|*}"
        if ! systemctl is-active --quiet "$svc" 2>/dev/null || \
           echo "$restarted_list$failed_list" | grep -qi "${entry##*|}"; then
            if _can_notify "$svc"; then
                should_send=true
                break
            fi
        fi
    done

    if [[ "$should_send" == true ]]; then
        _tg_msg "$body"
        _log "NOTIF: Pesan dikirim ke admin TG"
    else
        _log "NOTIF: Masih cooldown, skip kirim TG"
    fi
fi
