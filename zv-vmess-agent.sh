#!/bin/bash
# ============================================================
#   ZV-VMess-Agent - VMess Account Management Agent
#   Diinstall di remote VPS: /usr/local/bin/zv-vmess-agent
#   Dipanggil dari brain VPS via SSH
#
#   Usage: zv-vmess-agent <command> [args...]
#
#   Commands:
#     ping
#     add  <user> <uuid> <days> <bw_limit_gb> [tg_uid]
#     del  <user>
#     info <user>
#     list
#     renew  <user> <days>
#     enable <user>
#     disable <user>
#     check  <user>
#     bw     <user>          → bandwidth used bytes
# ============================================================

VMESS_DIR="/etc/zv-manager/accounts/vmess"
XRAY_BIN="/usr/local/bin/xray"
XRAY_DIR="/usr/local/etc/xray"
API_ADDR="127.0.0.1:10085"

mkdir -p "$VMESS_DIR"

# ── helpers ──────────────────────────────────────────────────
_today()  { date +"%Y-%m-%d"; }
_exp_from_days() { date -d "$1 days" +"%Y-%m-%d" 2>/dev/null; }
_exp_from_base() { date -d "$1 +$2 days" +"%Y-%m-%d" 2>/dev/null; }
_conf()   { echo "${VMESS_DIR}/$1.conf"; }
_exists() { [[ -f "$(_conf "$1")" ]]; }
_read()   {
    unset USERNAME UUID EXPIRED CREATED TG_USER_ID BW_LIMIT_GB BW_USED_BYTES SERVER
    source "$(_conf "$1")" 2>/dev/null
}

_xray_add() {
    local user="$1" uuid="$2"
    local j="{\"vmess\":{\"id\":\"${uuid}\",\"email\":\"${user}@vmess\",\"alterId\":0}}"
    # Hapus placeholder dari memory jika masih ada
    "$XRAY_BIN" api rmu -s "$API_ADDR" -inbound "vmess-ws"   -email "placeholder@vmess" &>/dev/null || true
    "$XRAY_BIN" api rmu -s "$API_ADDR" -inbound "vmess-grpc" -email "placeholder@vmess" &>/dev/null || true
    "$XRAY_BIN" api adu -s "$API_ADDR" -inbound "vmess-ws"   -user "$j" &>/dev/null || true
    "$XRAY_BIN" api adu -s "$API_ADDR" -inbound "vmess-grpc" -user "$j" &>/dev/null || true
    _xray_config_rebuild
}

_xray_del() {
    local user="$1"
    "$XRAY_BIN" api rmu -s "$API_ADDR" -inbound "vmess-ws"   -email "${user}@vmess" &>/dev/null || true
    "$XRAY_BIN" api rmu -s "$API_ADDR" -inbound "vmess-grpc" -email "${user}@vmess" &>/dev/null || true
    _xray_config_rebuild
}

