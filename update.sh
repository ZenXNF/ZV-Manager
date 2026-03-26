#!/bin/bash
# ============================================================
#   ZV-Manager - Updater
# ============================================================

[[ "$EUID" -ne 0 ]] && { echo "[ERROR] Jalankan sebagai root!"; exit 1; }

_LOG="/tmp/zv-update-detail.log"
> "$_LOG"

# ── Warna ────────────────────────────────────────────────────
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

_bar() {
    local pct=$1 width=25
    local filled=$(( pct * width / 100 )) bar="" r g b
    local empty=$(( width - filled ))
    if (( pct < 50 )); then r=255; g=$(( pct * 5 )); b=0
    else r=$(( 255-(pct-50)*5 )); g=255; b=0; fi
    for (( i=0; i<filled; i++ )); do bar+="█"; done
    for (( i=0; i<empty;  i++ )); do bar+="░"; done
    printf "\e[1;38;2;%d;%d;%dm%s\e[0m" "$r" "$g" "$b" "$bar"
}

_run() {
    local label="$1" ok="$2" func="$3"

    "$func" >> "$_LOG" 2>&1 &
    local pid=$! pct=0 step=4

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  $(_bar $pct) ${W}%3d%%${NC} ${D}%s...${NC}" "$pct" "$label"
        (( pct < 30 )) && step=$(( RANDOM%5+3 ))
        (( pct >= 30 && pct < 70 )) && step=$(( RANDOM%3+2 ))
        (( pct >= 70 )) && step=1
        pct=$(( pct+step > 94 ? 94 : pct+step ))
        sleep 0.08
    done
    wait "$pid"; local rc=$?

    if [[ $rc -eq 0 ]]; then
        printf "\r  $(_bar 100) ${W}100%%${NC}  ${G}✔${NC}  ${W}%-30s${NC} ${D}%s${NC}\n" "$label" "$ok"
    else
        printf "\r  $(_bar 100) ${W}100%%${NC}  ${R}✘${NC}  ${W}%-30s${NC} ${R}gagal — cek $_LOG${NC}\n" "$label"
    fi
}

_skip() { printf "  ${D}–${NC}  ${W}%-35s${NC}  ${D}%s${NC}\n" "$1" "$2"; }
_pkg_installed() { dpkg -l "$1" 2>/dev/null | grep -q "^ii"; }
_xray_latest()  { curl -s --max-time 10 "https://api.github.com/repos/XTLS/Xray-core/releases/latest" 2>/dev/null | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('tag_name','').lstrip('v'))" 2>/dev/null; }
_xray_current() { /usr/local/bin/xray version 2>/dev/null | grep -m1 "^Xray" | grep -oP '\d+\.\d+\.\d+' | head -1 || echo ""; }

# ── Task functions ────────────────────────────────────────────
_task_git() {
    command -v git &>/dev/null || apt-get install -y git
    if [[ ! -d /root/ZV-Manager/.git ]]; then
        rm -rf /root/ZV-Manager
        git clone -q https://github.com/ZenXNF/ZV-Manager.git /root/ZV-Manager
    else
        cd /root/ZV-Manager
        git fetch -q origin
        git reset -q --hard origin/main
    fi
}

_task_copy() {
    cd /root/ZV-Manager || return 1
    cp -r core services menu utils cron checker /etc/zv-manager/
    chmod +x /etc/zv-manager/checker/zv-checker
    chmod +x /etc/zv-manager/services/telegram/bot.py 2>/dev/null || true
    cp config.conf install.sh update.sh uninstall.sh zv-agent.sh zv-vmess-agent.sh zv-vless-agent.sh /etc/zv-manager/
}

_task_agent() {
    cp /etc/zv-manager/zv-agent.sh /usr/local/bin/zv-agent
    chmod +x /usr/local/bin/zv-agent
    cp /etc/zv-manager/zv-vmess-agent.sh /usr/local/bin/zv-vmess-agent
    chmod +x /usr/local/bin/zv-vmess-agent
    cp /etc/zv-manager/zv-vless-agent.sh /usr/local/bin/zv-vless-agent
    chmod +x /usr/local/bin/zv-vless-agent
    mkdir -p /etc/zv-manager/accounts/vless
}

_task_bot() {
    local BOT_DIR="/opt/zv-telegram"
    mkdir -p "$BOT_DIR"
    cp -r /etc/zv-manager/services/telegram/. "$BOT_DIR/"
    find "$BOT_DIR" -name "*.py" -exec chmod +x {} \;
    pip3 install -q "aiogram==3.*" --break-system-packages 2>/dev/null || \
    pip3 install -q "aiogram==3.*" 2>/dev/null
    python3 - << 'PYEOF'
svc = "[Unit]\nDescription=ZV-Manager Telegram Bot (Python)\nAfter=network.target\nStartLimitIntervalSec=60\nStartLimitBurst=5\n\n[Service]\nType=simple\nWorkingDirectory=/opt/zv-telegram\nExecStart=/usr/bin/python3 -u /opt/zv-telegram/bot.py\nRestart=always\nRestartSec=10s\nMemoryMax=120M\nMemorySwapMax=0\nCPUQuota=60%\nStandardOutput=append:/var/log/zv-manager/telegram-bot.log\nStandardError=append:/var/log/zv-manager/telegram-bot.log\n\n[Install]\nWantedBy=multi-user.target\n"
open("/etc/systemd/system/zv-telegram.service","w").write(svc)
PYEOF
    systemctl daemon-reload
    if systemctl is-active --quiet zv-telegram 2>/dev/null; then
        systemctl restart zv-telegram &>/dev/null
    else
        systemctl enable zv-telegram &>/dev/null
        systemctl start zv-telegram &>/dev/null
    fi
}

