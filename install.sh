#!/bin/bash
# ============================================================
#   ZV-Manager Installer
#   SSH, VMess & VLESS Tunneling Panel for Ubuntu 24.04 LTS
# ============================================================

INSTALL_DIR="/etc/zv-manager"
REPO_DIR="/root/ZV-Manager"
GITHUB_URL="https://github.com/ZenXNF/ZV-Manager.git"
_INSTALL_LOG="/tmp/zv-install-detail.log"

mkdir -p /var/log/zv-manager
touch /var/log/zv-manager/install.log
> "$_INSTALL_LOG"

[[ "$EUID" -ne 0 ]] && { echo "  [!] Jalankan sebagai root!"; exit 1; }
[[ "$(uname -m)" != "x86_64" ]] && { echo "  [!] Arsitektur tidak didukung: $(uname -m)"; exit 1; }

# ── Warna & gradient ─────────────────────────────────────────
R="\e[1;31m" O="\e[1;33m" G="\e[1;32m" C="\e[1;36m"
B="\e[1;34m" P="\e[1;35m" W="\e[1;97m" D="\e[0;37m" NC="\e[0m"

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

# ── Progress bar realtime per step ───────────────────────────
_bar() {
    local pct=$1 width=25 filled bar="" r g b
    filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))
    if (( pct < 50 )); then r=255; g=$(( pct*5 )); b=0
    else r=$(( 255-(pct-50)*5 )); g=255; b=0; fi
    for (( i=0; i<filled; i++ )); do bar+="█"; done
    for (( i=0; i<empty;  i++ )); do bar+="░"; done
    printf "\e[1;38;2;%d;%d;%dm%s\e[0m" "$r" "$g" "$b" "$bar"
}

_run() {
    local label="$1" ok="$2" func="$3"
    "$func" >> "$_INSTALL_LOG" 2>&1 &
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
        printf "\r  $(_bar 100) ${W}100%%${NC}  ${R}✘${NC}  ${W}%-30s${NC} ${R}gagal${NC}\n" "$label"
    fi
}

_run_inline() {
    local label="$1" ok="$2" func="$3"
    printf "  ${D}»${NC}  %-38s\r" "$label"
    if "$func" >> "$_INSTALL_LOG" 2>&1; then
        printf "\033[2K"
        printf "  ${G}✔${NC}  ${W}%-35s${NC}  ${D}%s${NC}\n" "$label" "$ok"
    else
        printf "\033[2K"
        printf "  ${R}✘${NC}  ${W}%-35s${NC}  ${R}gagal${NC}\n" "$label"
    fi
}

_note() { printf "  ${O}–${NC}  ${W}%-35s${NC}  ${D}%s${NC}\n" "$1" "$2"; }

# ── Banner ────────────────────────────────────────────────────
clear
_sep
_grad " ZV-MANAGER INSTALLER" 255 0 127 0 210 255
_grad " SSH, VMess & VLESS Tunneling Panel — Ubuntu 24.04 LTS" 0 210 255 160 80 255
_sep
echo ""

# ── Clone / Update repo ───────────────────────────────────────
echo -e "  ${C}»${NC} ${W}Persiapan...${NC}"
echo ""

_t_git_install() { apt-get install -y git; }
_t_git_clone()  { rm -rf "$REPO_DIR" && git clone -q "$GITHUB_URL" "$REPO_DIR"; }
_t_git_update() { git -C "$REPO_DIR" fetch -q origin && git -C "$REPO_DIR" reset -q --hard origin/main; }

if ! command -v git &>/dev/null; then
    _run_inline "Instalasi git" "berhasil" _t_git_install
fi

if [[ ! -d "$REPO_DIR/.git" ]]; then
    _run_inline "Download ZV-Manager" "berhasil" _t_git_clone
else
    _run_inline "Update repo" "berhasil" _t_git_update
fi
echo ""

[[ ! -d "$REPO_DIR" ]] && { echo "  ${R}[!]${NC} Gagal download repo!"; exit 1; }

SCRIPT_DIR="$REPO_DIR"
find "$REPO_DIR" -name "*.sh" -exec chmod +x {} \;
find "$REPO_DIR" -name "*.py" -exec chmod +x {} \;
chmod +x "$REPO_DIR/checker/zv-checker" 2>/dev/null

# ── Cek izin ─────────────────────────────────────────────────
source "$SCRIPT_DIR/core/license.sh"
check_license

