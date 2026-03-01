#!/bin/bash
# ============================================================
#   ZV-Manager - WebSocket & SSL Proxy Installer
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/config.conf

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
    #   - stunnel port 443 (WS SSL / HTTP CONNECT)
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

    # --- Install stunnel4 untuk SSL port 443 ---
    # Arsitektur: client → stunnel:443 (SSL termination) → ws-proxy:8880 (raw TCP)
    # Stunnel jauh lebih reliable dari nginx stream untuk use case ini
    # karena tidak ada buffering dan langsung forward byte-per-byte
    apt-get install -y stunnel4 &>/dev/null

    local ssl_cert="/etc/zv-manager/ssl/cert.pem"
    local ssl_key="/etc/zv-manager/ssl/key.pem"

    # Config stunnel
    cat > /etc/stunnel/zv-wss.conf <<STCONF
; ZV-Manager WSS/HTTPS proxy
; SSL termination → forward ke ws-proxy internal

; Jangan run sebagai daemon — systemd yang handle
foreground = yes
pid = /var/run/stunnel-zv.pid

; Log minimal
debug = 0
output = /var/log/stunnel-zv.log

[wss]
accept  = 0.0.0.0:${WSS_PORT}
connect = 127.0.0.1:8880
cert    = ${ssl_cert}
key     = ${ssl_key}

; Protokol SSL yang diizinkan
sslVersion = all
options = NO_SSLv2
options = NO_SSLv3
STCONF

    # Systemd service untuk stunnel
    cat > /etc/systemd/system/zv-stunnel.service <<SVCEOF
[Unit]
Description=ZV-Manager SSL Tunnel (port 443 → ws-proxy)
After=network.target zv-wss.service
Requires=zv-wss.service

[Service]
Type=simple
ExecStart=/usr/bin/stunnel4 /etc/stunnel/zv-wss.conf
Restart=always
RestartSec=3s

[Install]
WantedBy=multi-user.target
SVCEOF

    systemctl daemon-reload
    systemctl enable zv-stunnel &>/dev/null
    systemctl restart zv-stunnel &>/dev/null

    sleep 2
    if systemctl is-active --quiet zv-stunnel; then
        print_success "WebSocket Proxy (Internal port 8880 — dilayani Nginx di port ${WS_PORT} & Stunnel di port ${WSS_PORT})"
    else
        print_error "Stunnel gagal start! Cek: systemctl status zv-stunnel"
    fi
}
