#!/bin/bash
# ============================================================
#   ZV-Manager - Updater
# ============================================================

[[ "$EUID" -ne 0 ]] && { echo "[ERROR] Jalankan sebagai root!"; exit 1; }

_TOTAL=14
_CUR=0
_LOG="/tmp/zv-update-detail.log"
> "$_LOG"

# ── Warna & gradient ─────────────────────────────────────────
G="\e[1;32m" R="\e[1;31m" O="\e[1;33m" C="\e[1;36m"
W="\e[1;97m" D="\e[0;37m" NC="\e[0m"

_grad() {
    local text="$1" r1=$2 g1=$3 b1=$4 r2=$5 g2=$6 b2=$7 nc="\e[0m"
    local len=0
    for (( c=0; c<${#text}; c++ )); do [[ "${text:$c:1}" != " " ]] && len=$((len+1)); done
    [[ $len -le 1 ]] && len=2
    local i=0 out=""
    for (( c=0; c<${#text}; c++ )); do
        local ch="${text:$c:1}"
        if [[ "$ch" == " " ]]; then out+=" "
        else
            local r=$(( r1+(r2-r1)*i/(len-1) )) g=$(( g1+(g2-g1)*i/(len-1) )) b=$(( b1+(b2-b1)*i/(len-1) ))
            out+="\e[1;38;2;${r};${g};${b}m${ch}${nc}"; i=$((i+1))
        fi
    done
    echo -e "$out"
}

_sep() { _grad "$(printf '=%.0s' {1..50})" 0 180 255 120 0 255; }

_progress() {
    _CUR=$(( _CUR + 1 ))
    local pct=$(( _CUR * 100 / _TOTAL ))
    local filled=$(( pct / 5 )) empty=$(( 20 - pct/5 ))
    local bar=""
    for (( i=0; i<filled; i++ )); do bar+="█"; done
    for (( i=0; i<empty; i++ )); do bar+="░"; done
    printf "\r  ${C}[${bar}]${NC} ${W}%3d%%${NC} ${D}%s${NC}..." "$pct" "$1"
}

_done() {
    local pct=$(( _CUR * 100 / _TOTAL ))
    local filled=$(( pct / 5 )) empty=$(( 20 - pct/5 ))
    local bar=""
    for (( i=0; i<filled; i++ )); do bar+="█"; done
    for (( i=0; i<empty; i++ )); do bar+="░"; done
    printf "\r\033[K"
    printf "  ${C}[${bar}]${NC} ${W}%3d%%${NC}  ${G}✔${NC}  ${W}%-28s${NC}  ${D}%s${NC}\n" "$pct" "$1" "$2"
}

_skip() {
    _CUR=$(( _CUR + 1 ))
    local pct=$(( _CUR * 100 / _TOTAL ))
    printf "  ${D}–${NC}  ${W}%-35s${NC}  ${D}%s${NC}\n" "$1" "$2"
}

_fail() {
    printf "\r\033[K"
    printf "  ${R}✘${NC}  ${W}%-35s${NC}  ${R}gagal (lihat $_LOG)${NC}\n" "$1"
}

_run() {
    local label="$1" ok="$2"; shift 2
    _progress "$label"
    if "$@" >> "$_LOG" 2>&1; then _done "$label" "$ok"
    else _fail "$label"; fi
}

_pkg_installed() { dpkg -l "$1" 2>/dev/null | grep -q "^ii"; }
_xray_latest()   { curl -s --max-time 10 "https://api.github.com/repos/XTLS/Xray-core/releases/latest" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tag_name','').lstrip('v'))" 2>/dev/null; }
_xray_current()  { /usr/local/bin/xray version 2>/dev/null | grep -m1 "^Xray" | grep -oP '\d+\.\d+\.\d+' | head -1 || echo ""; }

# ── Banner ────────────────────────────────────────────────────
clear
_sep
_grad " ZV-MANAGER UPDATER" 255 0 127 0 210 255
_sep
echo ""

# ── Git fetch ─────────────────────────────────────────────────
_progress "Mengambil update dari GitHub"
if ! command -v git &>/dev/null; then apt-get install -y git >> "$_LOG" 2>&1; fi

if [[ ! -d /root/ZV-Manager/.git ]]; then
    rm -rf /root/ZV-Manager
    git clone -q https://github.com/ZenXNF/ZV-Manager.git /root/ZV-Manager >> "$_LOG" 2>&1
else
    cd /root/ZV-Manager
    git fetch -q origin >> "$_LOG" 2>&1
    git reset -q --hard origin/main >> "$_LOG" 2>&1
fi
[[ ! -d /root/ZV-Manager ]] && { _fail "Git fetch"; exit 1; }
_done "Git fetch" "berhasil"

cd /root/ZV-Manager
find . -name "*.sh" -exec chmod +x {} \;
find . -name "*.py" -exec chmod +x {} \;
chmod +x checker/zv-checker 2>/dev/null

# ── Cek izin ─────────────────────────────────────────────────
source /etc/zv-manager/core/license.sh
check_license

# ── Salin script ─────────────────────────────────────────────
_progress "Menyalin script"
{
cp -r core /etc/zv-manager/
cp -r services /etc/zv-manager/
cp -r menu /etc/zv-manager/
cp -r utils /etc/zv-manager/
cp -r cron /etc/zv-manager/
cp -r checker /etc/zv-manager/
chmod +x /etc/zv-manager/checker/zv-checker
chmod +x /etc/zv-manager/services/telegram/bot.py 2>/dev/null || true
cp config.conf /etc/zv-manager/
cp install.sh update.sh uninstall.sh /etc/zv-manager/
cp zv-agent.sh zv-vmess-agent.sh /etc/zv-manager/
} >> "$_LOG" 2>&1
NEW_HASH=$(git -C /root/ZV-Manager rev-parse --short HEAD 2>/dev/null || echo "unknown")
sed -i "s/^COMMIT_HASH=.*/COMMIT_HASH=\"${NEW_HASH}\"/" /etc/zv-manager/config.conf
_done "Script" "#${NEW_HASH}"

# ── zv-agent ─────────────────────────────────────────────────
_run "zv-agent" "diperbarui" bash -c "
    cp /etc/zv-manager/zv-agent.sh /usr/local/bin/zv-agent
    chmod +x /usr/local/bin/zv-agent
    cp /etc/zv-manager/zv-vmess-agent.sh /usr/local/bin/zv-vmess-agent
    chmod +x /usr/local/bin/zv-vmess-agent
"

# ── Telegram bot ─────────────────────────────────────────────
_progress "Telegram bot"
{
BOT_DIR="/opt/zv-telegram"
mkdir -p "$BOT_DIR"
rm -f /usr/local/bin/zv-telegram-bot /usr/local/bin/zv-telegram-bot.py
cp -r /etc/zv-manager/services/telegram/. "$BOT_DIR/"
find "$BOT_DIR" -name "*.py" -exec chmod +x {} \;
pip3 install -q "aiogram==3.*" --break-system-packages 2>/dev/null || pip3 install -q "aiogram==3.*" 2>/dev/null
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
else
    systemctl enable zv-telegram &>/dev/null
    systemctl start zv-telegram &>/dev/null
fi
} >> "$_LOG" 2>&1
_done "Telegram bot" "diperbarui & dijalankan"

# ── Xray-core ────────────────────────────────────────────────
if [[ ! -f "/usr/local/bin/xray" ]]; then
    _run "Xray-core" "berhasil diinstall" bash -c "source /etc/zv-manager/services/xray/install.sh && install_xray"
else
    current_xray=$(_xray_current)
    latest_xray=$(_xray_latest)
    if [[ -n "$latest_xray" && -n "$current_xray" && "$current_xray" != "$latest_xray" ]]; then
        _progress "Xray-core $current_xray → $latest_xray"
        tmpdir=$(mktemp -d)
        dl_url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
        if wget -q -O "${tmpdir}/xray.zip" "$dl_url" >> "$_LOG" 2>&1 && \
           unzip -q "${tmpdir}/xray.zip" -d "${tmpdir}/xray" >> "$_LOG" 2>&1; then
            systemctl stop zv-xray 2>/dev/null
            install -m 755 "${tmpdir}/xray/xray" /usr/local/bin/xray
            systemctl start zv-xray 2>/dev/null
            _done "Xray-core" "diupdate ke v${latest_xray}"
        else
            _fail "Xray-core update"
        fi
        rm -rf "$tmpdir"
    else
        _skip "Xray-core" "sudah terbaru (v${current_xray})"
    fi
fi

# ── BadVPN ───────────────────────────────────────────────────
if [[ ! -f "/usr/local/bin/badvpn-udpgw" ]]; then
    _run "BadVPN UDPGW" "berhasil diinstall" bash -c "source /etc/zv-manager/services/badvpn/install.sh && install_badvpn"
else
    _skip "BadVPN UDPGW" "sudah ada"
fi

# ── Nginx ────────────────────────────────────────────────────
_run "Nginx" "config diperbarui" bash -c "source /etc/zv-manager/services/nginx/install.sh && install_nginx"

# ── Dropbear ─────────────────────────────────────────────────
_run "Dropbear" "config diperbarui" bash -c "source /etc/zv-manager/services/dropbear/install.sh && install_dropbear"

# ── WebSocket ────────────────────────────────────────────────
_run "WebSocket Proxy" "config diperbarui" bash -c "source /etc/zv-manager/services/websocket/install.sh && install_websocket"

# ── SSH ──────────────────────────────────────────────────────
_run "OpenSSH" "config diperbarui" bash -c "source /etc/zv-manager/services/ssh/install.sh && install_ssh"

# ── UDP Custom ───────────────────────────────────────────────
_run "UDP Custom" "config diperbarui" bash -c "source /etc/zv-manager/services/udp/install.sh && install_udp_custom"

# ── aiogram ──────────────────────────────────────────────────
current_aiogram=$(pip3 show aiogram 2>/dev/null | grep "^Version:" | awk '{print $2}')
if [[ -z "$current_aiogram" ]]; then
    _run "aiogram (Python)" "berhasil diinstall" pip3 install -q "aiogram==3.*" --break-system-packages
else
    _skip "aiogram (Python)" "sudah ada (v${current_aiogram})"
fi

# ── Cron jobs ────────────────────────────────────────────────
_progress "Cron jobs"
{
cat > /etc/cron.d/zv-autokill <<'CRONEOF'
*/1 * * * * root /bin/bash /etc/zv-manager/cron/autokill.sh
CRONEOF
cat > /etc/cron.d/zv-trial <<'CRONEOF'
*/1 * * * * root /bin/bash /etc/zv-manager/cron/trial-cleanup.sh
CRONEOF
cat > /etc/cron.d/zv-tg-notify <<'CRONEOF'
0 * * * * root /bin/bash /etc/zv-manager/cron/tg-notify.sh
CRONEOF
cat > /etc/cron.d/zv-expired <<'CRONEOF'
2 0 * * * root /bin/bash /etc/zv-manager/cron/expired.sh
CRONEOF
cat > /etc/cron.d/zv-license <<'CRONEOF'
5 0 * * * root /bin/bash /etc/zv-manager/cron/license-check.sh
0 7 * * * root /bin/bash /etc/zv-manager/cron/daily-report.sh
CRONEOF
cat > /etc/cron.d/zv-bw-check <<'CRONEOF'
*/5 * * * * root /bin/bash /etc/zv-manager/cron/bw-check.sh
*/5 * * * * root /bin/bash /etc/zv-manager/cron/bw-vmess.sh
* * * * * root /bin/bash /etc/zv-manager/cron/ip-limit.sh
CRONEOF
cat > /etc/cron.d/zv-watchdog <<'CRONEOF'
*/5 * * * * root /bin/bash /etc/zv-manager/cron/watchdog.sh
CRONEOF
cat > /etc/cron.d/zv-status-page <<'CRONEOF'
*/5 * * * * root /bin/bash /etc/zv-manager/cron/status-page.sh
CRONEOF
cat > /etc/cron.d/zv-backup <<'CRONEOF'
0 2 * * * root /bin/bash /etc/zv-manager/cron/backup.sh
CRONEOF
cat > /etc/cron.d/zv-check-update <<'CRONEOF'
0 6 * * * root /bin/bash /etc/zv-manager/cron/check-update.sh
CRONEOF
mkdir -p /var/lib/zv-manager/status
service cron restart &>/dev/null
} >> "$_LOG" 2>&1
_done "Cron jobs" "semua diperbarui"

ln -sf /etc/zv-manager/menu/menu.sh /usr/local/bin/menu
chmod +x /usr/local/bin/menu

# ── Selesai ───────────────────────────────────────────────────
echo ""
_sep
_grad " UPDATE SELESAI!" 0 210 255 160 80 255
_sep
echo ""
printf "  ${D}≥${NC}  ${W}Versi  :${NC}  ${G}#%s${NC}\n" "$NEW_HASH"
echo ""
printf "  ${D}≥${NC}  ${W}Yang diperbarui:${NC}\n"
printf "  ${G}  ✔${NC}  Script (menu, services, utils, core)\n"
printf "  ${G}  ✔${NC}  Xray-core, BadVPN, Nginx, SSH, Dropbear\n"
printf "  ${G}  ✔${NC}  WebSocket, UDP Custom, aiogram, Cron\n"
printf "  ${G}  ✔${NC}  Binary zv-agent, zv-vmess-agent\n"
echo ""
printf "  ${D}≥${NC}  ${W}Tidak berubah:${NC}\n"
printf "  ${O}  –${NC}  Akun SSH & VMess, daftar server, SSL\n"
printf "  ${O}  –${NC}  Domain & konfigurasi Telegram\n"
echo ""
echo -e "  ${O}Ketik 'menu' untuk membuka ZV-Manager${NC}"
echo ""
