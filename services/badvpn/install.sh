#!/bin/bash
# ============================================================
#   ZV-Manager - BadVPN UDPGW Installer
#   Dibutuhkan untuk support UDP di NetMod dan aplikasi serupa
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh

install_badvpn() {
    print_section "Install BadVPN UDPGW"

    local binary_path="/usr/local/bin/badvpn-udpgw"

    # Kalau binary sudah ada, skip compile
    if [[ -f "$binary_path" ]]; then
        print_info "badvpn-udpgw sudah ada, skip compile..."
    else
        print_info "Menginstall dependencies build..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y \
            cmake build-essential libssl-dev &>/dev/null

        print_info "Compile badvpn-udpgw dari source..."
        rm -rf /tmp/badvpn
        if ! git clone -q https://github.com/ambrop72/badvpn.git /tmp/badvpn 2>/dev/null; then
            print_error "Gagal clone repo badvpn!"
            return 1
        fi

        cd /tmp/badvpn
        if ! cmake -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 . &>/dev/null; then
            print_error "Gagal cmake badvpn!"
            rm -rf /tmp/badvpn
            return 1
        fi

        if ! make &>/dev/null; then
            print_error "Gagal compile badvpn!"
            rm -rf /tmp/badvpn
            return 1
        fi

        cp udpgw/badvpn-udpgw "$binary_path"
        chmod +x "$binary_path"
        rm -rf /tmp/badvpn
        cd ~
        print_ok "badvpn-udpgw berhasil dikompilasi"
    fi

    # Systemd service
    cat > /etc/systemd/system/zv-badvpn.service <<'SVCEOF'
[Unit]
Description=ZV-Manager BadVPN UDPGW
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 500 --max-connections-for-client 10
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SVCEOF

    systemctl daemon-reload
    systemctl enable zv-badvpn &>/dev/null

    # Restart kalau sudah jalan, start kalau belum
    if systemctl is-active --quiet zv-badvpn; then
        systemctl restart zv-badvpn &>/dev/null
    else
        systemctl start zv-badvpn &>/dev/null
    fi

    sleep 1
    if systemctl is-active --quiet zv-badvpn; then
        print_success "BadVPN UDPGW (Port: 7300)"
    else
        print_error "BadVPN UDPGW gagal start! Cek: systemctl status zv-badvpn"
    fi
}
