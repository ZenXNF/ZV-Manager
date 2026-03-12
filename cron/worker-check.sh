#!/bin/bash
# ============================================================
#   ZV-Manager - Worker Server Health Check
#   Cron: tiap 5 menit
#   - Ping setiap worker VPS via zv-agent
#   - Kalau gagal → kirim notif ke user yang punya akun di server itu
#   - Cooldown 30 menit per server agar tidak spam
#   - Kirim notif "pulih" ke user saat server kembali online
# ============================================================

source /etc/zv-manager/core/telegram.sh
tg_load 2>/dev/null || true
source /etc/zv-manager/utils/remote.sh 2>/dev/null || true

BASE_DIR="/etc/zv-manager"
SERVER_DIR="${BASE_DIR}/servers"
LOG="/var/log/zv-manager/worker-check.log"
STATE_DIR="/tmp/zv-worker-check"
mkdir -p "$STATE_DIR"

COOLDOWN_DOWN=1800    # 30 menit — jeda notif "down" per server
COOLDOWN_RECOVER=300  # 5 menit — jeda notif "pulih" per server

_log() {
    echo "[$(TZ=Asia/Jakarta date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG" 2>/dev/null
}

_tg_send() {
    local chat_id="$1" text="$2"
    [[ -z "$TG_TOKEN" || -z "$chat_id" ]] && return
    printf '%b' "$text" | curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -F "chat_id=${chat_id}" \
        -F "parse_mode=HTML" \
        -F "text=<-" --max-time 10 &>/dev/null
}

# Ambil IP brain VPS (server lokal)
LOCAL_IP=$(cat "${BASE_DIR}/accounts/ipvps" 2>/dev/null | tr -d '[:space:]')