# ── Pilihan mode instalasi ────────────────────────────────────
echo ""
_sep
_grad " PILIH MODE INSTALASI" 255 200 0 255 100 200
_sep
echo ""
echo -e "  $(_grad '[1]' 0 210 255 160 80 255) Install Baru"
echo -e "  ${R}[0]${NC} Batal"
echo ""
read -rp "  Pilihan [0-1]: " install_mode < /dev/tty

case "$install_mode" in
    0) echo ""; echo "  Instalasi dibatalkan."; exit 0 ;;
    *) install_mode="1" ;;
esac

echo ""

# ── Load utils ────────────────────────────────────────────────
source "$SCRIPT_DIR/utils/colors.sh"
source "$SCRIPT_DIR/utils/logger.sh"
source "$SCRIPT_DIR/utils/checker.sh"
source "$SCRIPT_DIR/utils/helpers.sh"
source "$SCRIPT_DIR/config.conf"

# ── System check ─────────────────────────────────────────────
echo ""
_sep
_grad " MEMERIKSA SISTEM" 0 210 255 160 80 255
_sep
echo ""
run_all_checks
echo ""

timer_start

# ── Task functions install ────────────────────────────────────
_t_copy_files() {
    mkdir -p "$INSTALL_DIR"
    cp -r "$SCRIPT_DIR"/* "$INSTALL_DIR/"
    find "$INSTALL_DIR" -name "*.sh" -exec chmod +x {} \;
    find "$INSTALL_DIR" -name "*.py" -exec chmod +x {} \;
    chmod +x "$INSTALL_DIR/checker/zv-checker" 2>/dev/null
    cp "$INSTALL_DIR/zv-agent.sh" /usr/local/bin/zv-agent
    chmod +x /usr/local/bin/zv-agent
    cp "$INSTALL_DIR/zv-vmess-agent.sh" /usr/local/bin/zv-vmess-agent
    chmod +x /usr/local/bin/zv-vmess-agent
    cp "$INSTALL_DIR/zv-vless-agent.sh" /usr/local/bin/zv-vless-agent
    chmod +x /usr/local/bin/zv-vless-agent
    cp "$INSTALL_DIR/zv-zivpn-agent.sh" /usr/local/bin/zv-zivpn-agent
    chmod +x /usr/local/bin/zv-zivpn-agent
    mkdir -p /etc/zv-manager/accounts/vless /etc/zv-manager/accounts/zivpn
}
_t_ssl()      { source "$INSTALL_DIR/core/ssl.sh" && setup_ssl; }
_t_system()   { source "$INSTALL_DIR/core/system.sh" && run_system_setup; }
_t_ssh()      { source "$INSTALL_DIR/services/ssh/install.sh" && install_ssh; }
_t_dropbear() { source "$INSTALL_DIR/services/dropbear/install.sh" && install_dropbear; }
_t_nginx()    { source "$INSTALL_DIR/services/nginx/install.sh" && install_nginx; }
_t_ws()       { source "$INSTALL_DIR/services/websocket/install.sh" && install_websocket; }
_t_udp()      { source "$INSTALL_DIR/services/udp/install.sh" && install_udp_custom; }
_t_badvpn()   { source "$INSTALL_DIR/services/badvpn/install.sh" && install_badvpn; }
_t_xray()     { source "$INSTALL_DIR/services/xray/install.sh" && install_xray; }
_t_zivpn()    { source "$INSTALL_DIR/services/zivpn/install.sh" && install_zivpn; }
_t_cron() {
    printf '%s\n' "* * * * * root for i in 1 2 3 4 5 6; do /bin/bash /etc/zv-manager/cron/autokill.sh; sleep 10; done" > /etc/cron.d/zv-autokill
    printf '%s\n' "*/5 * * * * root /bin/bash /etc/zv-manager/cron/trial-cleanup.sh" > /etc/cron.d/zv-trial
    printf '%s\n' "0 * * * * root /bin/bash /etc/zv-manager/cron/tg-notify.sh" > /etc/cron.d/zv-tg-notify
    printf '%s\n' "* * * * * root for i in 1 2 3 4 5; do /bin/bash /etc/zv-manager/cron/expired.sh; sleep 12; done" > /etc/cron.d/zv-expired
    printf '%s\n' "5 0 * * * root /bin/bash /etc/zv-manager/cron/license-check.sh" "0 7 * * * root /bin/bash /etc/zv-manager/cron/daily-report.sh" > /etc/cron.d/zv-license
    printf '%s\n' "* * * * * root for i in 1 2 3 4 5 6; do /bin/bash /etc/zv-manager/cron/bw-check.sh; sleep 10; done" "*/5 * * * * root /bin/bash /etc/zv-manager/cron/bw-vmess.sh" "*/5 * * * * root /bin/bash /etc/zv-manager/cron/bw-vless.sh" "* * * * * root /bin/bash /etc/zv-manager/cron/ip-limit.sh" > /etc/cron.d/zv-bw-check
    printf '%s\n' "*/5 * * * * root /bin/bash /etc/zv-manager/cron/watchdog.sh" > /etc/cron.d/zv-watchdog
    printf '%s\n' "*/5 * * * * root /bin/bash /etc/zv-manager/cron/worker-check.sh" > /etc/cron.d/zv-worker-check
    printf '%s\n' "*/5 * * * * root /bin/bash /etc/zv-manager/cron/trial-cleanup.sh" > /etc/cron.d/zv-trial
    printf '%s\n' "0 2 * * * root /bin/bash /etc/zv-manager/cron/backup.sh" > /etc/cron.d/zv-backup
    printf '%s\n' "0 6 * * * root /bin/bash /etc/zv-manager/cron/check-update.sh" > /etc/cron.d/zv-check-update
    mkdir -p /var/lib/zv-manager/status
    service cron restart &>/dev/null
    systemctl enable --now atd &>/dev/null || service atd start &>/dev/null || true
    /bin/bash /etc/zv-manager/cron/check-update.sh &>/dev/null &
}
_t_bw() {
    mkdir -p /tmp/zv-bw
    chmod +x /etc/zv-manager/core/bw-session.sh
    grep -q "bw-session.sh" /etc/pam.d/sshd || \
        echo "session optional pam_exec.so /etc/zv-manager/core/bw-session.sh" >> /etc/pam.d/sshd
    source /etc/zv-manager/core/bandwidth.sh
    for cf in /etc/zv-manager/accounts/ssh/*.conf; do
        [[ -f "$cf" ]] || continue
        uname=$(grep "^USERNAME=" "$cf" | cut -d= -f2 | tr -d '[:space:]')
        [[ -n "$uname" ]] && _bw_init_user "$uname"
    done
}
_t_menu() {
    mkdir -p /etc/zv-manager/servers
    ln -sf /etc/zv-manager/menu/menu.sh /usr/local/bin/menu
    chmod +x /usr/local/bin/menu
}

# ── Salin file ────────────────────────────────────────────────
if [[ "$install_mode" == "1" ]]; then
    echo ""
    _sep
    _grad " INSTALASI KOMPONEN" 0 210 255 160 80 255
    _sep
    echo ""
    _run "Salin file ZV-Manager" "berhasil" _t_copy_files
fi

# ── Setup Domain ──────────────────────────────────────────────
PUBLIC_IP=$(curl -s --max-time 10 ipv4.icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')
echo ""
echo -e "  ${D}IP Publik VPS:${NC} ${W}${PUBLIC_IP}${NC}"
echo ""
while true; do
    read -rp "  Domain (kosongkan = pakai IP): " _input_domain < /dev/tty
    _input_domain=$(echo "$_input_domain" | tr -d '[:space:]')
    if [[ -z "$_input_domain" ]]; then
        echo "$PUBLIC_IP" > /etc/zv-manager/domain
        printf "  ${G}✔${NC}  ${W}%-35s${NC}  ${D}%s${NC}\n" "Domain" "$PUBLIC_IP (ganti di Setup Web)"
        break
    fi
    if [[ "$_input_domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$_input_domain" > /etc/zv-manager/domain
        printf "  ${G}✔${NC}  ${W}%-35s${NC}  ${D}%s${NC}\n" "Domain" "$_input_domain"
        break
    fi
    printf "  ${D}Memverifikasi domain %s...${NC}\n" "$_input_domain"
    _resolved=""
    command -v dig &>/dev/null && _resolved=$(dig +short "$_input_domain" A 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
    [[ -z "$_resolved" ]] && command -v host &>/dev/null && _resolved=$(host -t A "$_input_domain" 2>/dev/null | awk '/has address/{print $4}' | head -1)
    if [[ -z "$_resolved" ]]; then
        echo -e "  ${R}[!]${NC} Domain tidak bisa di-resolve. Coba lagi atau kosongkan untuk pakai IP."
        continue
    elif [[ "$_resolved" != "$PUBLIC_IP" ]]; then
        echo -e "  ${R}[!]${NC} Domain mengarah ke ${_resolved}, bukan ${PUBLIC_IP}!"
        continue
    else
        echo "$_input_domain" > /etc/zv-manager/domain
        printf "  ${G}✔${NC}  ${W}%-35s${NC}  ${D}%s → %s${NC}\n" "Domain" "$_input_domain" "$_resolved"
        break
    fi
done
echo ""
_run "Setup SSL" "sertifikat dipasang" _t_ssl

_run "System Setup"    "selesai"         _t_system
_run "OpenSSH"         "berhasil dipasang" _t_ssh
_run "Dropbear"        "berhasil dipasang" _t_dropbear
_run "Nginx"           "berhasil dipasang" _t_nginx
_run "WebSocket Proxy" "berhasil dipasang" _t_ws
_run "UDP Custom"      "berhasil dipasang" _t_udp
_run "BadVPN UDPGW"    "berhasil dipasang" _t_badvpn
_run "Xray VMess+VLESS"  "berhasil dipasang" _t_xray
_run "ZiVPN UDP"        "berhasil dipasang" _t_zivpn

# ── Cron jobs ─────────────────────────────────────────────────
_run "Cron jobs"           "semua terjadwal"  _t_cron

# ── Bandwidth tracking ────────────────────────────────────────
_run "Bandwidth tracking"  "aktif"            _t_bw

# ── Global command ────────────────────────────────────────────
_run "Command 'menu'"      "siap digunakan"   _t_menu

# ── Versi & IP ────────────────────────────────────────────────
INSTALL_HASH=$(git -C /root/ZV-Manager rev-parse --short HEAD 2>/dev/null || echo "unknown")
sed -i "s/^COMMIT_HASH=.*/COMMIT_HASH=\"${INSTALL_HASH}\"/" /etc/zv-manager/config.conf
mkdir -p /etc/zv-manager/accounts
echo "$PUBLIC_IP" > /etc/zv-manager/accounts/ipvps

# ── Auto-launch menu saat login ───────────────────────────────
cat > /root/.profile <<'PROFILEEOF'
if [ "$BASH" ]; then if [ -f ~/.bashrc ]; then . ~/.bashrc; fi; fi
mesg n 2>/dev/null || true
case $- in *i*) ;; *) return ;; esac
[ -t 1 ] || return
[ -z "$SSH_TTY" ] && return
[ -n "$SSH_ORIGINAL_COMMAND" ] && return
menu
PROFILEEOF