# ── Rebuild config.json dari semua .conf aktif ───────────────
# Dipanggil setiap add/del/renew supaya config persist
_xray_config_rebuild() {
    local conf_dir="/etc/zv-manager/accounts/vmess"
    local config_file="${XRAY_DIR}/config.json"
    local now_ts; now_ts=$(date +%s)

    # Kumpulkan semua UUID akun yang belum expired
    local clients_ws="" clients_grpc=""
    for f in "${conf_dir}"/*.conf; do
        [[ -f "$f" ]] || continue
        unset USERNAME UUID EXPIRED_TS SERVER
        source "$f" 2>/dev/null
        [[ -z "$UUID" || -z "$USERNAME" ]] && continue
        # Skip expired
        [[ -n "$EXPIRED_TS" && "$EXPIRED_TS" -lt "$now_ts" ]] && continue
        local entry="{\"id\":\"${UUID}\",\"alterId\":0,\"email\":\"${USERNAME}@vmess\"}"
        clients_ws="${clients_ws}${entry},"
        clients_grpc="${clients_grpc}${entry},"
    done
    # Hapus trailing koma
    clients_ws="${clients_ws%,}"
    clients_grpc="${clients_grpc%,}"

    # Tulis ulang config.json via python3 (aman untuk JSON)
    python3 - "$config_file" "$clients_ws" "$clients_grpc" << 'PYEOF'
import sys, json

config_file = sys.argv[1]
clients_ws_raw   = sys.argv[2]
clients_grpc_raw = sys.argv[3]

import json as _json

def parse_clients(raw):
    if not raw.strip():
        return []
    try:
        return _json.loads(f"[{raw}]")
    except Exception:
        return []

clients_ws   = parse_clients(clients_ws_raw)
clients_grpc = parse_clients(clients_grpc_raw)

with open(config_file) as f:
    cfg = json.load(f)

for inbound in cfg.get("inbounds", []):
    if inbound.get("tag") == "vmess-ws":
        inbound["settings"]["clients"] = clients_ws
    elif inbound.get("tag") == "vmess-grpc":
        inbound["settings"]["clients"] = clients_grpc

with open(config_file, "w") as f:
    json.dump(cfg, f, indent=2)
PYEOF
}

# ── ping ─────────────────────────────────────────────────────
cmd_ping() { echo "ZV-VMESS-AGENT-OK"; }

# ── add ──────────────────────────────────────────────────────
# add <user> <uuid> <days> <bw_limit_gb> [tg_uid]
cmd_add() {
    local user="$1" uuid="$2" days="$3" bw="$4" tg_uid="${5:-0}"
    [[ -z "$user" || -z "$uuid" || -z "$days" ]] && {
        echo "ADD-ERR|Argumen tidak lengkap (user uuid days bw_limit_gb)"; return 1
    }
    [[ -z "$bw" ]] && bw=0
    _exists "$user" && { echo "ADD-ERR|Akun '${user}' sudah ada"; return 1; }
    local exp
    exp=$(_exp_from_days "$days")
    [[ -z "$exp" ]] && { echo "ADD-ERR|Format hari tidak valid: $days"; return 1; }
    cat > "$(_conf "$user")" <<CONFEOF
USERNAME="${user}"
UUID="${uuid}"
EXPIRED="${exp}"
CREATED="$(_today)"
TG_USER_ID="${tg_uid}"
BW_LIMIT_GB="${bw}"
BW_USED_BYTES="0"
BW_LAST_CHECK="$(_today)"
SERVER="$(hostname)"
CONFEOF
    _xray_add "$user" "$uuid"
    echo "ADD-OK|${user}|${uuid}|${exp}"
}

# ── del ──────────────────────────────────────────────────────
cmd_del() {
    local user="$1"
    [[ -z "$user" ]] && { echo "DEL-ERR|Username wajib diisi"; return 1; }
    _exists "$user" || { echo "DEL-ERR|Akun '${user}' tidak ditemukan"; return 1; }
    _xray_del "$user"
    rm -f "$(_conf "$user")" "${VMESS_DIR}/${user}.disabled"
    echo "DEL-OK|${user}"
}

# ── info ─────────────────────────────────────────────────────
cmd_info() {
    local user="$1"
    [[ -z "$user" ]] && { echo "INFO-ERR|Username wajib diisi"; return 1; }
    _exists "$user" || { echo "INFO-ERR|Akun '${user}' tidak ditemukan"; return 1; }
    _read "$user"
    echo "INFO-OK|${USERNAME}|${UUID}|${EXPIRED}|${CREATED:-?}|${BW_LIMIT_GB:-0}|${BW_USED_BYTES:-0}"
}

# ── list ─────────────────────────────────────────────────────
# Output per baris: USERNAME|UUID|EXPIRED|CREATED|BW_LIMIT_GB|BW_USED_BYTES
cmd_list() {
    local count=0
    for conf in "${VMESS_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue
        unset USERNAME UUID EXPIRED CREATED BW_LIMIT_GB BW_USED_BYTES
        source "$conf"
        echo "${USERNAME}|${UUID}|${EXPIRED}|${CREATED:-?}|${BW_LIMIT_GB:-0}|${BW_USED_BYTES:-0}"
        count=$(( count + 1 ))
    done
    [[ $count -eq 0 ]] && echo "LIST-EMPTY"
}

# ── renew ────────────────────────────────────────────────────
cmd_renew() {
    local user="$1" days="$2"
    [[ -z "$user" || -z "$days" ]] && { echo "RENEW-ERR|Argumen tidak lengkap (user days)"; return 1; }
    _exists "$user" || { echo "RENEW-ERR|Akun '${user}' tidak ditemukan"; return 1; }
    local new_exp
    new_exp=$(_exp_from_days "$days")
    [[ -z "$new_exp" ]] && { echo "RENEW-ERR|Format hari tidak valid"; return 1; }
    sed -i "s/^EXPIRED=.*/EXPIRED=\"${new_exp}\"/" "$(_conf "$user")"
    # Re-add ke xray jika sebelumnya disabled
    if [[ -f "${VMESS_DIR}/${user}.disabled" ]]; then
        mv "${VMESS_DIR}/${user}.disabled" "$(_conf "$user")"
        _read "$user"
        _xray_add "$user" "$UUID"
    fi
    echo "RENEW-OK|${user}|${new_exp}"
}

