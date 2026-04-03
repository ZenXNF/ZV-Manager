#!/bin/bash
# ============================================================
#   ZV-Manager - WebSocket & SSL Proxy Installer
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/config.conf

# Fallback port default
WS_PORT=${WS_PORT:-80}
WSS_PORT=${WSS_PORT:-443}

install_websocket() {
    print_section "Install WebSocket Proxy"

    # Copy ws-proxy.py ke lokasi sistem
    cp /etc/zv-manager/services/websocket/ws-proxy.py /usr/local/bin/zv-ws-proxy.py
    chmod +x /usr/local/bin/zv-ws-proxy.py

    # Bersihkan service lama yang konflik
    systemctl stop zv-ws &>/dev/null
    systemctl disable zv-ws &>/dev/null
    rm -f /etc/systemd/system/zv-ws.service

    # --- ws-proxy internal port 8880 ---
    # Menerima koneksi dari:
    #   - nginx port 80 (WS non-SSL)
    cat > /etc/systemd/system/zv-wss.service <<EOF
[Unit]
Description=ZV-Manager WebSocket & HTTP CONNECT Proxy (Internal)
After=network.target
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 -u /usr/local/bin/zv-ws-proxy.py 8880
Restart=always
RestartSec=5s
# Batasi RAM — cukup untuk 200 koneksi di VPS 512MB/1GB
MemoryMax=80M
MemorySwapMax=0

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable zv-wss &>/dev/null
    systemctl restart zv-wss &>/dev/null

    # Stunnel tidak digunakan lagi — SSL 443 dihandle langsung oleh Nginx

    sleep 1
    print_success "WebSocket Proxy (Internal port 8880 — dilayani Nginx port ${WS_PORT} non-SSL & port ${WSS_PORT} SSL)"
}
