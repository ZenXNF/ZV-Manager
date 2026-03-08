#!/bin/bash
# ============================================================
#   ZV-Manager - Xray-core Installer
#   VMess over WebSocket (TLS & non-TLS) + gRPC
#   Arsitektur:
#     - Xray inbound WS  : 127.0.0.1:10001 (non-TLS, internal)
#     - Xray inbound gRPC: 127.0.0.1:10002 (non-TLS, internal)
#     - Nginx port 80    : /vmess → 10001
#     - Stunnel port 443 → nginx 80 → 10001 (TLS)
#     - Nginx port 443   : gRPC /vmess-grpc → 10002 (via h2)
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/config.conf

WS_PORT=${WS_PORT:-80}
WSS_PORT=${WSS_PORT:-443}
XRAY_DIR="/usr/local/etc/xray"
XRAY_BIN="/usr/local/bin/xray"
XRAY_ACCT_DIR="/etc/zv-manager/accounts/vmess"
SSL_CERT="/etc/zv-manager/ssl/cert.pem"
SSL_KEY="/etc/zv-manager/ssl/key.pem"

install_xray() {
    print_section "Install Xray-core (VMess)"

    # ── 1. Install xray binary ──────────────────────────────
    if [[ ! -f "$XRAY_BIN" ]]; then
        print_info "Mengunduh Xray-core..."
        local ARCH
        ARCH=$(uname -m)
        case "$ARCH" in
            x86_64)  ARCH_TAG="64" ;;
            aarch64) ARCH_TAG="arm64-v8a" ;;
            *)       ARCH_TAG="64" ;;
        esac

        local tmpdir
        tmpdir=$(mktemp -d)
        local dl_url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${ARCH_TAG}.zip"

        if ! wget -q --show-progress -O "${tmpdir}/xray.zip" "$dl_url"; then
            print_error "Gagal download Xray-core. Cek koneksi internet."
            return 1
        fi

        apt-get install -y unzip &>/dev/null
        unzip -q "${tmpdir}/xray.zip" -d "${tmpdir}/xray"
        install -m 755 "${tmpdir}/xray/xray" "$XRAY_BIN"
        rm -rf "$tmpdir"
        print_ok "Xray-core terinstall: $($XRAY_BIN version | head -1)"
    else
        print_info "Xray-core sudah ada, skip download..."
    fi

    # ── 2. Buat direktori ───────────────────────────────────
    mkdir -p "$XRAY_DIR" "$XRAY_ACCT_DIR"

    # ── 3. Generate config xray ────────────────────────────
    _write_xray_config

    # ── 4. Systemd service ──────────────────────────────────
    cat > /etc/systemd/system/zv-xray.service <<SVCEOF
[Unit]
Description=ZV-Manager Xray-core (VMess)
After=network.target
Wants=network.target

[Service]
Type=simple
ExecStart=${XRAY_BIN} run -c ${XRAY_DIR}/config.json
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
SVCEOF

    systemctl daemon-reload &>/dev/null
    systemctl enable zv-xray &>/dev/null
    systemctl restart zv-xray &>/dev/null

    # ── 6. Verifikasi ───────────────────────────────────────
    sleep 2
    if systemctl is-active --quiet zv-xray; then
        print_success "Xray-core (VMess WS port ${WS_PORT}/vmess, WSS port ${WSS_PORT}/vmess, gRPC vmess-grpc)"
    else
        print_error "Xray gagal start! Cek: systemctl status zv-xray"
        systemctl status zv-xray --no-pager -l
        return 1
    fi
}

_write_xray_config() {
    local tmppy
    tmppy=$(mktemp /tmp/xray_cfg_XXXXXX.py)

    cat > "$tmppy" << 'PYEOF2'
import json, glob

acct_dir = "/etc/zv-manager/accounts/vmess"
clients  = []
for conf in sorted(glob.glob(f"{acct_dir}/*.conf")):
    d = {}
    with open(conf) as f:
        for line in f:
            line = line.strip()
            if "=" in line:
                k, _, v = line.partition("=")
                d[k] = v.strip('"')
    if d.get("UUID") and d.get("USERNAME"):
        clients.append({
            "id":      d["UUID"],
            "alterId": 0,
            "email":   f"{d['USERNAME']}@vmess"
        })

if not clients:
    clients = [{"id": "00000000-0000-0000-0000-000000000000",
                "alterId": 0, "email": "placeholder@vmess"}]

cfg = {
  "log": {"loglevel": "warning", "error": "/var/log/xray-error.log"},
  "stats": {},
  "api": {"tag": "api", "services": ["StatsService"]},
  "policy": {
    "levels": {"0": {"statsUserUplink": True, "statsUserDownlink": True}},
    "system": {"statsInboundUplink": True, "statsInboundDownlink": True,
               "statsOutboundUplink": True, "statsOutboundDownlink": True}
  },
  "inbounds": [
    {
      "tag": "api-in",
      "listen": "127.0.0.1", "port": 10085,
      "protocol": "dokodemo-door",
      "settings": {"address": "127.0.0.1"},
      "streamSettings": {"network": "tcp"}
    },
    {
      "tag": "vmess-ws",
      "listen": "127.0.0.1", "port": 10001,
      "protocol": "vmess",
      "settings": {"clients": clients},
      "streamSettings": {"network": "ws", "wsSettings": {"path": "/vmess"}}
    },
    {
      "tag": "vmess-grpc",
      "listen": "127.0.0.1", "port": 10002,
      "protocol": "vmess",
      "settings": {"clients": clients},
      "streamSettings": {"network": "grpc",
                         "grpcSettings": {"serviceName": "vmess-grpc"}}
    }
  ],
  "outbounds": [
    {"tag": "direct", "protocol": "freedom"}
  ],
  "routing": {
    "rules": [
      {"type": "field", "inboundTag": ["api-in"], "outboundTag": "api"}
    ]
  }
}
with open("/usr/local/etc/xray/config.json", "w") as f:
    json.dump(cfg, f, indent=2)
PYEOF2

    python3 "$tmppy"
    rm -f "$tmppy"
}


# Reload xray config tanpa restart (tambah/hapus akun)
reload_xray() {
    _write_xray_config
    systemctl reload zv-xray 2>/dev/null || systemctl restart zv-xray 2>/dev/null
}

# Uninstall xray
uninstall_xray() {
    systemctl stop zv-xray &>/dev/null
    systemctl disable zv-xray &>/dev/null
    rm -f /etc/systemd/system/zv-xray.service
    rm -f "$XRAY_BIN"
    rm -rf "$XRAY_DIR"
    systemctl daemon-reload &>/dev/null
    print_ok "Xray-core dihapus."
}
