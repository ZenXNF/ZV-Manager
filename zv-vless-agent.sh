#!/bin/bash
# ============================================================
#   ZV-VLESS-Agent - VLESS Account Management Agent
#   Diinstall di remote VPS: /usr/local/bin/zv-vless-agent
#   Dipanggil dari brain VPS via SSH
#
#   Usage: zv-vless-agent <command> [args...]
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
#     exists <user>
#     bw     <user>
#     rebuild-config
# ============================================================

VLESS_DIR="/etc/zv-manager/accounts/vless"
XRAY_BIN="/usr/local/bin/xray"
XRAY_DIR="/usr/local/etc/xray"
API_ADDR="127.0.0.1:10085"

mkdir -p "$VLESS_DIR"

# ── helpers ──────────────────────────────────────────────────
_today()         { date +"%Y-%m-%d"; }
_exp_from_days() { date -d "$1 days" +"%Y-%m-%d" 2>/dev/null; }
_conf()          { echo "${VLESS_DIR}/$1.conf"; }
_exists()        { [[ -f "$(_conf "$1")" ]]; }
_read()          {
    unset USERNAME UUID EXPIRED EXPIRED_TS CREATED TG_USER_ID BW_LIMIT_GB BW_USED_BYTES SERVER
    source "$(_conf "$1")" 2>/dev/null
}

_xray_add() {
    local user="$1" uuid="$2"
    local j="{\"vless\":{\"id\":\"${uuid}\",\"email\":\"${user}@vless\",\"encryption\":\"none\"}}"
    "$XRAY_BIN" api rmu -s "$API_ADDR" -inbound "vless-ws"   -email "placeholder@vless" &>/dev/null || true
    "$XRAY_BIN" api rmu -s "$API_ADDR" -inbound "vless-grpc" -email "placeholder@vless" &>/dev/null || true
    "$XRAY_BIN" api adu -s "$API_ADDR" -inbound "vless-ws"   -user "$j" &>/dev/null || true
    "$XRAY_BIN" api adu -s "$API_ADDR" -inbound "vless-grpc" -user "$j" &>/dev/null || true
    _xray_config_rebuild
}

_xray_del() {
    local user="$1"
    "$XRAY_BIN" api rmu -s "$API_ADDR" -inbound "vless-ws"   -email "${user}@vless" &>/dev/null || true
    "$XRAY_BIN" api rmu -s "$API_ADDR" -inbound "vless-grpc" -email "${user}@vless" &>/dev/null || true
    _xray_config_rebuild
}

