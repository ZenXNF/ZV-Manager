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
cp uninstall.sh /etc/zv-manager/
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

echo ""
echo -e "${BYELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BWHITE}  🔧 Cek & Update Komponen${NC}"
echo -e "${BYELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

_UPDATE_LOG="/tmp/zv-update-detail.log"
> "$_UPDATE_LOG"

_pkg_installed() { dpkg -l "$1" 2>/dev/null | grep -q "^ii"; }

_xray_latest_version() {
    local raw
    raw=$(curl -s --max-time 10 "https://api.github.com/repos/XTLS/Xray-core/releases/latest" 2>/dev/null)
    echo "$raw" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tag_name','').lstrip('v'))" 2>/dev/null || \
    echo "$raw" | grep -m1 '"tag_name"' | grep -oP '(?<="v)[^"]+' | head -1
}

_xray_current_version() {
    /usr/local/bin/xray version 2>/dev/null | grep -m1 "^Xray" | grep -oP '\d+\.\d+\.\d+' | head -1 || echo ""
}

# Tampilkan spinner di baris saat ini (tanpa newline), setelah selesai overwrite jadi 1 baris hasil
_run_task() {
    local name="$1" ok_msg="$2"; shift 2
    printf "  \033[33m>\033[0m  %-38s\r" "$name"
    if "$@" >> "$_UPDATE_LOG" 2>&1; then
        printf "\033[2K"
        printf "  \033[32m+\033[0m  \033[1m%-35s\033[0m  %s\n" "$name" "$ok_msg"
    else
        printf "\033[2K"
        printf "  \033[31m!\033[0m  \033[1m%-35s\033[0m  \033[31mgagal (lihat /tmp/zv-update-detail.log)\033[0m\n" "$name"
    fi
}

_skip_task() {
    local name="$1" msg="$2"
    printf "  \033[33m-\033[0m  \033[1m%-35s\033[0m  \033[33m%s\033[0m\n" "$name" "$msg"
}

# ── 1. Xray-core ─────────────────────────────────────────────
if [[ ! -f "/usr/local/bin/xray" ]]; then
    _run_task "Xray-core" "berhasil diinstall" \
        bash -c "source /etc/zv-manager/services/xray/install.sh && install_xray"
else
    current_xray=$(_xray_current_version)
    latest_xray=$(_xray_latest_version)
    latest_xray_clean="${latest_xray#v}"
    if [[ -n "$latest_xray_clean" && -n "$current_xray" && "$current_xray" != "$latest_xray_clean" ]]; then
        ARCH=$(uname -m)
        case "$ARCH" in
            x86_64)  ARCH_TAG="64" ;;
            aarch64) ARCH_TAG="arm64-v8a" ;;
            *)       ARCH_TAG="64" ;;
        esac
        tmpdir=$(mktemp -d)
        dl_url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${ARCH_TAG}.zip"
        _run_task "Xray-core  v${current_xray} -> v${latest_xray}" "diupdate ke v${latest_xray}" \
            bash -c "wget -q -O '${tmpdir}/xray.zip' '$dl_url' 2>/dev/null \
                && apt-get install -y unzip > /dev/null 2>&1 \
                && unzip -q '${tmpdir}/xray.zip' -d '${tmpdir}/xray' \
                && systemctl stop zv-xray 2>/dev/null \
                ; install -m 755 '${tmpdir}/xray/xray' /usr/local/bin/xray \
                && systemctl start zv-xray 2>/dev/null"
        rm -rf "$tmpdir"
    else
        _skip_task "Xray-core" "sudah terbaru (v${current_xray})"
    fi
    if ! grep -q "HandlerService" /usr/local/etc/xray/config.json 2>/dev/null; then
        _run_task "Xray config" "HandlerService ditambahkan" \
            bash -c "source /etc/zv-manager/services/xray/install.sh && _write_xray_config"
    fi
fi

# ── 2. BadVPN UDPGW ──────────────────────────────────────────
if [[ ! -f "/usr/local/bin/badvpn-udpgw" ]]; then
    _run_task "BadVPN UDPGW" "berhasil diinstall" \
        bash -c "source /etc/zv-manager/services/badvpn/install.sh && install_badvpn"
else
    _skip_task "BadVPN UDPGW" "sudah ada"
fi

# ── 3. Nginx ─────────────────────────────────────────────────
if ! _pkg_installed nginx; then
    _run_task "Nginx" "berhasil diinstall" \
        bash -c "source /etc/zv-manager/services/nginx/install.sh && install_nginx"
else
    _run_task "Nginx" "config diperbarui" \
        bash -c "source /etc/zv-manager/services/nginx/install.sh && install_nginx"
fi

