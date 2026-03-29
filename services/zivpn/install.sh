#!/bin/bash
# ============================================================
#   ZV-Manager - ZiVPN UDP Installer
#   Binary: /usr/local/bin/zivpn
#   Config: /etc/zivpn/config.json
#   Cert  : /etc/zivpn/zivpn.crt + zivpn.key
#   Port  : 5667 UDP
# ============================================================
source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh

ZIVPN_BIN="/usr/local/bin/zivpn"
ZIVPN_DIR="/etc/zivpn"
ZIVPN_CFG="${ZIVPN_DIR}/config.json"
ZIVPN_CRT="${ZIVPN_DIR}/zivpn.crt"
ZIVPN_KEY="${ZIVPN_DIR}/zivpn.key"
ZIVPN_PORT="5667"

install_zivpn() {
    print_section "Install ZiVPN UDP"
    mkdir -p "$ZIVPN_DIR"

    # 1. Download binary
    if [[ ! -f "$ZIVPN_BIN" ]]; then
        local ARCH; ARCH=$(uname -m)
        local DL_URL
        case "$ARCH" in
            x86_64)  DL_URL="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64" ;;
            aarch64) DL_URL="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-arm64" ;;
            *)       DL_URL="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64" ;;
        esac
        wget -q -O "$ZIVPN_BIN" "$DL_URL" 2>/dev/null || { print_error "Gagal download ZiVPN binary."; return 1; }
        chmod +x "$ZIVPN_BIN"
    fi

    # 2. Generate self-signed cert
    if [[ ! -f "$ZIVPN_CRT" || ! -f "$ZIVPN_KEY" ]]; then
        openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
            -subj "/C=ID/ST=Jakarta/L=Jakarta/O=ZV-Manager/CN=zivpn" \
            -keyout "$ZIVPN_KEY" -out "$ZIVPN_CRT" &>/dev/null
    fi

    # 3. Tulis config.json kosong
    _write_zivpn_config

    # 4. Kernel UDP tuning
    sysctl -w net.core.rmem_max=16777216 &>/dev/null
    sysctl -w net.core.wmem_max=16777216 &>/dev/null
    grep -q "net.core.rmem_max" /etc/sysctl.conf || \
        printf '\nnet.core.rmem_max=16777216\nnet.core.wmem_max=16777216\n' >> /etc/sysctl.conf

    # 5. Systemd service
    cat > /etc/systemd/system/zv-zivpn.service << SVCEOF
[Unit]
Description=ZV-Manager ZiVPN UDP Service
After=network.target

[Service]
Type=simple
ExecStart=${ZIVPN_BIN} server --config ${ZIVPN_CFG}
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
SVCEOF

    systemctl daemon-reload &>/dev/null
    systemctl enable zv-zivpn &>/dev/null
    systemctl restart zv-zivpn &>/dev/null
    sleep 2
    if systemctl is-active --quiet zv-zivpn; then
        print_success "ZiVPN UDP (port ${ZIVPN_PORT})"
    else
        print_error "ZiVPN gagal start! Cek: systemctl status zv-zivpn"
        return 1
    fi
}

_write_zivpn_config() {
    local ACCT_DIR="/etc/zv-manager/accounts/zivpn"
    mkdir -p "$ACCT_DIR"
    local now_ts; now_ts=$(date +%s)
    local passwords=()
    for conf in "${ACCT_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue
        local exp_ts pw
        exp_ts=$(grep "^EXPIRED_TS=" "$conf" | cut -d= -f2 | tr -d '"')
        pw=$(grep "^PASSWORD=" "$conf" | cut -d= -f2 | tr -d '"')
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
}

reload_zivpn() { _write_zivpn_config; systemctl restart zv-zivpn &>/dev/null; }

uninstall_zivpn() {
    systemctl stop zv-zivpn &>/dev/null; systemctl disable zv-zivpn &>/dev/null
    rm -f /etc/systemd/system/zv-zivpn.service "$ZIVPN_BIN"; rm -rf "$ZIVPN_DIR"
    systemctl daemon-reload &>/dev/null; print_ok "ZiVPN dihapus."
}
