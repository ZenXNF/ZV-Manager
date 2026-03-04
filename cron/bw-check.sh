#!/bin/bash
# ============================================================
#   ZV-Manager - Bandwidth Checker
#   Cron tiap 5 menit: akumulasi usage, block yang habis,
#   kirim notif Telegram
# ============================================================

source /etc/zv-manager/core/bandwidth.sh
source /etc/zv-manager/core/telegram.sh
tg_load 2>/dev/null || true

ACCOUNT_DIR="/etc/zv-manager/accounts/ssh"

_notify_bw() {
    local tg_uid="$1" user="$2" used="$3" quota="$4" action="$5"
    [[ -z "$tg_uid" || -z "$TG_TOKEN" ]] && return
    local jfile; jfile=$(mktemp)
    python3 - "$tg_uid" "$user" "$used" "$quota" "$action" > "$jfile" << 'PYINLINE'
import json, sys
uid, user, used, quota, action = sys.argv[1:6]
used_gb  = round(int(used)/1024**3, 2)
quota_gb = round(int(quota)/1024**3, 2)
if action == "warning":
    text = (
        f"⚠️ <b>Peringatan Bandwidth</b>\n\n"
        f"Username : <code>{user}</code>\n"
        f"Terpakai : {used_gb} GB / {quota_gb} GB\n"
        f"Sisa     : {round(quota_gb - used_gb, 2)} GB\n\n"
        "Bandwidth hampir habis! Beli tambahan agar tidak terputus."
    )
else:
    text = (
        f"🚫 <b>Bandwidth Habis!</b>\n\n"
        f"Username : <code>{user}</code>\n"
        f"Terpakai : {used_gb} GB / {quota_gb} GB\n\n"
        "Koneksi diputus. Beli tambahan bandwidth di bot untuk aktif kembali."
    )
print(json.dumps({"chat_id": uid, "text": text, "parse_mode": "HTML"}))
PYINLINE
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -H "Content-Type: application/json" -d "@${jfile}" --max-time 10 &>/dev/null
    rm -f "$jfile"
}

for conf in "$ACCOUNT_DIR"/*.conf; do
    [[ -f "$conf" ]] || continue
    unset USERNAME BW_QUOTA_BYTES BW_USED_BYTES BW_BLOCKED IS_TRIAL TG_USER_ID
    source "$conf"

    [[ -z "$USERNAME" ]] && continue
    # Skip kalau tidak ada quota (fitur BW belum diaktifkan untuk akun ini)
    [[ -z "$BW_QUOTA_BYTES" || "$BW_QUOTA_BYTES" -eq 0 ]] && continue
    # Pastikan chain iptables ada
    _bw_init_user "$USERNAME" 2>/dev/null
    # Akumulasi delta
    local_used=$(_bw_accumulate "$USERNAME")
    [[ -z "$local_used" ]] && local_used="$BW_USED_BYTES"
    local_used="${local_used:-0}"

    quota="$BW_QUOTA_BYTES"
    tg_uid=$(grep "^TG_USER_ID=" "$conf" | cut -d= -f2 | tr -d "[:space:]")
    warn_dir="/etc/zv-manager/accounts/notified"
    mkdir -p "$warn_dir"
    warn_file="${warn_dir}/${USERNAME}.bw_warn"

    # Sudah blocked — skip
    [[ "$BW_BLOCKED" == "1" ]] && continue

    # Habis → block
    if [[ "$local_used" -ge "$quota" ]]; then
        _bw_block "$USERNAME"
        rm -f "$warn_file"  # reset warning flag
        _notify_bw "$tg_uid" "$USERNAME" "$local_used" "$quota" "blocked"
        _bw_log "QUOTA_EXCEEDED: $USERNAME used=${local_used} quota=${quota}"

    # 80% terpakai → warning (kirim sekali)
    elif [[ $(( local_used * 100 / quota )) -ge 80 && ! -f "$warn_file" ]]; then
        touch "$warn_file"
        _notify_bw "$tg_uid" "$USERNAME" "$local_used" "$quota" "warning"
        _bw_log "QUOTA_WARNING: $USERNAME used=${local_used} quota=${quota}"
    fi
done
