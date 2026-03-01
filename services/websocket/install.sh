#!/bin/bash
# ============================================================
#   ZV-Manager - WebSocket Service Installer
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/config.conf

install_websocket() {
    print_section "Install WebSocket Proxy"

    # Copy ws-proxy.py ke lokasi sistem
    cp /etc/zv-manager/services/websocket/ws-proxy.py /usr/local/bin/zv-ws-proxy.py
    chmod +x /usr/local/bin/zv-ws-proxy.py

    # --- Bersihkan service lama yang konflik ---
    # zv-ws.service lama bind ke port 80 langsung, konflik dengan nginx
    # Sekarang nginx yang handle port 80, lalu forward ke 8880 (ws-proxy internal)
    systemctl stop zv-ws &>/dev/null
    systemctl disable zv-ws &>/dev/null
    rm -f /etc/systemd/system/zv-ws.service

    # --- Satu-satunya WS proxy: internal port 8880 ---
    # Nginx port 80  → proxy_pass 127.0.0.1:8880  (HTTP WS)
    # Nginx port 443 → stream proxy 127.0.0.1:8880 (HTTPS / HTTP CONNECT)
    # Jadi hanya butuh SATU instance ws-proxy di port 8880
    cat > /etc/systemd/system/zv-wss.service <<EOF
[Unit]
Description=ZV-Manager WebSocket & HTTP CONNECT Proxy (Internal)
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /usr/local/bin/zv-ws-proxy.py 8880
Restart=always
RestartSec=3s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable zv-wss &>/dev/null
    systemctl restart zv-wss &>/dev/null

    print_success "WebSocket Proxy (Internal port 8880 — dilayani Nginx di port ${WS_PORT} & ${WSS_PORT})"
}
