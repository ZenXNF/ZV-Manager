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

    # ── 5. Update nginx — tambah routing VMess ──────────────
    _update_nginx_vmess

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
    # Kumpulkan semua akun VMess yang sudah ada
    local clients_json=""
    for conf in "${XRAY_ACCT_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue
        local uuid
        uuid=$(grep "^UUID=" "$conf" | cut -d= -f2 | tr -d '"')
        [[ -z "$uuid" ]] && continue
        [[ -n "$clients_json" ]] && clients_json+=","
        clients_json+="{\"id\":\"${uuid}\",\"alterId\":0}"
    done
    [[ -z "$clients_json" ]] && clients_json='{"id":"00000000-0000-0000-0000-000000000000","alterId":0}'

    cat > "${XRAY_DIR}/config.json" <<JSONEOF
{
  "log": {
    "loglevel": "warning",
    "error": "/var/log/xray-error.log"
  },
  "inbounds": [
    {
      "tag": "vmess-ws",
      "listen": "127.0.0.1",
      "port": 10001,
      "protocol": "vmess",
      "settings": {
        "clients": [${clients_json}]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vmess"
        }
      }
    },
    {
      "tag": "vmess-grpc",
      "listen": "127.0.0.1",
      "port": 10002,
      "protocol": "vmess",
      "settings": {
        "clients": [${clients_json}]
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "vmess-grpc"
        }
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom"
    }
  ]
}
JSONEOF
}

_update_nginx_vmess() {
    local domain
    domain=$(cat /etc/zv-manager/domain 2>/dev/null)

    # Cek apakah sudah ada nginx vmess conf
    if grep -q "vmess" /etc/nginx/nginx.conf 2>/dev/null; then
        return 0
    fi

    # Tambah location /vmess di server port 80
    # dan tambah server baru port 443 untuk gRPC
    local nginx_conf="/etc/nginx/nginx.conf"

    # Inject location /vmess sebelum closing } di server port 80
    sed -i '/proxy_buffering off;/{
        a\        }
        a\
        a\        location /vmess {
        a\            proxy_pass http://127.0.0.1:10001;
        a\            proxy_http_version 1.1;
        a\            proxy_set_header Upgrade $http_upgrade;
        a\            proxy_set_header Connection $connection_upgrade;
        a\            proxy_set_header Host $host;
        a\            proxy_set_header X-Real-IP $remote_addr;
        a\            proxy_read_timeout 3600s;
        a\            proxy_send_timeout 3600s;
        a\            proxy_buffering off;
    }' "$nginx_conf" 2>/dev/null || true

    # Tambah server block gRPC port 8443 (ssl termination via cert)
    if [[ -f "$SSL_CERT" && -f "$SSL_KEY" ]]; then
        # Inject sebelum baris terakhir }
        sed -i "$ i\\
\\
    # VMess gRPC (port 8443, TLS)\\
    server {\\
        listen 8443 ssl http2;\\
        server_name ${domain} _;\\
        ssl_certificate ${SSL_CERT};\\
        ssl_certificate_key ${SSL_KEY};\\
        location /vmess-grpc {\\
            grpc_pass grpc://127.0.0.1:10002;\\
            grpc_set_header Host \$host;\\
        }\\
    }" "$nginx_conf" 2>/dev/null || true
    fi

    nginx -t &>/dev/null && systemctl reload nginx &>/dev/null || true
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
