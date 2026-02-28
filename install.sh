#!/bin/bash
# ============================================================
#   ZV-Manager v1.0.0
#   SSH Tunneling Manager for Ubuntu 24.04 LTS
#   https://github.com/yourusername/ZV-Manager
# ============================================================

set -e

INSTALL_DIR="/etc/zv-manager"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Banner ---
clear
echo -e "\033[1;36m"
cat << 'EOF'
  ███████╗██╗   ██╗      ███╗   ███╗ █████╗ ███╗   ██╗ █████╗  ██████╗ ███████╗██████╗
  ╚══███╔╝██║   ██║      ████╗ ████║██╔══██╗████╗  ██║██╔══██╗██╔════╝ ██╔════╝██╔══██╗
    ███╔╝ ██║   ██║█████╗██╔████╔██║███████║██╔██╗ ██║███████║██║  ███╗█████╗  ██████╔╝
   ███╔╝  ╚██╗ ██╔╝╚════╝██║╚██╔╝██║██╔══██║██║╚██╗██║██╔══██║██║   ██║██╔══╝  ██╔══██╗
  ███████╗ ╚████╔╝       ██║ ╚═╝ ██║██║  ██║██║ ╚████║██║  ██║╚██████╔╝███████╗██║  ██║
  ╚══════╝  ╚═══╝        ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝
EOF
echo -e "\033[0m"
echo -e "\033[1;33m  SSH Tunneling Manager — Ubuntu 24.04 LTS\033[0m"
echo -e "\033[1;33m  Version 1.0.0\033[0m"
echo ""
echo -e "\033[0;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo ""

# --- Pre-checks sederhana sebelum load utils ---
if [[ "$EUID" -ne 0 ]]; then
    echo "[ERROR] Jalankan script ini sebagai root!"
    exit 1
fi

if [[ "$(uname -m)" != "x86_64" ]]; then
    echo "[ERROR] Arsitektur tidak didukung: $(uname -m)"
    exit 1
fi

echo "Press [Enter] untuk memulai instalasi, atau Ctrl+C untuk batal..."
read -r

# --- Copy semua file ke /etc/zv-manager ---
echo "[ INFO ] Menyalin file ke ${INSTALL_DIR}..."
mkdir -p "$INSTALL_DIR"
cp -r "$SCRIPT_DIR"/* "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR"/**/*.sh 2>/dev/null || true
chmod +x "$INSTALL_DIR"/*.sh 2>/dev/null || true
chmod +x "$INSTALL_DIR"/menu/**/*.sh 2>/dev/null || true
chmod +x "$INSTALL_DIR"/cron/*.sh 2>/dev/null || true

# --- Load utils ---
source "$INSTALL_DIR/utils/colors.sh"
source "$INSTALL_DIR/utils/logger.sh"
source "$INSTALL_DIR/utils/checker.sh"
source "$INSTALL_DIR/utils/helpers.sh"
source "$INSTALL_DIR/config.conf"

# --- Run system checks ---
print_section "Memeriksa Sistem"
run_all_checks

# --- Setup log ---
mkdir -p /var/log/zv-manager
timer_start

# --- Jalankan setiap tahap instalasi ---
source "$INSTALL_DIR/core/system.sh"
run_system_setup

source "$INSTALL_DIR/core/domain.sh"
setup_domain

source "$INSTALL_DIR/core/ssl.sh"
setup_ssl

source "$INSTALL_DIR/services/ssh/install.sh"
install_ssh

source "$INSTALL_DIR/services/dropbear/install.sh"
install_dropbear

source "$INSTALL_DIR/services/nginx/install.sh"
install_nginx

source "$INSTALL_DIR/services/websocket/install.sh"
install_websocket

source "$INSTALL_DIR/services/udp/install.sh"
install_udp_custom

# --- Setup Cron Jobs ---
print_section "Setup Cron Jobs"

cat > /etc/cron.d/zv-autokill <<EOF
# ZV-Manager - Auto Kill Multi-Login
*/1 * * * * root /bin/bash /etc/zv-manager/cron/autokill.sh
EOF

cat > /etc/cron.d/zv-expired <<EOF
# ZV-Manager - Auto Delete Expired Users
2 0 * * * root /bin/bash /etc/zv-manager/cron/expired.sh
EOF

service cron restart &>/dev/null
print_success "Cron Jobs"

# --- Setup menu command global ---
print_section "Setup Global Command"
ln -sf /etc/zv-manager/menu/menu.sh /usr/local/bin/menu
chmod +x /usr/local/bin/menu

# --- Simpan IP VPS ---
mkdir -p /etc/zv-manager/accounts
echo "$PUBLIC_IP" > /etc/zv-manager/accounts/ipvps

# --- Setup auto-login menu saat SSH ---
cat > /root/.profile <<'EOF'
if [ "$BASH" ]; then
    if [ -f ~/.bashrc ]; then
        . ~/.bashrc
    fi
fi
mesg n 2>/dev/null || true
menu
EOF

# --- Selesai ---
clear
echo -e "${BCYAN}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║        INSTALASI ZV-MANAGER SELESAI!             ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

local domain
domain=$(cat /etc/zv-manager/domain)
local ip="$PUBLIC_IP"

echo -e "  ${BWHITE}IP VPS      :${NC} ${BGREEN}${ip}${NC}"
echo -e "  ${BWHITE}Domain/Host :${NC} ${BGREEN}${domain}${NC}"
echo ""
echo -e "  ${BWHITE}OpenSSH     :${NC} ${BPURPLE}22, 500, 40000${NC}"
echo -e "  ${BWHITE}Dropbear    :${NC} ${BPURPLE}109, 143${NC}"
echo -e "  ${BWHITE}WS HTTP     :${NC} ${BPURPLE}80${NC}"
echo -e "  ${BWHITE}WS HTTPS    :${NC} ${BPURPLE}443${NC}"
echo -e "  ${BWHITE}UDP Custom  :${NC} ${BPURPLE}1-65535${NC}"
echo -e "  ${BWHITE}UDPGW       :${NC} ${BPURPLE}7100-7900${NC}"
echo ""
echo -e "  ${BYELLOW}Ketik 'menu' untuk membuka ZV-Manager${NC}"
echo ""

timer_end
echo ""
read -rp "  Reboot sekarang? [y/N]: " reboot_ans
[[ "$reboot_ans" =~ ^[Yy]$ ]] && reboot