_task_xray_install() {
    source /etc/zv-manager/services/xray/install.sh && install_xray
}

_task_xray_update() {
    local tmpdir; tmpdir=$(mktemp -d)
    local url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
    wget -q -O "$tmpdir/xray.zip" "$url" && \
    unzip -q "$tmpdir/xray.zip" -d "$tmpdir/xray" && \
    systemctl stop zv-xray 2>/dev/null && \
    install -m 755 "$tmpdir/xray/xray" /usr/local/bin/xray && \
    systemctl start zv-xray 2>/dev/null
    rm -rf "$tmpdir"
}

_task_badvpn() {
    source /etc/zv-manager/services/badvpn/install.sh && install_badvpn
}

_task_nginx() {
    source /etc/zv-manager/services/nginx/install.sh && install_nginx
}

_task_dropbear() {
    source /etc/zv-manager/services/dropbear/install.sh && install_dropbear
}

_task_ws() {
    source /etc/zv-manager/services/websocket/install.sh && install_websocket
}

_task_ssh() {
    source /etc/zv-manager/services/ssh/install.sh && install_ssh
}

_task_udp() {
    source /etc/zv-manager/services/udp/install.sh && install_udp_custom
}

_task_cron() {
    printf '%s\n' "* * * * * root for i in 1 2 3 4 5 6; do /bin/bash /etc/zv-manager/cron/autokill.sh; sleep 10; done" \
        > /etc/cron.d/zv-autokill
    printf '%s\n' "*/5 * * * * root /bin/bash /etc/zv-manager/cron/trial-cleanup.sh" \
        > /etc/cron.d/zv-trial
    printf '%s\n' "0 * * * * root /bin/bash /etc/zv-manager/cron/tg-notify.sh" \
        > /etc/cron.d/zv-tg-notify
    printf '%s\n' "* * * * * root for i in 1 2 3 4 5; do /bin/bash /etc/zv-manager/cron/expired.sh; sleep 12; done" \
        > /etc/cron.d/zv-expired
    printf '%s\n' \
        "5 0 * * * root /bin/bash /etc/zv-manager/cron/license-check.sh" \
        "0 7 * * * root /bin/bash /etc/zv-manager/cron/daily-report.sh" \
        > /etc/cron.d/zv-license
    printf '%s\n' \
        "* * * * * root for i in 1 2 3 4 5 6; do /bin/bash /etc/zv-manager/cron/bw-check.sh; sleep 10; done" \
        "*/5 * * * * root /bin/bash /etc/zv-manager/cron/bw-vmess.sh" \
        "*/5 * * * * root /bin/bash /etc/zv-manager/cron/bw-vless.sh" \
        "* * * * * root /bin/bash /etc/zv-manager/cron/ip-limit.sh" \
        > /etc/cron.d/zv-bw-check
    printf '%s\n' "*/5 * * * * root /bin/bash /etc/zv-manager/cron/watchdog.sh" \
        > /etc/cron.d/zv-watchdog
    printf '%s\n' "*/5 * * * * root /bin/bash /etc/zv-manager/cron/worker-check.sh" \
        > /etc/cron.d/zv-worker-check
    printf '%s\n' "0 2 * * * root /bin/bash /etc/zv-manager/cron/backup.sh" \
        > /etc/cron.d/zv-backup
    printf '%s\n' "0 6 * * * root /bin/bash /etc/zv-manager/cron/check-update.sh" \
        > /etc/cron.d/zv-check-update
    # Status page cron (hanya jika web sudah diinstall)
    if [[ -f /etc/zv-manager/.web-installed ]]; then
        printf '%s\n' "*/5 * * * * root /bin/bash /etc/zv-manager/cron/status-page.sh" \
            > /etc/cron.d/zv-status-page
    fi
    mkdir -p /var/lib/zv-manager/status
    service cron restart &>/dev/null
    systemctl enable --now atd &>/dev/null || service atd start &>/dev/null || true
}

# ── Banner ────────────────────────────────────────────────────
clear
_sep
_grad " ZV-MANAGER UPDATER" 255 0 127 0 210 255
_sep
echo ""

# ── 1. Git fetch ──────────────────────────────────────────────
_run "Git fetch" "berhasil" _task_git
[[ ! -d /root/ZV-Manager ]] && { echo "Gagal download repo!"; exit 1; }

