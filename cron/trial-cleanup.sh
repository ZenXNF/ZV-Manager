#!/bin/bash
# ============================================================
#   ZV-Manager - Trial Cleanup (Fallback Safety)
#   Jalankan tiap 5 menit — backup jika `at` gagal schedule
# ============================================================
source /etc/zv-manager/core/telegram.sh
tg_load 2>/dev/null || true
source /etc/zv-manager/utils/remote.sh 2>/dev/null

LOG="/var/log/zv-manager/install.log"
now_ts=$(date +%s)

_tg_notif() {
    local uid="$1" proto="$2" uname="$3"
    [[ -z "$TG_TOKEN" || -z "$uid" ]] && return
    printf '%b' "⏰ <b>Trial ${proto} Habis</b>\n\nAkun trial <code>${uname}</code> kamu sudah berakhir.\n\nMau lanjut? Buat akun premium lewat bot." | \
        curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -F "chat_id=${uid}" -F "parse_mode=HTML" -F "text=<-" --max-time 10 &>/dev/null
}

# ── SSH trial ────────────────────────────────────────────────
for conf in /etc/zv-manager/accounts/ssh/*.conf; do
    [[ -f "$conf" ]] || continue
    unset IS_TRIAL EXPIRED_TS USERNAME TG_USER_ID
    source "$conf"
    [[ "$IS_TRIAL" != "1" ]] && continue
    [[ -z "$EXPIRED_TS" ]] && continue
    [[ "$now_ts" -lt "$EXPIRED_TS" ]] && continue
    _tg_notif "$TG_USER_ID" "SSH" "$USERNAME"
    pkill -u "$USERNAME" &>/dev/null
    userdel -r "$USERNAME" &>/dev/null 2>&1
    rm -f "$conf"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SSH TRIAL cleanup: $USERNAME" >> "$LOG"
done

# ── VMess trial ──────────────────────────────────────────────
for conf in /etc/zv-manager/accounts/vmess/*.conf; do
    [[ -f "$conf" ]] || continue
    unset IS_TRIAL EXPIRED_TS USERNAME TG_USER_ID SERVER
    source "$conf"
    [[ "$IS_TRIAL" != "1" ]] && continue
    [[ -z "$EXPIRED_TS" ]] && continue
    [[ "$now_ts" -lt "$EXPIRED_TS" ]] && continue
    _tg_notif "$TG_USER_ID" "VMess" "$USERNAME"
    remote_vmess_agent "${SERVER:-local}" del "$USERNAME" 2>/dev/null
    rm -f "$conf"
    rm -f "/tmp/zv-tg-state/vmess_${USERNAME}.notified"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] VMESS TRIAL cleanup: $USERNAME" >> "$LOG"
done

# ── VLESS trial ──────────────────────────────────────────────
for conf in /etc/zv-manager/accounts/vless/*.conf; do
    [[ -f "$conf" ]] || continue
    unset IS_TRIAL EXPIRED_TS USERNAME TG_USER_ID SERVER
    source "$conf"
    [[ "$IS_TRIAL" != "1" ]] && continue
    [[ -z "$EXPIRED_TS" ]] && continue
    [[ "$now_ts" -lt "$EXPIRED_TS" ]] && continue
    _tg_notif "$TG_USER_ID" "VLESS" "$USERNAME"
    remote_vless_agent "${SERVER:-local}" del "$USERNAME" 2>/dev/null
    rm -f "$conf"
    rm -f "/tmp/zv-tg-state/vless_${USERNAME}.notified"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] VLESS TRIAL cleanup: $USERNAME" >> "$LOG"
done

# ── ZiVPN trial ──────────────────────────────────────────────
for conf in /etc/zv-manager/accounts/zivpn/*.conf; do
    [[ -f "$conf" ]] || continue
    unset IS_TRIAL EXPIRED_TS USERNAME TG_USER_ID SERVER
    source "$conf"
    [[ "$IS_TRIAL" != "1" ]] && continue
    [[ -z "$EXPIRED_TS" ]] && continue
    [[ "$now_ts" -lt "$EXPIRED_TS" ]] && continue
    _tg_notif "$TG_USER_ID" "ZiVPN" "$USERNAME"
    remote_zivpn_agent "${SERVER:-local}" del "$USERNAME" 2>/dev/null
    rm -f "$conf"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ZIVPN TRIAL cleanup: $USERNAME" >> "$LOG"
done
