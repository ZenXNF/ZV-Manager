#!/bin/bash
# ============================================================
#   ZV-Manager - Auto Kill Multi-Login
#   Cek jumlah session aktif via counter file
#   Jika melebihi limit → hapus akun + notif Telegram
# ============================================================
ACCOUNT_DIR="/etc/zv-manager/accounts/ssh"
SESSION_DIR="/tmp/zv-bw"
TG_CONF="/etc/zv-manager/telegram.conf"
LOG="/var/log/zv-manager/install.log"

source /etc/zv-manager/core/bandwidth.sh 2>/dev/null

TOKEN=$(grep "^TG_TOKEN=" "$TG_CONF" 2>/dev/null | cut -d= -f2 | tr -d '"'"'"' ')

_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG" 2>/dev/null; }

_tg_send() {
    local chat="$1" msg="$2"
    [[ -z "$TOKEN" || -z "$chat" ]] && return
    python3 -c "
import json,urllib.request
p=json.dumps({'chat_id':'${chat}','parse_mode':'HTML','text':'''$msg'''}).encode()
r=urllib.request.Request('https://api.telegram.org/bot${TOKEN}/sendMessage',data=p,headers={'Content-Type':'application/json'})
try: urllib.request.urlopen(r,timeout=10)
except: pass
"
}

_hapus_akun() {
    local username="$1" tg_uid="$2" server="$3"
    local local_ip; local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null | tr -d '[:space:]')
    local conf_file="${ACCOUNT_DIR}/${username}.conf"

    _bw_cleanup_user "$username" 2>/dev/null
    rm -f "${SESSION_DIR}/${username}.ips" "${SESSION_DIR}/${username}.count" 2>/dev/null
    rm -f "/etc/zv-manager/accounts/notified/${username}.notified" 2>/dev/null

    # Cek apakah akun ada di server lokal atau remote
    local srv_ip=""
    if [[ -f "$conf_file" ]]; then
        local sname; sname=$(grep "^SERVER=" "$conf_file" | cut -d= -f2 | tr -d '"' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [[ -n "$sname" ]]; then
            local sconf="/etc/zv-manager/servers/${sname}.conf"
            [[ -f "$sconf" ]] && srv_ip=$(grep "^IP=" "$sconf" | cut -d= -f2 | tr -d '"' | tr -d '[:space:]')
        fi
    fi

    if [[ -z "$srv_ip" || "$srv_ip" == "$local_ip" ]]; then
        # Akun lokal — hapus system user
        pkill -u "$username" -9 &>/dev/null
        userdel -r "$username" &>/dev/null 2>&1
    fi
    # Selalu hapus conf lokal di otak
    rm -f "$conf_file"
    _log "AUTOKILL: $username dihapus (multi-login) server=$server"
    [[ -n "$tg_uid" ]] && _tg_send "$tg_uid" "🚫 Akun Dihapus! Username: $username | Server: $server | Alasan: Multi Login melebihi batas. Buat akun baru via bot."
}

