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
cp zv-vmess-agent.sh /etc/zv-manager/
NEW_HASH=$(git -C /root/ZV-Manager rev-parse --short HEAD 2>/dev/null || echo "unknown")
sed -i "s/^COMMIT_HASH=.*/COMMIT_HASH=\"${NEW_HASH}\"/" /etc/zv-manager/config.conf
echo " ✔  Script diperbarui (#${NEW_HASH})"

# --- Update zv-agent binary ---
cp /etc/zv-manager/zv-agent.sh /usr/local/bin/zv-agent
chmod +x /usr/local/bin/zv-agent
echo " ✔  zv-agent diperbarui"
# --- Update zv-vmess-agent binary ---
cp /etc/zv-manager/zv-vmess-agent.sh /usr/local/bin/zv-vmess-agent
chmod +x /usr/local/bin/zv-vmess-agent
echo " ✔  zv-vmess-agent diperbarui"

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

print_section "Cek & Update Komponen"

# ── Helper cek versi ──────────────────────────────────────────
_pkg_installed() { dpkg -l "$1" 2>/dev/null | grep -q "^ii"; }

_xray_latest_version() {
    curl -s --max-time 10 \
        "https://api.github.com/repos/XTLS/Xray-core/releases/latest" \
        | grep '"tag_name"' | head -1 | grep -oP 'v[\d.]+' || echo ""
}

_xray_current_version() {
    /usr/local/bin/xray version 2>/dev/null | grep -oP 'Xray \K[\d.]+' | head -1 || echo ""
}

# ── 1. Xray-core ─────────────────────────────────────────────
print_info "Mengecek Xray-core..."
if [[ ! -f "/usr/local/bin/xray" ]]; then
    print_info "Xray belum ada, menginstall..."
    source /etc/zv-manager/services/xray/install.sh
    install_xray
    print_ok "Xray-core terinstall"
else
    current_xray=$(_xray_current_version)
    latest_xray=$(_xray_latest_version)
    # Strip 'v' prefix untuk perbandingan
    latest_xray_clean="${latest_xray#v}"
    if [[ -n "$latest_xray_clean" && "$current_xray" != "$latest_xray_clean" ]]; then
        print_info "Xray update: v${current_xray} → ${latest_xray}"
        ARCH=$(uname -m)
        case "$ARCH" in
            x86_64)  ARCH_TAG="64" ;;
            aarch64) ARCH_TAG="arm64-v8a" ;;
            *)       ARCH_TAG="64" ;;
        esac
        tmpdir=$(mktemp -d)
        dl_url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${ARCH_TAG}.zip"
        if wget -q --show-progress -O "${tmpdir}/xray.zip" "$dl_url"; then
            apt-get install -y unzip &>/dev/null
            unzip -q "${tmpdir}/xray.zip" -d "${tmpdir}/xray"
            systemctl stop zv-xray 2>/dev/null
            install -m 755 "${tmpdir}/xray/xray" /usr/local/bin/xray
            systemctl start zv-xray 2>/dev/null
            print_ok "Xray-core diupdate ke ${latest_xray}"
        else
            print_info "Gagal download Xray, skip update"
        fi
        rm -rf "$tmpdir"
    else
        print_ok "Xray-core sudah terbaru (v${current_xray}), skip"
    fi
    # Pastikan config Xray sudah punya HandlerService
    if ! grep -q "HandlerService" /usr/local/etc/xray/config.json 2>/dev/null; then
        print_info "Menambahkan HandlerService ke config Xray..."
        source /etc/zv-manager/services/xray/install.sh
        install_xray
        print_ok "Xray config diperbarui"
    fi
fi

# ── 2. BadVPN UDPGW ──────────────────────────────────────────
print_info "Mengecek BadVPN UDPGW..."
source /etc/zv-manager/services/badvpn/install.sh
if [[ ! -f "/usr/local/bin/badvpn-udpgw" ]]; then
    print_info "BadVPN belum ada, menginstall..."
    install_badvpn
    print_ok "BadVPN terinstall"
else
    print_ok "BadVPN sudah ada, skip"
fi

# ── 3. Nginx ─────────────────────────────────────────────────
print_info "Mengecek Nginx..."
if ! _pkg_installed nginx; then
    print_info "Nginx belum ada, menginstall..."
    source /etc/zv-manager/services/nginx/install.sh
    install_nginx
    print_ok "Nginx terinstall"
else
    print_ok "Nginx sudah ada, apply config terbaru..."
    source /etc/zv-manager/services/nginx/install.sh
    install_nginx
fi

# ── 4. Dropbear ───────────────────────────────────────────────
print_info "Mengecek Dropbear..."
if ! _pkg_installed dropbear; then
    print_info "Dropbear belum ada, menginstall..."
    source /etc/zv-manager/services/dropbear/install.sh
    install_dropbear
    print_ok "Dropbear terinstall"
else
    print_ok "Dropbear sudah ada, apply config terbaru..."
    source /etc/zv-manager/services/dropbear/install.sh
    install_dropbear
fi

# ── 5. WebSocket + Stunnel ────────────────────────────────────
print_info "Mengecek WebSocket/Stunnel..."
source /etc/zv-manager/services/websocket/install.sh
install_websocket
print_ok "WebSocket config diterapkan"

# ── 6. SSH ────────────────────────────────────────────────────
print_info "Apply config SSH..."
source /etc/zv-manager/services/ssh/install.sh
install_ssh
print_ok "SSH config diterapkan"

# ── 7. UDP Custom ─────────────────────────────────────────────
print_info "Mengecek UDP Custom..."
source /etc/zv-manager/services/udp/install.sh
install_udp_custom
print_ok "UDP Custom diterapkan"

# ── 8. Python aiogram ─────────────────────────────────────────
print_info "Mengecek aiogram (Python)..."
current_aiogram=$(pip3 show aiogram 2>/dev/null | grep "^Version:" | awk '{print $2}')
if [[ -z "$current_aiogram" ]]; then
    print_info "aiogram belum ada, menginstall..."
    pip3 install -q "aiogram==3.*" --break-system-packages 2>/dev/null || \
    pip3 install -q "aiogram==3.*" 2>/dev/null
    print_ok "aiogram terinstall"
else
    print_ok "aiogram sudah ada (v${current_aiogram}), skip"
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
echo -e "  ${BWHITE}Yang dicek & diperbarui:${NC}"
echo -e "  ${BGREEN}✔${NC} Script (menu, services, utils, core)"
echo -e "  ${BGREEN}✔${NC} Xray-core (cek versi, auto update jika ada)"
echo -e "  ${BGREEN}✔${NC} BadVPN UDPGW (install jika belum ada)"
echo -e "  ${BGREEN}✔${NC} Nginx, Stunnel SSL, WebSocket"
echo -e "  ${BGREEN}✔${NC} SSH, Dropbear, UDP Custom"
echo -e "  ${BGREEN}✔${NC} aiogram Python (install jika belum ada)"
echo -e "  ${BGREEN}✔${NC} Binary zv-agent, zv-vmess-agent, zv-checker"
echo ""
echo -e "  ${BWHITE}Yang tidak tersentuh:${NC}"
echo -e "  ${BYELLOW}–${NC} Akun SSH & VMess yang sudah dibuat"
echo -e "  ${BYELLOW}–${NC} Daftar server"
echo -e "  ${BYELLOW}–${NC} Sertifikat SSL"
echo -e "  ${BYELLOW}–${NC} Domain & konfigurasi Telegram"
echo ""
echo -e "  ${BYELLOW}Ketik 'menu' untuk membuka ZV-Manager${NC}"
echo ""
