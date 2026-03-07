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

# Chmod semua script dan binary
find . -name "*.sh" -exec chmod +x {} \;
find . -name "*.py" -exec chmod +x {} \;
chmod +x checker/zv-checker 2>/dev/null

# --- Cek izin sebelum apply update ---
source /etc/zv-manager/core/license.sh
check_license

echo "[ INFO ] Menyalin script ke /etc/zv-manager..."
cp -r core /etc/zv-manager/
cp -r services /etc/zv-manager/
cp -r menu /etc/zv-manager/
cp -r utils /etc/zv-manager/
cp -r cron /etc/zv-manager/
cp -r checker /etc/zv-manager/
chmod +x /etc/zv-manager/checker/zv-checker
chmod +x /etc/zv-manager/services/telegram/bot.py 2>/dev/null || true
cp config.conf /etc/zv-manager/
cp install.sh /etc/zv-manager/
cp update.sh /etc/zv-manager/
cp zv-agent.sh /etc/zv-manager/
NEW_HASH=$(git -C /root/ZV-Manager rev-parse --short HEAD 2>/dev/null || echo "unknown")
sed -i "s/^COMMIT_HASH=.*/COMMIT_HASH=\"${NEW_HASH}\"/" /etc/zv-manager/config.conf
echo " ✔  Script diperbarui (#${NEW_HASH})"

# --- Update zv-agent binary ---
cp /etc/zv-manager/zv-agent.sh /usr/local/bin/zv-agent
chmod +x /usr/local/bin/zv-agent
echo " ✔  zv-agent diperbarui"

# --- Update Telegram bot (Python) ---
if [[ -d /etc/zv-manager/services/telegram ]]; then
    BOT_DIR="/opt/zv-telegram"
    mkdir -p "$BOT_DIR"

    # Hapus file lama
    rm -f /usr/local/bin/zv-telegram-bot /usr/local/bin/zv-telegram-bot.py

    # Deploy semua modul ke /opt/zv-telegram/
    cp -r /etc/zv-manager/services/telegram/. "$BOT_DIR/"
    find "$BOT_DIR" -name "*.py" -exec chmod +x {} \;

    # Update aiogram kalau perlu
    pip3 install -q "aiogram==3.*" --break-system-packages 2>/dev/null || \
    pip3 install -q "aiogram==3.*" 2>/dev/null

    # Update systemd service — selalu pakai WorkingDirectory + path baru
    cat > /etc/systemd/system/zv-telegram.service <<'SVCEOF'
[Unit]
Description=ZV-Manager Telegram Bot (Python)
After=network.target
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
Type=simple
WorkingDirectory=/opt/zv-telegram
ExecStart=/usr/bin/python3 -u /opt/zv-telegram/bot.py
Restart=always
RestartSec=10s
MemoryMax=120M
MemorySwapMax=0
CPUQuota=60%
StandardOutput=append:/var/log/zv-manager/telegram-bot.log
StandardError=append:/var/log/zv-manager/telegram-bot.log

[Install]
WantedBy=multi-user.target
SVCEOF
    systemctl daemon-reload
    if systemctl is-active --quiet zv-telegram 2>/dev/null; then
        systemctl restart zv-telegram &>/dev/null
        echo " ✔  Telegram bot diperbarui & di-restart"
    else
        systemctl enable zv-telegram &>/dev/null
        systemctl start zv-telegram &>/dev/null
        echo " ✔  Telegram bot diperbarui & dijalankan"
    fi
fi

# Load utils
source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/config.conf

print_section "Apply Config Terbaru"

# --- Nginx ---
print_info "Apply config nginx..."
source /etc/zv-manager/services/nginx/install.sh
install_nginx
print_ok "Nginx config diterapkan"

# --- WebSocket + Stunnel ---
print_info "Apply config WebSocket..."
source /etc/zv-manager/services/websocket/install.sh
install_websocket
print_ok "WebSocket config diterapkan"

# --- SSH ---
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

# --- BadVPN UDPGW ---
print_info "Apply BadVPN UDPGW..."
source /etc/zv-manager/services/badvpn/install.sh
install_badvpn

# Reload xray config jika terinstall
if [[ -f "/usr/local/bin/xray" ]]; then
    source /etc/zv-manager/services/xray/install.sh
    reload_xray
    print_ok "Xray config di-reload"
fi

# --- Cron jobs ---
print_info "Apply cron jobs..."
cat > /etc/cron.d/zv-autokill <<'CRONEOF'
# ZV-Manager - Auto Kill Multi-Login
*/1 * * * * root /bin/bash /etc/zv-manager/cron/autokill.sh
CRONEOF

cat > /etc/cron.d/zv-status-page <<'CRONEOF'
# ZV-Manager - Generate Status Page
*/5 * * * * root /bin/bash /etc/zv-manager/cron/status-page.sh
CRONEOF

mkdir -p /var/lib/zv-manager/status

cat > /etc/cron.d/zv-expired <<'CRONEOF'
# ZV-Manager - Auto Delete Expired Users
2 0 * * * root /bin/bash /etc/zv-manager/cron/expired.sh
CRONEOF

cat > /etc/cron.d/zv-license <<'CRONEOF'
# ZV-Manager - Cek Izin Harian (jam 00:05)
5 0 * * * root /bin/bash /etc/zv-manager/cron/license-check.sh
0 7 * * * root /bin/bash /etc/zv-manager/cron/daily-report.sh
CRONEOF

cat > /etc/cron.d/zv-bandwidth <<'CRONEOF'
# ZV-Manager - Cek Bandwidth tiap 5 menit
*/5 * * * * root /bin/bash /etc/zv-manager/cron/bw-check.sh
CRONEOF

cat > /etc/cron.d/zv-check-update <<'CRONEOF'
# ZV-Manager - Cek Update sekali sehari jam 06:00
0 6 * * * root /bin/bash /etc/zv-manager/cron/check-update.sh
CRONEOF

cat > /etc/cron.d/zv-backup <<'CRONEOF'
# ZV-Manager - Backup harian jam 02:00
0 2 * * * root /bin/bash /etc/zv-manager/cron/backup.sh
CRONEOF

service cron restart &>/dev/null
# Jalankan cek update sekali sekarang (background, tidak blocking)
/bin/bash /etc/zv-manager/cron/check-update.sh &>/dev/null &
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
echo -e "  ${BGREEN}✔${NC} Config Nginx, Stunnel SSL, WebSocket"
echo -e "  ${BGREEN}✔${NC} Config SSH, Dropbear, UDP Custom"
echo -e "  ${BGREEN}✔${NC} Binary zv-checker (sistem izin)"
echo -e "  ${BGREEN}✔${NC} zv-agent (manajemen remote server)"
echo ""
echo -e "  ${BWHITE}Yang tidak tersentuh:${NC}"
echo -e "  ${BYELLOW}✔${NC} Akun SSH yang sudah dibuat"
echo -e "  ${BYELLOW}✔${NC} Daftar server"
echo -e "  ${BYELLOW}✔${NC} Sertifikat SSL"
echo -e "  ${BYELLOW}✔${NC} Domain"
echo ""
echo -e "  ${BYELLOW}Ketik 'menu' untuk membuka ZV-Manager${NC}"
echo ""