# ── Rebuild terpusat VMess + VLESS ────────────────────────────
_xray_config_rebuild() {
    local config_file="${XRAY_DIR}/config.json"
    local now_ts; now_ts=$(date +%s)

    local vmess_ws="" vmess_grpc=""
    for f in "/etc/zv-manager/accounts/vmess"/*.conf; do
        [[ -f "$f" ]] || continue
        unset USERNAME UUID EXPIRED_TS
        source "$f" 2>/dev/null
        [[ -z "$UUID" || -z "$USERNAME" ]] && continue
        [[ -n "$EXPIRED_TS" && "$EXPIRED_TS" -lt "$now_ts" ]] && continue
        local entry="{\"id\":\"${UUID}\",\"alterId\":0,\"email\":\"${USERNAME}@vmess\"}"
        vmess_ws="${vmess_ws}${entry},"
        vmess_grpc="${vmess_grpc}${entry},"
    done
    vmess_ws="${vmess_ws%,}"; vmess_grpc="${vmess_grpc%,}"

    local vless_ws="" vless_grpc=""
    for f in "${VLESS_DIR}"/*.conf; do
        [[ -f "$f" ]] || continue
        unset USERNAME UUID EXPIRED_TS
        source "$f" 2>/dev/null
        [[ -z "$UUID" || -z "$USERNAME" ]] && continue
        [[ -n "$EXPIRED_TS" && "$EXPIRED_TS" -lt "$now_ts" ]] && continue
        local entry="{\"id\":\"${UUID}\",\"email\":\"${USERNAME}@vless\"}"
        vless_ws="${vless_ws}${entry},"
        vless_grpc="${vless_grpc}${entry},"
    done
    vless_ws="${vless_ws%,}"; vless_grpc="${vless_grpc%,}"

    python3 - "$config_file" "$vmess_ws" "$vmess_grpc" "$vless_ws" "$vless_grpc" << 'PYEOF'
import sys, json

config_file    = sys.argv[1]
vmess_ws_raw   = sys.argv[2]
vmess_grpc_raw = sys.argv[3]
vless_ws_raw   = sys.argv[4]
vless_grpc_raw = sys.argv[5]

def parse_clients(raw):
    if not raw.strip():
        return []
    try:
        return json.loads(f"[{raw}]")
    except Exception:
        return []

vmess_ws   = parse_clients(vmess_ws_raw)   or [{"id":"00000000-0000-0000-0000-000000000000","alterId":0,"email":"placeholder@vmess"}]
vmess_grpc = parse_clients(vmess_grpc_raw) or [{"id":"00000000-0000-0000-0000-000000000000","alterId":0,"email":"placeholder@vmess"}]
vless_ws   = parse_clients(vless_ws_raw)   or [{"id":"00000000-0000-0000-0000-000000000001","email":"placeholder@vless"}]
vless_grpc = parse_clients(vless_grpc_raw) or [{"id":"00000000-0000-0000-0000-000000000001","email":"placeholder@vless"}]

with open(config_file) as f:
    cfg = json.load(f)

for inbound in cfg.get("inbounds", []):
    tag = inbound.get("tag")
    if tag == "vmess-ws":
        inbound["settings"]["clients"] = vmess_ws
    elif tag == "vmess-grpc":
        inbound["settings"]["clients"] = vmess_grpc
    elif tag == "vless-ws":
        inbound["settings"]["clients"] = vless_ws
        inbound["settings"]["decryption"] = "none"
    elif tag == "vless-grpc":
        inbound["settings"]["clients"] = vless_grpc
        inbound["settings"]["decryption"] = "none"

with open(config_file, "w") as f:
    json.dump(cfg, f, indent=2)
PYEOF
    systemctl restart zv-xray &>/dev/null || true
}

# ── ping ─────────────────────────────────────────────────────
cmd_ping() { echo "ZV-VLESS-AGENT-OK"; }

# ── add ──────────────────────────────────────────────────────
cmd_add() {
    local user="$1" uuid="$2" days="$3" bw="$4" tg_uid="${5:-0}"
    [[ -z "$user" || -z "$uuid" || -z "$days" ]] && {
        echo "ADD-ERR|Argumen tidak lengkap (user uuid days bw_limit_gb)"; return 1
    }
    [[ -z "$bw" ]] && bw=0
    if _exists "$user"; then
        _read "$user"
        _xray_add "$user" "${UUID:-$uuid}"
        echo "ADD-OK|${user}|${UUID:-$uuid}|${EXPIRED:-?}"
        return 0
    fi
    local exp; exp=$(_exp_from_days "$days")
    [[ -z "$exp" ]] && { echo "ADD-ERR|Format hari tidak valid: $days"; return 1; }
    local exp_ts; exp_ts=$(date -d "$exp" +%s 2>/dev/null || echo "0")
    cat > "$(_conf "$user")" << CONFEOF
USERNAME="${user}"
UUID="${uuid}"
EXPIRED="${exp}"
EXPIRED_TS="${exp_ts}"
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
    rm -f "$(_conf "$user")" "${VLESS_DIR}/${user}.disabled"
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
cmd_list() {
    local count=0
    for conf in "${VLESS_DIR}"/*.conf; do
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
    local new_exp; new_exp=$(_exp_from_days "$days")
    [[ -z "$new_exp" ]] && { echo "RENEW-ERR|Format hari tidak valid"; return 1; }
    local new_ts; new_ts=$(date -d "$new_exp" +%s 2>/dev/null || echo "0")
    sed -i "s/^EXPIRED=.*/EXPIRED=\"${new_exp}\"/" "$(_conf "$user")"
    sed -i "s/^EXPIRED_TS=.*/EXPIRED_TS=\"${new_ts}\"/" "$(_conf "$user")"
    if [[ -f "${VLESS_DIR}/${user}.disabled" ]]; then
        mv "${VLESS_DIR}/${user}.disabled" "$(_conf "$user")"
        _read "$user"
        _xray_add "$user" "$UUID"
    fi
    echo "RENEW-OK|${user}|${new_exp}"
}

