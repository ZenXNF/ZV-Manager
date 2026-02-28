#!/bin/bash
# ============================================================
#   ZV-Manager - UDP Custom Installer
#   Binary: ePro Dev (via noobconner21/UDP-Custom-Script)
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/config.conf

install_udp_custom() {
    print_section "Install UDP Custom"

    mkdir -p /etc/zv-manager/udp

    local binary_path="/etc/zv-manager/udp/udp-custom"
    local binary_url="https://github.com/noobconner21/UDP-Custom-Script/raw/main/udp-custom-linux-amd64"

    # Download binary
    print_info "Mendownload UDP Custom binary (ePro Dev)..."
    wget -q --timeout=30 -O "$binary_path" "$binary_url" 2>/dev/null

    # Validasi binary (harus lebih dari 1MB)
    local filesize
    filesize=$(stat -c%s "$binary_path" 2>/dev/null || echo 0)

    if [[ "$filesize" -lt 1048576 ]]; then
        rm -f "$binary_path"
        print_error "Download UDP Custom gagal atau file tidak valid!"
        print_info "Skip UDP Custom, install manual nanti via menu."
        return 1
    fi

    chmod +x "$binary_path"
    print_ok "UDP Custom binary siap"

    # Config — listen semua port, mode password
    cat > /etc/zv-manager/udp/config.json <<CFGEOF
{
  "listen": ":${UDP_PORT_START}-${UDP_PORT_END}",
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
RestartSec=3s

[Install]
WantedBy=multi-user.target
SVCEOF

    systemctl daemon-reload
    systemctl enable zv-udp &>/dev/null
    systemctl start zv-udp &>/dev/null

    # Verifikasi
    sleep 2
    if systemctl is-active --quiet zv-udp; then
        print_success "UDP Custom (Port: ${UDP_PORT_START}-${UDP_PORT_END})"
    else
        print_error "UDP Custom gagal start! Cek: systemctl status zv-udp"
    fi
}
