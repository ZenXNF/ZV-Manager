#!/bin/bash
# ============================================================
#   ZV-Manager - Dropbear Installer
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/config.conf

install_dropbear() {
    print_section "Install Dropbear"

    apt-get install -y dropbear &>/dev/null

    # Konfigurasi dropbear
    cat > /etc/default/dropbear <<EOF
# ZV-Manager - Dropbear Config
NO_START=0
DROPBEAR_PORT=${DROPBEAR_PORT}
DROPBEAR_EXTRA_ARGS="-p ${DROPBEAR_PORT_2}"
DROPBEAR_BANNER="/etc/issue.net"
DROPBEAR_RECEIVE_WINDOW=65536
EOF

    systemctl enable dropbear &>/dev/null
    systemctl restart dropbear &>/dev/null

    print_success "Dropbear (Port: ${DROPBEAR_PORT}, ${DROPBEAR_PORT_2})"
}