# ── 4. Dropbear ──────────────────────────────────────────────
if ! _pkg_installed dropbear; then
    _run_task "Dropbear" "berhasil diinstall" \
        bash -c "source /etc/zv-manager/services/dropbear/install.sh && install_dropbear"
else
    _run_task "Dropbear" "config diperbarui" \
        bash -c "source /etc/zv-manager/services/dropbear/install.sh && install_dropbear"
fi

# ── 5. WebSocket ─────────────────────────────────────────────
_run_task "WebSocket Proxy" "config diperbarui" \
    bash -c "source /etc/zv-manager/services/websocket/install.sh && install_websocket"

# ── 6. SSH ───────────────────────────────────────────────────
_run_task "OpenSSH" "config diperbarui" \
    bash -c "source /etc/zv-manager/services/ssh/install.sh && install_ssh"

# ── 7. UDP Custom ────────────────────────────────────────────
_run_task "UDP Custom" "config diperbarui" \
    bash -c "source /etc/zv-manager/services/udp/install.sh && install_udp_custom"

# ── 8. aiogram ───────────────────────────────────────────────
current_aiogram=$(pip3 show aiogram 2>/dev/null | grep "^Version:" | awk '{print $2}')
if [[ -z "$current_aiogram" ]]; then
    _run_task "aiogram (Python)" "berhasil diinstall" \
        pip3 install -q "aiogram==3.*" --break-system-packages
else
    _skip_task "aiogram (Python)" "sudah ada (v${current_aiogram})"
fi

# ── 9. Cron jobs ─────────────────────────────────────────────
{
cat > /etc/cron.d/zv-autokill <<'CRONEOF'
# ZV-Manager - Auto Kill Multi-Login
*/1 * * * * root /bin/bash /etc/zv-manager/cron/autokill.sh
CRONEOF

cat > /etc/cron.d/zv-trial <<'CRONEOF'
# ZV-Manager - Trial Account Cleanup
*/1 * * * * root /bin/bash /etc/zv-manager/cron/trial-cleanup.sh
CRONEOF

cat > /etc/cron.d/zv-tg-notify <<'CRONEOF'
# ZV-Manager - Notifikasi Telegram (tiap jam)
0 * * * * root /bin/bash /etc/zv-manager/cron/tg-notify.sh
CRONEOF

cat > /etc/cron.d/zv-expired <<'CRONEOF'
# ZV-Manager - Auto Delete Expired Users
2 0 * * * root /bin/bash /etc/zv-manager/cron/expired.sh
CRONEOF

cat > /etc/cron.d/zv-license <<'CRONEOF'
# ZV-Manager - Cek Izin Harian + Laporan Harian
5 0 * * * root /bin/bash /etc/zv-manager/cron/license-check.sh
0 7 * * * root /bin/bash /etc/zv-manager/cron/daily-report.sh
CRONEOF

cat > /etc/cron.d/zv-bw-check <<'CRONEOF'
# ZV-Manager - Bandwidth SSH + VMess + IP Limit + Online Counter
*/5 * * * * root /bin/bash /etc/zv-manager/cron/bw-check.sh
*/5 * * * * root /bin/bash /etc/zv-manager/cron/bw-vmess.sh
* * * * * root /bin/bash /etc/zv-manager/cron/ip-limit.sh
* * * * * root /bin/bash /etc/zv-manager/cron/vmess-online.sh
CRONEOF

cat > /etc/cron.d/zv-watchdog <<'CRONEOF'
# ZV-Manager - Watchdog: auto-restart service
*/5 * * * * root /bin/bash /etc/zv-manager/cron/watchdog.sh
CRONEOF

cat > /etc/cron.d/zv-status-page <<'CRONEOF'
# ZV-Manager - Generate Status Page
*/5 * * * * root /bin/bash /etc/zv-manager/cron/status-page.sh
CRONEOF

cat > /etc/cron.d/zv-backup <<'CRONEOF'
# ZV-Manager - Daily Backup jam 02:00
0 2 * * * root /bin/bash /etc/zv-manager/cron/backup.sh
CRONEOF

cat > /etc/cron.d/zv-check-update <<'CRONEOF'
# ZV-Manager - Cek update GitHub jam 06:00
0 6 * * * root /bin/bash /etc/zv-manager/cron/check-update.sh
CRONEOF

mkdir -p /var/lib/zv-manager/status
service cron restart &>/dev/null
} >> "$_UPDATE_LOG" 2>&1
printf "  \033[32m+\033[0m  \033[1m%-35s\033[0m  %s\n" "Cron jobs" "semua cron diperbarui"

echo ""
/bin/bash /etc/zv-manager/cron/check-update.sh &>/dev/null &

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
