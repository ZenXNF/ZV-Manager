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

    # --- Systemd service untuk WS HTTP (port 80) ---
    cat > /etc/systemd/system/zv-ws.service <<EOF
[Unit]
Description=ZV-Manager WebSocket HTTP Proxy
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /usr/local/bin/zv-ws-proxy.py ${WS_PORT}
Restart=always
RestartSec=3s

[Install]
WantedBy=multi-user.target
EOF

    # --- Systemd service untuk WS HTTPS (443 via nginx) ---
    # Port 443 ditangani nginx, nginx forward ke WS proxy internal (port 8880)
    cat > /etc/systemd/system/zv-wss.service <<EOF
[Unit]
Description=ZV-Manager WebSocket HTTPS Internal Proxy
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
    systemctl enable zv-ws zv-wss &>/dev/null
    systemctl start zv-ws zv-wss &>/dev/null

    print_success "WebSocket Proxy (HTTP:${WS_PORT}, HTTPS via Nginx:${WSS_PORT})"
}
