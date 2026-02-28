#!/bin/bash
# ============================================================
#   ZV-Manager - UDP Custom Installer
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/config.conf

install_udp_custom() {
    print_section "Install UDP Custom"

    mkdir -p /etc/zv-manager/udp

    # --- Config UDP Custom ---
    cat > /etc/zv-manager/udp/config.json <<EOF
{
    "listen": ":${UDP_PORT_START}-${UDP_PORT_END}",
    "password": "",
    "timeout": 60,
    "speed_limit": 0
}
EOF

    # Download binary udp-custom (coba dari beberapa sumber)
    print_info "Mendownload UDP Custom binary..."

    local binary_path="/etc/zv-manager/udp/udp-custom"
    local downloaded=false

    # Sumber 1 - GitHub releases
    if wget -q --timeout=30 -O "$binary_path" \
        "https://github.com/epro-dev/udp-custom/releases/latest/download/udp-custom-linux-amd64" 2>/dev/null; then
        downloaded=true
    fi

    # Fallback: compile badvpn dari sumber sebagai alternatif
    if [[ "$downloaded" == false ]]; then
        print_warning "UDP Custom binary gagal didownload, menggunakan BadVPN sebagai fallback..."
        install_badvpn_fallback
        return
    fi

    chmod +x "$binary_path"

    # --- Systemd Service ---
    cat > /etc/systemd/system/zv-udp.service <<EOF
[Unit]
Description=ZV-Manager UDP Custom Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zv-manager/udp
ExecStart=/etc/zv-manager/udp/udp-custom server
Restart=always
RestartSec=3s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable zv-udp &>/dev/null
    systemctl start zv-udp &>/dev/null

    print_success "UDP Custom (Port: 1-65535)"
}

install_badvpn_fallback() {
    print_section "Install BadVPN (Fallback UDP)"

    # Compile badvpn dari source
    apt-get install -y cmake make gcc libssl-dev &>/dev/null

    cd /tmp
    git clone https://github.com/ambrop72/badvpn.git &>/dev/null
    cd badvpn
    mkdir build && cd build
    cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 &>/dev/null
    make &>/dev/null
    cp udpgw/badvpn-udpgw /usr/local/bin/
    chmod +x /usr/local/bin/badvpn-udpgw
    cd /root && rm -rf /tmp/badvpn

    # Systemd service untuk badvpn (port 7100-7900)
    cat > /etc/systemd/system/zv-badvpn.service <<EOF
[Unit]
Description=ZV-Manager BadVPN UDPGW
After=network.target

[Service]
Type=simple
User=nobody
Group=nogroup
ExecStart=/bin/sh -c '\
    badvpn-udpgw --listen-addr 127.0.0.1:7100 --max-clients ${BADVPN_MAX_CLIENTS} & \
    badvpn-udpgw --listen-addr 127.0.0.1:7200 --max-clients ${BADVPN_MAX_CLIENTS} & \
    badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients ${BADVPN_MAX_CLIENTS} & \
    badvpn-udpgw --listen-addr 127.0.0.1:7400 --max-clients ${BADVPN_MAX_CLIENTS} & \
    badvpn-udpgw --listen-addr 127.0.0.1:7500 --max-clients ${BADVPN_MAX_CLIENTS} & \
    badvpn-udpgw --listen-addr 127.0.0.1:7600 --max-clients ${BADVPN_MAX_CLIENTS} & \
    badvpn-udpgw --listen-addr 127.0.0.1:7700 --max-clients ${BADVPN_MAX_CLIENTS} & \
    badvpn-udpgw --listen-addr 127.0.0.1:7800 --max-clients ${BADVPN_MAX_CLIENTS} & \
    exec badvpn-udpgw --listen-addr 127.0.0.1:7900 --max-clients ${BADVPN_MAX_CLIENTS}'
Restart=always
RestartSec=3s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable zv-badvpn &>/dev/null
    systemctl start zv-badvpn &>/dev/null

    print_success "BadVPN UDPGW (Port: 7100-7900)"
}
