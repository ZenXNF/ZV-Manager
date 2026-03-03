#!/bin/bash
# ============================================================
#   ZV-Manager - BadVPN UDPGW Installer
#   Download pre-compiled binary dari GitHub Releases
#   Repo: https://github.com/ZenXNF/ZV-Manager
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh

# URL binary di GitHub Releases
BADVPN_RELEASE_URL="https://github.com/ZenXNF/ZV-Manager/releases/latest/download/badvpn-udpgw"

install_badvpn() {
    print_section "Install BadVPN UDPGW"

    local binary_path="/usr/local/bin/badvpn-udpgw"

    # Kalau binary sudah ada, skip download
    if [[ -f "$binary_path" ]]; then
        print_info "badvpn-udpgw sudah ada, skip download..."
    else
        print_info "Mengunduh badvpn-udpgw dari GitHub Releases..."

        if command -v wget &>/dev/null; then
            wget -q --timeout=30 -O "$binary_path" "$BADVPN_RELEASE_URL"
        elif command -v curl &>/dev/null; then
            curl -sL --max-time 30 -o "$binary_path" "$BADVPN_RELEASE_URL"
        else
            print_error "wget / curl tidak tersedia!"
            return 1
        fi

        # Validasi hasil download — bukan HTML error page
        if [[ ! -s "$binary_path" ]] || file "$binary_path" 2>/dev/null | grep -q "HTML\|text"; then
            rm -f "$binary_path"
            print_error "Download gagal atau file tidak valid!"
            print_info "Fallback: compile dari source..."
            _compile_badvpn "$binary_path" || return 1
        else
            chmod +x "$binary_path"
            print_ok "badvpn-udpgw berhasil diunduh"
        fi
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

# Fallback: compile dari source kalau download gagal
_compile_badvpn() {
    local binary_path="$1"

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
    print_ok "badvpn-udpgw berhasil dikompilasi (fallback)"
}