# ── enable / disable ─────────────────────────────────────────
cmd_enable() {
    local user="$1"
    [[ -z "$user" ]] && { echo "ENABLE-ERR|Username wajib diisi"; return 1; }
    local disabled="${VMESS_DIR}/${user}.disabled"
    if [[ -f "$disabled" ]]; then
        mv "$disabled" "$(_conf "$user")"
        _read "$user"
        _xray_add "$user" "$UUID"
        echo "ENABLE-OK|${user}"
    elif _exists "$user"; then
        echo "ENABLE-OK|${user}"  # sudah aktif
    else
        echo "ENABLE-ERR|Akun '${user}' tidak ditemukan"
    fi
}

cmd_disable() {
    local user="$1"
    [[ -z "$user" ]] && { echo "DISABLE-ERR|Username wajib diisi"; return 1; }
    _exists "$user" || { echo "DISABLE-ERR|Akun '${user}' tidak ditemukan"; return 1; }
    _xray_del "$user"
    mv "$(_conf "$user")" "${VMESS_DIR}/${user}.disabled"
    echo "DISABLE-OK|${user}"
}

# ── check ────────────────────────────────────────────────────
cmd_check() {
    local user="$1"
    [[ -z "$user" ]] && { echo "CHECK-ERR|Username wajib diisi"; return 1; }
    if _exists "$user"; then
        echo "EXISTS|${user}"
    elif [[ -f "${VMESS_DIR}/${user}.disabled" ]]; then
        echo "DISABLED|${user}"
    else
        echo "NOTFOUND|${user}"
    fi
}

# ── bw ───────────────────────────────────────────────────────
cmd_bw() {
    local user="$1"
    [[ -z "$user" ]] && { echo "BW-ERR|Username wajib diisi"; return 1; }
    _exists "$user" || { echo "BW-ERR|Akun '${user}' tidak ditemukan"; return 1; }
    _read "$user"
    # Query xray stats
    local tmpf; tmpf=$(mktemp)
    "$XRAY_BIN" api statsquery -s "$API_ADDR" -pattern "user>>>${user}@vmess" > "$tmpf" 2>/dev/null
    local used
    used=$(python3 - "$tmpf" << 'PYEOF'
import sys, json
try:
    data = json.load(open(sys.argv[1]))
    total = 0
    for s in data.get("stat", []):
        total += int(s.get("value", 0))
    print(total)
except:
    print(0)
PYEOF
)
    rm -f "$tmpf"
    echo "BW-OK|${user}|${used:-0}|${BW_LIMIT_GB:-0}"
}

# ── dispatcher ───────────────────────────────────────────────
CMD="$1"; shift
case "$CMD" in
    ping)    cmd_ping             ;;
    add)     cmd_add     "$@"     ;;
    del)     cmd_del     "$@"     ;;
    info)    cmd_info    "$@"     ;;
    list)    cmd_list             ;;
    renew)   cmd_renew   "$@"     ;;
    enable)  cmd_enable  "$@"     ;;
    disable) cmd_disable "$@"     ;;
    check)   cmd_check   "$@"     ;;
    bw)      cmd_bw      "$@"     ;;
    *)
        echo "ZV-VMess-Agent"
        echo "Usage: zv-vmess-agent <command> [args]"
        echo ""
        echo "Commands:"
        echo "  ping"
        echo "  add  <user> <uuid> <days> <bw_limit_gb> [tg_uid]"
        echo "  del  <user>"
        echo "  info <user>"
        echo "  list"
        echo "  renew  <user> <days>"
        echo "  enable <user>"
        echo "  disable <user>"
        echo "  check  <user>"
        echo "  bw     <user>"
        exit 1
        ;;
esac