cd /root/ZV-Manager
find . -name "*.sh" -exec chmod +x {} \;
find . -name "*.py" -exec chmod +x {} \;
chmod +x checker/zv-checker 2>/dev/null

source /etc/zv-manager/core/license.sh
check_license

# ── 2. Salin script ───────────────────────────────────────────
_run "Menyalin script" "selesai" _task_copy
NEW_HASH=$(git -C /root/ZV-Manager rev-parse --short HEAD 2>/dev/null || echo "unknown")
sed -i "s/^COMMIT_HASH=.*/COMMIT_HASH=\"${NEW_HASH}\"/" /etc/zv-manager/config.conf

# ── 3. zv-agent ───────────────────────────────────────────────
_run "zv-agent" "diperbarui" _task_agent

# ── 4. Telegram bot ───────────────────────────────────────────
_run "Telegram bot" "diperbarui & dijalankan" _task_bot

# ── 5. Xray-core ─────────────────────────────────────────────
if [[ ! -f "/usr/local/bin/xray" ]]; then
    _run "Xray-core" "berhasil diinstall" _task_xray_install
else
    current_xray=$(_xray_current)
    latest_xray=$(_xray_latest)
    if [[ -n "$latest_xray" && -n "$current_xray" && "$current_xray" != "$latest_xray" ]]; then
        _run "Xray-core $current_xray -> $latest_xray" "v${latest_xray}" _task_xray_update
    else
        _skip "Xray-core" "sudah terbaru v${current_xray}"
    fi
fi

# ── 6. BadVPN ─────────────────────────────────────────────────
if [[ ! -f "/usr/local/bin/badvpn-udpgw" ]]; then
    _run "BadVPN UDPGW" "berhasil diinstall" _task_badvpn
else
    _skip "BadVPN UDPGW" "sudah ada"
fi

# ── 7. Nginx ──────────────────────────────────────────────────
_run "Nginx" "config diperbarui" _task_nginx

# ── 8. Dropbear ───────────────────────────────────────────────
_run "Dropbear" "config diperbarui" _task_dropbear

# ── 9. WebSocket ──────────────────────────────────────────────
_run "WebSocket Proxy" "config diperbarui" _task_ws

# ── 10. SSH ───────────────────────────────────────────────────
_run "OpenSSH" "config diperbarui" _task_ssh

# ── 11. UDP Custom ────────────────────────────────────────────
_run "UDP Custom" "config diperbarui" _task_udp

# ── 12. aiogram ───────────────────────────────────────────────
_task_aiogram() {
    pip3 install -q "aiogram==3.*" --break-system-packages 2>/dev/null || \
    pip3 install -q "aiogram==3.*" 2>/dev/null
}
current_aiogram=$(pip3 show aiogram 2>/dev/null | grep "^Version:" | awk '{print $2}')
if [[ -z "$current_aiogram" ]]; then
    _run "aiogram Python" "berhasil diinstall" _task_aiogram
else
    _skip "aiogram" "sudah ada v${current_aiogram}"
fi

# ── 13. Cron jobs ─────────────────────────────────────────────
_run "Cron jobs" "semua diperbarui" _task_cron

ln -sf /etc/zv-manager/menu/menu.sh /usr/local/bin/menu
chmod +x /usr/local/bin/menu

# ── Regenerasi web status page jika aktif ─────────────────────
if [[ -f /etc/zv-manager/.web-installed ]]; then
    rm -f /var/www/zv-manager/index.html
    bash /etc/zv-manager/cron/status-page.sh &>/dev/null
fi

# ── Selesai ───────────────────────────────────────────────────
echo ""
_sep
_grad " UPDATE SELESAI!" 0 210 255 160 80 255
_sep
echo ""
printf "  ${D}≥${NC}  ${W}Versi  :${NC}  ${G}#%s${NC}\n" "$NEW_HASH"
echo ""
printf "  ${D}≥${NC}  ${W}Yang diperbarui:${NC}\n"
printf "  ${G}  ✔${NC}  Script, Nginx, SSH, Dropbear, WebSocket\n"
printf "  ${G}  ✔${NC}  Xray-core, BadVPN, UDP Custom, aiogram, Cron\n"
printf "  ${G}  ✔${NC}  Binary zv-agent, zv-vmess-agent, zv-vless-agent, Telegram bot\n"
echo ""
printf "  ${O}  –${NC}  Akun SSH, VMess & VLESS, daftar server, SSL tidak berubah\n"
echo ""


echo ""
echo -e "  ${O}Ketik 'y' lalu Enter untuk reboot (atau Ctrl+C untuk batal):${NC}"
while true; do
    read -rs _ans < /dev/tty
    [[ "$_ans" == "y" || "$_ans" == "Y" ]] && break
    echo -e "  ${D}Ketik 'y' untuk konfirmasi reboot.${NC}"
done
echo "  Rebooting..."
sleep 2
reboot
