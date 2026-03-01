#!/bin/bash
# ============================================================
#   ZV-Manager - Updater
#   wget -q https://raw.githubusercontent.com/ZenXNF/ZV-Manager/main/update.sh && bash update.sh
# ============================================================

if [[ "$EUID" -ne 0 ]]; then
    echo "[ERROR] Jalankan sebagai root!"
    exit 1
fi

echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║       Z V - M A N A G E R           ║"
echo "  ║  Updater                             ║"
echo "  ╚══════════════════════════════════════╝"
echo ""

# Cek git tersedia
if ! command -v git &>/dev/null; then
    echo "[ INFO ] Menginstall git..."
    apt-get install -y git &>/dev/null
fi

# Ambil update dari GitHub
if [[ ! -d /root/ZV-Manager/.git ]]; then
    echo "[ INFO ] Repo belum ada, clone fresh..."
    rm -rf /root/ZV-Manager
    git clone -q https://github.com/ZenXNF/ZV-Manager.git /root/ZV-Manager
else
    echo "[ INFO ] Mengambil update terbaru dari GitHub..."
    cd /root/ZV-Manager
    git fetch -q origin
    git reset -q --hard origin/main
fi

if [[ ! -d /root/ZV-Manager ]]; then
    echo "[ERROR] Gagal mengunduh update!"
    exit 1
fi

cd /root/ZV-Manager

# Chmod semua script
find . -name "*.sh" -exec chmod +x {} \;
find . -name "*.py" -exec chmod +x {} \;

echo "[ INFO ] Menyalin script ke /etc/zv-manager..."
# Salin HANYA file script — tidak menyentuh folder data
cp -r core /etc/zv-manager/
cp -r services /etc/zv-manager/
cp -r menu /etc/zv-manager/
cp -r utils /etc/zv-manager/
cp -r cron /etc/zv-manager/
cp config.conf /etc/zv-manager/
cp install.sh /etc/zv-manager/
cp update.sh /etc/zv-manager/
echo " ✔  Script diperbarui"

# Load utils untuk print functions
source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/config.conf

# Re-apply config service yang mungkin berubah
# Data aman: akun SSH, servers/, domain, ssl/ tidak disentuh

print_section "Apply Config Terbaru"

# --- Nginx ---
print_info "Apply config nginx..."
# Install stream module kalau belum ada
apt-get install -y libnginx-mod-stream &>/dev/null
source /etc/zv-manager/services/nginx/install.sh
install_nginx
print_ok "Nginx config diterapkan"

# --- WebSocket proxy ---
print_info "Apply config WebSocket..."
source /etc/zv-manager/services/websocket/install.sh
install_websocket
print_ok "WebSocket config diterapkan"

# --- SSH config (port & banner) ---
print_info "Apply config SSH..."
source /etc/zv-manager/services/ssh/install.sh
install_ssh
print_ok "SSH config diterapkan"

# --- Dropbear ---
print_info "Apply config Dropbear..."
source /etc/zv-manager/services/dropbear/install.sh
install_dropbear
print_ok "Dropbear config diterapkan"

# --- UDP Custom ---
print_info "Apply UDP Custom..."
source /etc/zv-manager/services/udp/install.sh
install_udp_custom
print_ok "UDP Custom diterapkan"

# --- Cron jobs ---
print_info "Apply cron jobs..."
cat > /etc/cron.d/zv-autokill <<'CRONEOF'
*/1 * * * * root /bin/bash /etc/zv-manager/cron/autokill.sh
CRONEOF
cat > /etc/cron.d/zv-expired <<'CRONEOF'
2 0 * * * root /bin/bash /etc/zv-manager/cron/expired.sh
CRONEOF
service cron restart &>/dev/null
print_ok "Cron jobs diterapkan"

# Pastikan menu command masih ada
ln -sf /etc/zv-manager/menu/menu.sh /usr/local/bin/menu
chmod +x /usr/local/bin/menu

echo ""
echo -e "${BCYAN}  ╔══════════════════════════════════════╗${NC}"
echo -e "${BCYAN}  ║      UPDATE SELESAI!                 ║${NC}"
echo -e "${BCYAN}  ╚══════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BWHITE}Yang diperbarui:${NC}"
echo -e "  ${BGREEN}✔${NC} Script (menu, services, utils, core)"
echo -e "  ${BGREEN}✔${NC} Config nginx (stream module untuk port 443)"
echo -e "  ${BGREEN}✔${NC} Config WebSocket, SSH, Dropbear"
echo ""
echo -e "  ${BWHITE}Yang tidak tersentuh:${NC}"
echo -e "  ${BYELLOW}✔${NC} Akun SSH yang sudah dibuat"
echo -e "  ${BYELLOW}✔${NC} Daftar server"
echo -e "  ${BYELLOW}✔${NC} Sertifikat SSL"
echo -e "  ${BYELLOW}✔${NC} Domain"
echo ""
echo -e "  ${BYELLOW}Ketik 'menu' untuk membuka ZV-Manager${NC}"
echo ""