# ── enable / disable ─────────────────────────────────────────
cmd_enable() {
    local user="$1"
    [[ -z "$user" ]] && { echo "ENABLE-ERR|Username wajib diisi"; return 1; }
    local disabled="${VLESS_DIR}/${user}.disabled"
    if [[ -f "$disabled" ]]; then
        mv "$disabled" "$(_conf "$user")"
        _read "$user"
        _xray_add "$user" "$UUID"
        echo "ENABLE-OK|${user}"
    elif _exists "$user"; then
        echo "ENABLE-OK|${user}"
    else
        echo "ENABLE-ERR|Akun '${user}' tidak ditemukan"
    fi
}

cmd_disable() {
    local user="$1"
    [[ -z "$user" ]] && { echo "DISABLE-ERR|Username wajib diisi"; return 1; }
    _exists "$user" || { echo "DISABLE-ERR|Akun '${user}' tidak ditemukan"; return 1; }
    _xray_del "$user"
    mv "$(_conf "$user")" "${VLESS_DIR}/${user}.disabled"
    echo "DISABLE-OK|${user}"
}

# ── check / exists ───────────────────────────────────────────
cmd_check() {
    local user="$1"
    [[ -z "$user" ]] && { echo "CHECK-ERR|Username wajib diisi"; return 1; }
    if _exists "$user"; then
        echo "EXISTS|${user}"
    elif [[ -f "${VLESS_DIR}/${user}.disabled" ]]; then
        echo "DISABLED|${user}"
    else
        echo "NOTFOUND|${user}"
    fi
}

cmd_exists() {
    local user="$1"
    _exists "$user" && echo "YES" || echo "NO"
}

# ── bw ───────────────────────────────────────────────────────
cmd_bw() {
    local user="$1"
    [[ -z "$user" ]] && { echo "BW-ERR|Username wajib diisi"; return 1; }
    _exists "$user" || { echo "BW-ERR|Akun '${user}' tidak ditemukan"; return 1; }
    _read "$user"
    local tmpf; tmpf=$(mktemp)
    "$XRAY_BIN" api statsquery -s "$API_ADDR" -pattern "user>>>${user}@vless" --reset > "$tmpf" 2>/dev/null
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
    ping)           cmd_ping             ;;
    add)            cmd_add     "$@"     ;;
    del)            cmd_del     "$@"     ;;
    info)           cmd_info    "$@"     ;;
    list)           cmd_list             ;;
    renew)          cmd_renew   "$@"     ;;
    enable)         cmd_enable  "$@"     ;;
    disable)        cmd_disable "$@"     ;;
    check)          cmd_check   "$@"     ;;
    exists)         cmd_exists  "$@"     ;;
    bw)             cmd_bw      "$@"     ;;
    rebuild-config) _xray_config_rebuild; echo "REBUILD-OK" ;;
    *)
        echo "ZV-VLESS-Agent"
        echo "Usage: zv-vless-agent <command> [args]"
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
        echo "  exists <user>"
        echo "  bw     <user>"
        exit 1
        ;;
esac
