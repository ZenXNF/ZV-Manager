#!/bin/bash
# ============================================================
#   ZV-Manager - UDP Custom Installer
#   Binary: ePro Dev (http-custom/udp-custom)
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/config.conf

install_udp_custom() {
    print_section "Install UDP Custom"

    mkdir -p /etc/zv-manager/udp

    local binary_path="/etc/zv-manager/udp/udp-custom"

    print_info "Mengunduh UDP Custom dari GitHub..."
    rm -rf /tmp/udp-custom-src

    if ! git clone -q --depth=1 https://github.com/http-custom/udp-custom.git /tmp/udp-custom-src 2>/dev/null; then
        print_error "Gagal clone repo UDP Custom! Cek koneksi internet."
        return 1
    fi

    # Binary ada di bin/udp-custom-linux-amd64
    if [[ ! -f /tmp/udp-custom-src/bin/udp-custom-linux-amd64 ]]; then
        print_error "Binary UDP Custom tidak ditemukan!"
        rm -rf /tmp/udp-custom-src
        return 1
    fi

    cp /tmp/udp-custom-src/bin/udp-custom-linux-amd64 "$binary_path"
    chmod +x "$binary_path"
    rm -rf /tmp/udp-custom-src
    print_ok "UDP Custom binary siap (ePro Dev)"

    # Config — UDP_PORT adalah internal listener binary
    # Binary otomatis intercept semua UDP port 1-65535 via iptables TPROXY
    cat > /etc/zv-manager/udp/config.json <<CFGEOF
{
  "listen": ":${UDP_PORT}",
  "stream_buffer": 33554432,
  "receive_buffer": 83886080,
  "auth": {
    "mode": "passwords"
  }
}
CFGEOF

    # Systemd service
    cat > /etc/systemd/system/zv-udp.service <<SVCEOF
[Unit]
Description=ZV-Manager UDP Custom (ePro Dev)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zv-manager/udp
ExecStart=/etc/zv-manager/udp/udp-custom server
Restart=always
RestartSec=2s

[Install]
WantedBy=multi-user.target
SVCEOF

    systemctl daemon-reload
    systemctl enable zv-udp &>/dev/null
    systemctl start zv-udp &>/dev/null

    sleep 2
    if systemctl is-active --quiet zv-udp; then
        print_success "UDP Custom (Port: 1-65535 via TPROXY, listener: ${UDP_PORT})"
    else
        print_error "UDP Custom gagal start! Cek: systemctl status zv-udp"
    fi
}