# ── Ping worker via SSH ───────────────────────────────────────
# Return 0 = online, 1 = offline
_ping_worker() {
    local name="$1"
    local conf="${SERVER_DIR}/${name}.conf"
    [[ ! -f "$conf" ]] && return 1

    local IP PORT USER PASS
    IP=$(grep "^IP="   "$conf" | cut -d= -f2 | tr -d '"')
    PORT=$(grep "^PORT=" "$conf" | cut -d= -f2 | tr -d '"')
    USER=$(grep "^USER=" "$conf" | cut -d= -f2 | tr -d '"')
    PASS=$(grep "^PASS=" "$conf" | cut -d= -f2 | tr -d '"')
    [[ -z "$PORT" ]] && PORT=22
    [[ -z "$USER" ]] && USER=root

    local result
    result=$(sshpass -p "$PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=8 \
        -o BatchMode=no \
        -p "$PORT" \
        "${USER}@${IP}" \
        "echo ZV-PING-OK" 2>&1)

    echo "$result" | grep -q "ZV-PING-OK"
}

# ── Kumpulkan UID user yang punya akun di server tertentu ────
_collect_uids() {
    local sname="$1"
    local -n _out=$2   # nameref ke array output
    _out=()
    local seen=()

    for _f in "${BASE_DIR}/accounts/ssh"/*.conf \
               "${BASE_DIR}/accounts/vmess"/*.conf; do
        [[ -f "$_f" ]] || continue
        local _srv; _srv=$(grep "^SERVER=" "$_f" | cut -d= -f2 | tr -d '"[:space:]')
        [[ "$_srv" != "$sname" ]] && continue
        local _uid; _uid=$(grep "^TG_USER_ID=" "$_f" | cut -d= -f2 | tr -d '"[:space:]')
        [[ -z "$_uid" || "$_uid" == "0" ]] && continue
        # dedup
        local _dup=false
        for _x in "${seen[@]}"; do [[ "$_x" == "$_uid" ]] && _dup=true && break; done
        [[ "$_dup" == false ]] && _out+=("$_uid") && seen+=("$_uid")
    done
}

# ── Cek cooldown ─────────────────────────────────────────────
_can_notify() {
    local key="$1" cooldown="$2"
    local state_file="${STATE_DIR}/${key}"
    local now; now=$(date +%s)
    if [[ -f "$state_file" ]]; then
        local last; last=$(cat "$state_file" 2>/dev/null)
        (( now - last < cooldown )) && return 1
    fi
    echo "$now" > "$state_file"
    return 0
}

_set_state() { echo "$1" > "${STATE_DIR}/state_${2}"; }
_get_state() { cat "${STATE_DIR}/state_${1}" 2>/dev/null || echo "up"; }

# ── Main loop semua server ────────────────────────────────────
for conf in "${SERVER_DIR}"/*.conf; do
    [[ -f "$conf" ]] || continue
    # Skip *.tg.conf
    [[ "$conf" == *.tg.conf ]] && continue

    name=$(grep "^NAME=" "$conf" | cut -d= -f2 | tr -d '"')
    [[ -z "$name" ]] && continue

    # Skip server lokal (brain) — watchdog.sh sudah handle
    ip=$(grep "^IP=" "$conf" | cut -d= -f2 | tr -d '"')
    [[ "$ip" == "$LOCAL_IP" ]] && continue

    tg_label=$(grep "^TG_SERVER_LABEL=" "${SERVER_DIR}/${name}.tg.conf" 2>/dev/null \
        | cut -d= -f2 | tr -d '"')
    [[ -z "$tg_label" ]] && tg_label="$name"

    prev_state=$(_get_state "$name")

    if _ping_worker "$name"; then
        # ── Server ONLINE ────────────────────────────────────
        if [[ "$prev_state" == "down" ]]; then
            _log "RECOVER: ${name} kembali online"
            _set_state "up" "$name"

            # Kirim notif pulih ke user (cooldown 5 menit)
            if _can_notify "recover_${name}" "$COOLDOWN_RECOVER"; then
                declare -a uids=()
                _collect_uids "$name" uids
                now_wib=$(TZ=Asia/Jakarta date "+%d %b %Y %H:%M")
                for uid in "${uids[@]}"; do
                    _tg_send "$uid" "✅ <b>Server Kembali Online!</b>
━━━━━━━━━━━━━━━━━━━
🖥 ${tg_label}
🕐 ${now_wib} WIB
━━━━━━━━━━━━━━━━━━━
Server sudah normal kembali. Akun kamu bisa digunakan seperti biasa. 🎉"
                    sleep 0.1
                done
                _log "NOTIF RECOVER: dikirim ke ${#uids[@]} user untuk server ${name}"
            fi
        fi
    else
        # ── Server OFFLINE ───────────────────────────────────
        _log "DOWN: ${name} tidak merespons"
        _set_state "down" "$name"

        # Kirim notif down ke user (cooldown 30 menit)
        if _can_notify "down_${name}" "$COOLDOWN_DOWN"; then
            declare -a uids=()
            _collect_uids "$name" uids

            if [[ ${#uids[@]} -gt 0 ]]; then
                now_wib=$(TZ=Asia/Jakarta date "+%d %b %Y %H:%M")
                for uid in "${uids[@]}"; do
                    _tg_send "$uid" "⚠️ <b>Server Gangguan!</b>
━━━━━━━━━━━━━━━━━━━
🖥 ${tg_label}
🕐 ${now_wib} WIB
━━━━━━━━━━━━━━━━━━━
Server sedang tidak dapat dijangkau. Tim sedang investigasi.
Kami akan kabari kamu saat server kembali normal. 🙏"
                    sleep 0.1
                done
                _log "NOTIF DOWN: dikirim ke ${#uids[@]} user untuk server ${name}"

                # Notif ke admin juga
                [[ -n "$TG_ADMIN_ID" ]] && _tg_send "$TG_ADMIN_ID" \
                    "🚨 <b>Worker Down!</b>
━━━━━━━━━━━━━━━━━━━
🖥 ${name} (${tg_label})
🌐 ${ip}
🕐 ${now_wib} WIB
━━━━━━━━━━━━━━━━━━━
Notif sudah dikirim ke ${#uids[@]} user."
            else
                _log "DOWN: ${name} — tidak ada user yang perlu dinotif"
            fi
        fi
    fi

    unset uids
done
