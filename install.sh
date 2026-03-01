#!/bin/bash
# ============================================================
#   ZV-Manager v1.0.0
#   SSH Tunneling Manager for Ubuntu 24.04 LTS
#   https://github.com/ZenXNF/ZV-Manager
# ============================================================

INSTALL_DIR="/etc/zv-manager"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Buat log dir PERTAMA sebelum apapun ---
mkdir -p /var/log/zv-manager
touch /var/log/zv-manager/install.log

# --- Pre-checks sebelum load utils ---
if [[ "$EUID" -ne 0 ]]; then
    echo "[ERROR] Jalankan script ini sebagai root!"
    exit 1
fi

if [[ "$(uname -m)" != "x86_64" ]]; then
    echo "[ERROR] Arsitektur tidak didukung: $(uname -m)"
    exit 1
fi

# --- Banner mobile-friendly (lebar ~42 char) ---
clear
echo -e "\033[1;36m"
echo "  ╔══════════════════════════════════════╗"
echo "  ║       Z V - M A N A G E R           ║"
echo "  ║  SSH Tunneling Manager v1.0.0        ║"
echo "  ║  Ubuntu 24.04 LTS                    ║"
echo "  ╚══════════════════════════════════════╝"
echo -e "\033[0m"
echo -e "\033[0;36m  ──────────────────────────────────────\033[0m"
echo ""

# --- Konfirmasi mulai (mobile-friendly, tanpa Ctrl+C) ---
echo -e "\033[1;33m  Ketik y lalu Enter untuk mulai"
echo -e "  Ketik n lalu Enter untuk batal\033[0m"
echo ""
read -rp "  Mulai instalasi? [y/n]: " start_ans
if [[ ! "$start_ans" =~ ^[Yy]$ ]]; then
    echo ""
    echo "  Instalasi dibatalkan."
    exit 0
fi

echo ""
echo "[ INFO ] Menyalin file ke ${INSTALL_DIR}..."

# --- Copy semua file ke /etc/zv-manager ---
mkdir -p "$INSTALL_DIR"
cp -r "$SCRIPT_DIR"/* "$INSTALL_DIR/"

# chmod kompatibel tanpa globstar
find "$INSTALL_DIR" -name "*.sh" -exec chmod +x {} \;
find "$INSTALL_DIR" -name "*.py" -exec chmod +x {} \;

echo "[ INFO ] File berhasil disalin"
echo ""

# --- Load utils (dari SCRIPT_DIR karena file sudah pasti ada di sini) ---
source "$SCRIPT_DIR/utils/colors.sh"
source "$SCRIPT_DIR/utils/logger.sh"
source "$SCRIPT_DIR/utils/checker.sh"
source "$SCRIPT_DIR/utils/helpers.sh"
source "$SCRIPT_DIR/config.conf"

# --- Run system checks ---
print_section "Memeriksa Sistem"
run_all_checks

# --- Start timer ---
timer_start

# --- Instalasi tahap demi tahap ---
source "$INSTALL_DIR/core/system.sh"
run_system_setup

source "$INSTALL_DIR/core/domain.sh"
setup_domain   # otomatis ambil IP, tidak tanya user

source "$INSTALL_DIR/core/ssl.sh"
setup_ssl      # otomatis self-signed, tidak tanya user

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

cat > /etc/cron.d/zv-autokill <<'CRONEOF'
# ZV-Manager - Auto Kill Multi-Login
*/1 * * * * root /bin/bash /etc/zv-manager/cron/autokill.sh
CRONEOF

cat > /etc/cron.d/zv-expired <<'CRONEOF'
# ZV-Manager - Auto Delete Expired Users
2 0 * * * root /bin/bash /etc/zv-manager/cron/expired.sh
CRONEOF

service cron restart &>/dev/null
print_success "Cron Jobs"

# --- Setup menu command global ---
print_section "Setup Global Command"
mkdir -p /etc/zv-manager/servers
ln -sf /etc/zv-manager/menu/menu.sh /usr/local/bin/menu
chmod +x /usr/local/bin/menu
print_ok "Command 'menu' siap digunakan"

# --- Simpan IP VPS ---
mkdir -p /etc/zv-manager/accounts
echo "$PUBLIC_IP" > /etc/zv-manager/accounts/ipvps

# --- Setup auto-launch menu saat login SSH ---
# Cek interactive session dulu agar tidak konflik dengan Termius/automation
cat > /root/.profile <<'PROFILEEOF'
if [ "$BASH" ]; then
    if [ -f ~/.bashrc ]; then
        . ~/.bashrc
    fi
fi
mesg n 2>/dev/null || true

# Hanya jalankan menu jika:
# 1. Session benar-benar interactive (flag -i)
# 2. Ada terminal yang proper (stdout ke TTY)
# 3. Bukan session non-interactive seperti Termius HostOS detection / SCP / SFTP
case $- in
    *i*) ;;
    *) return ;;
esac
[ -t 1 ] || return
[ -z "$SSH_TTY" ] && return
# Jangan jalankan menu kalau ada command yang dikirim langsung (Termius detection)
[ -n "$SSH_ORIGINAL_COMMAND" ] && return

menu
PROFILEEOF

# --- Selesai ---
# clear dihapus — supaya output progress WebSocket & UDP tetap kelihatan

ZV_DOMAIN=$(cat /etc/zv-manager/domain 2>/dev/null || echo "$PUBLIC_IP")
ZV_IP="$PUBLIC_IP"

echo ""
echo -e "${BCYAN}"
echo "  ╔══════════════════════════════════════╗"
echo "  ║      INSTALASI SELESAI!              ║"
echo "  ╚══════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  ${BWHITE}IP VPS   :${NC} ${BGREEN}${ZV_IP}${NC}"
echo -e "  ${BWHITE}Host     :${NC} ${BGREEN}${ZV_DOMAIN}${NC}"
echo ""
echo -e "  ${BWHITE}OpenSSH  :${NC} ${BPURPLE}22, 500, 40000${NC}"
echo -e "  ${BWHITE}Dropbear :${NC} ${BPURPLE}109, 143${NC}"
echo -e "  ${BWHITE}WS HTTP  :${NC} ${BPURPLE}80${NC}"
echo -e "  ${BWHITE}WS HTTPS :${NC} ${BPURPLE}443${NC}"
echo -e "  ${BWHITE}UDP      :${NC} ${BPURPLE}1-65535${NC}"
echo ""

# --- Status service ringkas ---
echo -e "  ${BWHITE}Status Service:${NC}"
for svc in ssh dropbear nginx zv-wss zv-udp; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo -e "  ${BGREEN}✔${NC} ${svc}"
    else
        echo -e "  ${BRED}✘${NC} ${svc} — tidak aktif, cek: systemctl status ${svc}"
    fi
done
echo ""

echo -e "  ${BYELLOW}Ketik 'menu' untuk membuka ZV-Manager${NC}"
echo ""

timer_end
echo ""
echo -e "  ${BYELLOW}Reboot diperlukan agar semua service aktif.${NC}"
echo ""
read -rp "  Reboot sekarang? [y/n]: " reboot_ans
if [[ "$reboot_ans" =~ ^[Yy]$ ]]; then
    echo "  Rebooting..."
    sleep 2
    reboot
fi
