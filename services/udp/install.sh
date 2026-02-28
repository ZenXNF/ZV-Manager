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

    local binary_path="/etc/zv-manager/udp/udp-custom"

    print_info "Mendownload UDP Custom binary..."

    # Download binary
    wget -q --timeout=30 -O "$binary_path" \
        "https://github.com/epro-dev/udp-custom/releases/latest/download/udp-custom-linux-amd64" 2>/dev/null

    # Cek apakah binary valid (lebih dari 10KB)
    local filesize
    filesize=$(stat -c%s "$binary_path" 2>/dev/null || echo 0)

    if [[ "$filesize" -lt 10240 ]]; then
        rm -f "$binary_path"
        print_warning "UDP Custom gagal atau tidak valid, compile BadVPN..."
        install_badvpn_fallback
        return
    fi

    chmod +x "$binary_path"

    cat > /etc/systemd/system/zv-udp.service <<SVCEOF
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
SVCEOF

    systemctl daemon-reload
    systemctl enable zv-udp &>/dev/null
    systemctl start zv-udp &>/dev/null

    print_success "UDP Custom (Port: 1-65535)"
}

install_badvpn_fallback() {
    print_section "Install BadVPN (Fallback UDP)"

    # Build tools hanya diinstall di sini kalau memang dibutuhkan
    print_info "Menginstall build tools untuk BadVPN..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y build-essential gcc cmake make libssl-dev git &>/dev/null
    print_ok "Build tools siap"

    print_info "Mengunduh & compile BadVPN... (ini butuh beberapa menit)"
    cd /tmp
    rm -rf badvpn
    git clone -q https://github.com/ambrop72/badvpn.git
    cd badvpn
    mkdir build && cd build
    cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 &>/dev/null
    make &>/dev/null
    cp udpgw/badvpn-udpgw /usr/local/bin/
    chmod +x /usr/local/bin/badvpn-udpgw
    cd /root && rm -rf /tmp/badvpn
    print_ok "BadVPN berhasil di-compile"

    cat > /etc/systemd/system/zv-badvpn.service <<SVCEOF
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
SVCEOF

    systemctl daemon-reload
    systemctl enable zv-badvpn &>/dev/null
    systemctl start zv-badvpn &>/dev/null

    print_success "BadVPN UDPGW (Port: 7100-7900)"
}
