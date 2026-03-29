#!/bin/bash
# ============================================================
#   ZV-ZIVPN-Agent — ZiVPN UDP Account Management
#   Installed at: /usr/local/bin/zv-zivpn-agent
#   Commands: ping add del info list renew exists rebuild-config
# ============================================================
ZIVPN_ACCT_DIR="/etc/zv-manager/accounts/zivpn"
ZIVPN_CFG="/etc/zivpn/config.json"
ZIVPN_CRT="/etc/zivpn/zivpn.crt"
ZIVPN_KEY="/etc/zivpn/zivpn.key"
ZIVPN_PORT="5667"
mkdir -p "$ZIVPN_ACCT_DIR"

_today()         { date +"%Y-%m-%d"; }
_exp_from_days() { date -d "$1 days" +"%Y-%m-%d" 2>/dev/null; }
_conf()          { echo "${ZIVPN_ACCT_DIR}/$1.conf"; }
_exists()        { [[ -f "$(_conf "$1")" ]]; }

_rebuild_config() {
    local now_ts; now_ts=$(date +%s)
    local passwords=()
    for conf in "${ZIVPN_ACCT_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue
        local pw exp_ts
        pw=$(grep "^PASSWORD=" "$conf" | cut -d= -f2 | tr -d '"')
        exp_ts=$(grep "^EXPIRED_TS=" "$conf" | cut -d= -f2 | tr -d '"')
        [[ -z "$pw" ]] && continue
        [[ -n "$exp_ts" && "$exp_ts" =~ ^[0-9]+$ && "$exp_ts" -lt "$now_ts" ]] && continue
        passwords+=("\"${pw}\"")
    done
    [[ ${#passwords[@]} -eq 0 ]] && passwords=("\"zv-placeholder\"")
    local pw_list; pw_list=$(IFS=,; echo "${passwords[*]}")
    python3 - "$ZIVPN_CFG" "$pw_list" "$ZIVPN_CRT" "$ZIVPN_KEY" "$ZIVPN_PORT" << 'PYEOF'
import sys, json
cfg_path  = sys.argv[1]
passwords = [p.strip().strip('"') for p in sys.argv[2].split(',') if p.strip()]
cert = sys.argv[3]; key = sys.argv[4]; port = sys.argv[5]
cfg = {"listen": f":{port}", "cert": cert, "key": key, "obfs": "zivpn",
       "auth": {"mode": "passwords", "config": passwords}}
with open(cfg_path, "w") as f: json.dump(cfg, f, indent=2)
PYEOF
    systemctl restart zv-zivpn &>/dev/null || true
}

cmd_ping() { echo "ZV-ZIVPN-AGENT-OK"; }

cmd_add() {
    local user="$1" pw="$2" days="$3" tg_uid="${4:-0}"
    [[ -z "$user" || -z "$pw" || -z "$days" ]] && { echo "ADD-ERR|Argumen tidak lengkap"; return 1; }
    local exp; exp=$(_exp_from_days "$days")
    [[ -z "$exp" ]] && { echo "ADD-ERR|Format hari tidak valid: $days"; return 1; }
    local exp_ts; exp_ts=$(date -d "$exp" +%s 2>/dev/null || echo "0")
    cat > "$(_conf "$user")" << CONFEOF
USERNAME="${user}"
PASSWORD="${pw}"
EXPIRED="${exp}"
EXPIRED_TS="${exp_ts}"
CREATED="$(_today)"
IS_TRIAL="0"
TG_USER_ID="${tg_uid}"
SERVER="$(hostname)"
CONFEOF
    _rebuild_config
    echo "ADD-OK|${user}|${pw}|${exp}"
}

cmd_del() {
    local user="$1"
    [[ -z "$user" ]] && { echo "DEL-ERR|Username wajib diisi"; return 1; }
    _exists "$user" || { echo "DEL-ERR|Akun '${user}' tidak ditemukan"; return 1; }
    rm -f "$(_conf "$user")"
    _rebuild_config
    echo "DEL-OK|${user}"
}

cmd_info() {
    local user="$1"
    [[ -z "$user" ]] && { echo "INFO-ERR|Username wajib diisi"; return 1; }
    _exists "$user" || { echo "INFO-ERR|Akun '${user}' tidak ditemukan"; return 1; }
    unset USERNAME PASSWORD EXPIRED EXPIRED_TS CREATED TG_USER_ID
    source "$(_conf "$user")" 2>/dev/null
    echo "INFO-OK|${USERNAME}|${PASSWORD}|${EXPIRED}|${CREATED:-?}"
}

cmd_list() {
    local count=0
    for conf in "${ZIVPN_ACCT_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue
        unset USERNAME PASSWORD EXPIRED CREATED
        source "$conf"
        echo "${USERNAME}|${PASSWORD}|${EXPIRED}|${CREATED:-?}"
        count=$((count+1))
    done
    [[ $count -eq 0 ]] && echo "LIST-EMPTY"
}

cmd_renew() {
    local user="$1" days="$2"
    [[ -z "$user" || -z "$days" ]] && { echo "RENEW-ERR|Argumen tidak lengkap"; return 1; }
    _exists "$user" || { echo "RENEW-ERR|Akun '${user}' tidak ditemukan"; return 1; }
    local new_exp; new_exp=$(_exp_from_days "$days")
    [[ -z "$new_exp" ]] && { echo "RENEW-ERR|Format hari tidak valid"; return 1; }
    local new_ts; new_ts=$(date -d "$new_exp" +%s 2>/dev/null || echo "0")
    sed -i "s/^EXPIRED=.*/EXPIRED=\"${new_exp}\"/" "$(_conf "$user")"
    sed -i "s/^EXPIRED_TS=.*/EXPIRED_TS=\"${new_ts}\"/" "$(_conf "$user")"
    _rebuild_config
    echo "RENEW-OK|${user}|${new_exp}"
}

cmd_exists() { _exists "$1" && echo "YES" || echo "NO"; }

CMD="$1"; shift
case "$CMD" in
    ping)           cmd_ping           ;;
    add)            cmd_add   "$@"     ;;
    del)            cmd_del   "$@"     ;;
    info)           cmd_info  "$@"     ;;
    list)           cmd_list           ;;
    renew)          cmd_renew "$@"     ;;
    exists)         cmd_exists "$@"    ;;
    rebuild-config) _rebuild_config; echo "REBUILD-OK" ;;
    *) echo "ZV-ZIVPN-Agent | Usage: zv-zivpn-agent <ping|add|del|info|list|renew|exists|rebuild-config>"; exit 1 ;;
esac