# ── Selesai ───────────────────────────────────────────────────
echo ""
_sep
_grad " INSTALASI SELESAI!" 0 210 255 160 80 255
_sep
echo ""
printf "  ${D}≥${NC}  ${W}%-14s${NC}  ${G}%s${NC}\n" "IP VPS"  "${PUBLIC_IP}"
printf "  ${D}≥${NC}  ${W}%-14s${NC}  ${G}#%s${NC}\n" "Versi"   "${INSTALL_HASH}"
echo ""
printf "  ${D}≥${NC}  ${W}Port aktif:${NC}\n"
printf "  ${D}  –${NC}  %-14s  %s\n" "OpenSSH"  "22, 500, 40000"
printf "  ${D}  –${NC}  %-14s  %s\n" "Dropbear" "109, 143"
printf "  ${D}  –${NC}  %-14s  %s\n" "WS HTTP"  "80"
printf "  ${D}  –${NC}  %-14s  %s\n" "WS HTTPS" "443"
printf "  ${D}  –${NC}  %-14s  %s\n" "UDP"      "1-65535"
echo ""
printf "  ${D}≥${NC}  ${W}Status service:${NC}\n"
for svc in ssh dropbear nginx zv-wss zv-udp zv-xray zv-zivpn; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        printf "  ${G}  ✔${NC}  %s\n" "$svc"
    else
        printf "  ${R}  ✘${NC}  %-20s  ${R}tidak aktif${NC}\n" "$svc"
    fi
done
echo ""
timer_end
echo ""
echo ""


echo ""
echo -e "  ${O}Ketik 'y' lalu Enter untuk reboot (atau Ctrl+C untuk batal):${NC}"
while true; do
    read -rp "  > " _ans < /dev/tty
    [[ "$_ans" == "y" || "$_ans" == "Y" ]] && break
    echo -e "  ${D}Ketik 'y' untuk konfirmasi reboot.${NC}"
done
echo "  Rebooting..."
sleep 2
reboot