# ── Sync session count akun SSH remote via zv-agent online ──────
local _local_ip_ak; _local_ip_ak=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null | tr -d '[:space:]')
for _sconf in /etc/zv-manager/servers/*.conf; do
    [[ -f "$_sconf" && "$_sconf" != *.tg.conf ]] || continue
    local _srv_ip; _srv_ip=$(grep "^IP=" "$_sconf" | cut -d= -f2 | tr -d '"' | tr -d '[:space:]')
    [[ -z "$_srv_ip" || "$_srv_ip" == "$_local_ip_ak" ]] && continue
    local _srv_name; _srv_name=$(grep "^NAME=" "$_sconf" | cut -d= -f2 | tr -d '"' | tr -d '[:space:]')
    [[ -z "$_srv_name" ]] && continue
    # Ambil session count semua user di server remote ini
    local _online_raw; _online_raw=$(remote_agent "$_srv_name" online 2>/dev/null)
    if [[ -n "$_online_raw" ]]; then
        while IFS='|' read -r _ruser _rcount; do
            [[ -z "$_ruser" || -z "$_rcount" ]] && continue
            [[ "$_rcount" =~ ^[0-9]+$ ]] || continue
            echo "$_rcount" > "${SESSION_DIR}/${_ruser}.count"
        done <<< "$_online_raw"
    fi
done


# ── Auto Kill SSH ────────────────────────────────────────────
for conf_file in "$ACCOUNT_DIR"/*.conf; do
    [[ -f "$conf_file" ]] || continue
    uname=$(grep "^USERNAME="    "$conf_file" | cut -d= -f2 | tr -d '[:space:]')
    limit=$(grep "^LIMIT="       "$conf_file" | cut -d= -f2 | tr -d '[:space:]')
    tg_uid=$(grep "^TG_USER_ID=" "$conf_file" | cut -d= -f2 | tr -d '[:space:]')
    server=$(grep "^SERVER="     "$conf_file" | cut -d= -f2 | tr -d '[:space:]')
    [[ -z "$uname" ]] && continue
    limit=${limit:-2}
    # Hitung IP unik dari .ips file (ditulis PAM saat session open/close)
    ips_file="${SESSION_DIR}/${uname}.ips"
    if [[ -f "$ips_file" ]]; then
        current=$(grep -c . "$ips_file" 2>/dev/null || echo 0)
    else
        current=$(cat "${SESSION_DIR}/${uname}.count" 2>/dev/null || echo 0)
    fi
    current=${current:-0}
    if (( current > limit )); then
        _hapus_akun "$uname" "$tg_uid" "$server"
    fi
done

# ── Auto Kill VMess ──────────────────────────────────────────
VMESS_DIR="/etc/zv-manager/accounts/vmess"
XRAY_BIN="/usr/local/bin/xray"
API_ADDR="127.0.0.1:10085"

[[ -d "$VMESS_DIR" ]] || exit 0
[[ -x "$XRAY_BIN" ]] || exit 0

for conf_file in "$VMESS_DIR"/*.conf; do
    [[ -f "$conf_file" ]] || continue
    v_user=$(grep "^USERNAME="    "$conf_file" | cut -d= -f2 | tr -d '"[:space:]')
    v_tguid=$(grep "^TG_USER_ID=" "$conf_file" | cut -d= -f2 | tr -d '"[:space:]')
    v_server=$(grep "^SERVER="    "$conf_file" | cut -d= -f2 | tr -d '"[:space:]')
    v_trial=$(grep "^IS_TRIAL="   "$conf_file" | cut -d= -f2 | tr -d '"[:space:]')
    v_exp=$(grep "^EXPIRED_TS="   "$conf_file" | cut -d= -f2 | tr -d '"[:space:]')
    [[ -z "$v_user" ]] && continue
    # Skip expired
    now_ts=$(date +%s)
    [[ -n "$v_exp" && "$v_exp" =~ ^[0-9]+$ && "$v_exp" -lt "$now_ts" ]] && continue
    # Ambil limit IP dari tg.conf server
    v_tgconf="/etc/zv-manager/servers/${v_server}.tg.conf"
    v_limit=$(grep "^TG_LIMIT_IP_VMESS=" "$v_tgconf" 2>/dev/null | cut -d= -f2 | tr -d '"[:space:]')
    v_limit=${v_limit:-2}

    # Query online count dari Xray stats API
    v_online=$("$XRAY_BIN" api statsquery -s "$API_ADDR" \
        -pattern "user>>>${v_user}@vmess>>>online" 2>/dev/null \
        | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    stats=d.get('stat',[])
    print(int(stats[0].get('value',0)) if stats else 0)
except: print(0)
" 2>/dev/null)
    v_online=${v_online:-0}

    if (( v_online > v_limit )); then
        # Hapus dari Xray
        "$XRAY_BIN" api rmu -s "$API_ADDR" -inbound "vmess-ws"   -email "${v_user}@vmess" &>/dev/null
        "$XRAY_BIN" api rmu -s "$API_ADDR" -inbound "vmess-grpc" -email "${v_user}@vmess" &>/dev/null
        # Hapus conf
        rm -f "$conf_file"
        _log "AUTOKILL VMESS: $v_user dihapus (multi-login online=$v_online limit=$v_limit)"
        [[ -n "$v_tguid" ]] && _tg_send "$v_tguid" "🚫 <b>Akun VMess Dihapus!</b>
Username : <code>${v_user}</code>
Server   : ${v_server}
Alasan   : Multi Login melebihi batas (${v_online}/${v_limit} IP).
Buat akun baru via bot."
    fi
done
