#!/bin/bash
# ============================================================
#   ZV-Manager Installer
#   SSH Tunneling Manager for Ubuntu 24.04 LTS
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

# ── Progress bar ──────────────────────────────────────────────
_TOTAL_STEPS=15
_CURRENT_STEP=0

_progress() {
    local label="$1"
    _CURRENT_STEP=$(( _CURRENT_STEP + 1 ))
    local pct=$(( _CURRENT_STEP * 100 / _TOTAL_STEPS ))
    local filled=$(( pct / 5 ))
    local empty=$(( 20 - filled ))
    local bar=""
    for (( i=0; i<filled; i++ )); do bar+="█"; done
    for (( i=0; i<empty; i++ )); do bar+="░"; done
    printf "\r  ${C}[${bar}]${NC} ${W}%3d%%${NC} ${D}%s${NC}..." "$pct" "$label"
}

_done_step() {
    local label="$1" ok="$2"
    local pct=$(( _CURRENT_STEP * 100 / _TOTAL_STEPS ))
    local filled=$(( pct / 5 ))
    local empty=$(( 20 - filled ))
    local bar=""
    for (( i=0; i<filled; i++ )); do bar+="█"; done
    for (( i=0; i<empty; i++ )); do bar+="░"; done
    printf "\r\033[K"
    printf "  ${C}[${bar}]${NC} ${W}%3d%%${NC}  ${G}✔${NC}  ${W}%-28s${NC}  ${D}%s${NC}\n" "$pct" "$label" "$ok"
}

_fail_step() {
    printf "\r\033[K"
    printf "  ${R}✘${NC}  ${W}%-28s${NC}  ${R}gagal${NC}\n" "$1"
}

_run() {
    local label="$1" ok="$2"; shift 2
    _progress "$label"
    if "$@" >> "$_INSTALL_LOG" 2>&1; then
        _done_step "$label" "$ok"
    else
        _fail_step "$label"
    fi
}

_run_inline() {
    local label="$1" ok="$2"; shift 2
    printf "  ${D}»${NC}  %-38s\r" "$label"
    if "$@" >> "$_INSTALL_LOG" 2>&1; then
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
_grad " SSH & VMess Tunneling Panel — Ubuntu 24.04 LTS" 0 210 255 160 80 255
_sep
echo ""

# ── Clone / Update repo ───────────────────────────────────────
echo -e "  ${C}»${NC} ${W}Persiapan...${NC}"
echo ""

if ! command -v git &>/dev/null; then
    _run_inline "Instalasi git" "berhasil" apt-get install -y git
fi

if [[ ! -d "$REPO_DIR/.git" ]]; then
    _run_inline "Download ZV-Manager" "berhasil" \
        bash -c "rm -rf '$REPO_DIR' && git clone -q '$GITHUB_URL' '$REPO_DIR'"
else
    _run_inline "Update repo" "berhasil" \
        bash -c "git -C '$REPO_DIR' fetch -q origin && git -C '$REPO_DIR' reset -q --hard origin/main"
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
echo -e "  $(_grad '[2]' 0 210 255 160 80 255) Restore dari Backup"
echo -e "  ${R}[0]${NC} Batal"
echo ""
read -rp "  Pilihan [0-2]: " install_mode

case "$install_mode" in
    2)
        echo ""
        echo -e "  ${O}Masukkan path lengkap file backup (.zvbak):${NC}"
        echo    "  Contoh: /root/zv-backup-otak-2026-03-06.zvbak"
        echo ""
        read -rp "  Path file backup: " BACKUP_FILE
        if [[ ! -f "$BACKUP_FILE" ]]; then
            echo ""
            echo -e "  ${R}[!]${NC} File tidak ditemukan: ${BACKUP_FILE}"
            echo -e "  ${O}    Lanjut dengan install baru...${NC}"
            install_mode="1"
        else
            echo ""
            _sep
            _grad " RESTORE BACKUP" 0 210 255 160 80 255
            _sep
            echo ""

            _run_inline "Salin file ZV-Manager" "berhasil" bash -c "
                mkdir -p '$INSTALL_DIR'
                cp -r '$SCRIPT_DIR'/* '$INSTALL_DIR/'
                find '$INSTALL_DIR' -name '*.sh' -exec chmod +x {} \;
                find '$INSTALL_DIR' -name '*.py' -exec chmod +x {} \;
                chmod +x '$INSTALL_DIR/checker/zv-checker' 2>/dev/null
                cp '$INSTALL_DIR/zv-agent.sh' /usr/local/bin/zv-agent
                chmod +x /usr/local/bin/zv-agent
                cp '$INSTALL_DIR/zv-vmess-agent.sh' /usr/local/bin/zv-vmess-agent
                chmod +x /usr/local/bin/zv-vmess-agent
            "
            _run_inline "Restore data backup" "berhasil" \
                tar -xzf "$BACKUP_FILE" -C "$INSTALL_DIR/" 2>/dev/null

            if [[ -n "$RESTORE_NEW_TOKEN" && -n "$RESTORE_NEW_ADMIN" ]]; then
                sed -i "s|^TG_TOKEN=.*|TG_TOKEN=\"${RESTORE_NEW_TOKEN}\"|" "$INSTALL_DIR/telegram.conf" 2>/dev/null
                sed -i "s|^TG_ADMIN=.*|TG_ADMIN=\"${RESTORE_NEW_ADMIN}\"|" "$INSTALL_DIR/telegram.conf" 2>/dev/null
            fi
            echo ""

            echo -e "  ${O}Apakah domain berubah dari sebelumnya?${NC}"
            read -rp "  Ganti domain? [y/n]: " ganti_domain
            [[ "$ganti_domain" =~ ^[Yy]$ ]] && install_mode="restore_with_domain" || install_mode="restore_skip_domain"

            echo ""
            echo -e "  ${O}Apakah Telegram Bot Token & Admin ID masih sama?${NC}"
            read -rp "  Token & Admin masih sama? [y/n]: " same_tg
            if [[ "$same_tg" =~ ^[Nn]$ ]]; then
                echo ""
                read -rp "  Bot Token baru: " _new_token
                read -rp "  Admin Telegram ID baru: " _new_admin
                RESTORE_NEW_TOKEN="$_new_token"
                RESTORE_NEW_ADMIN="$_new_admin"
            fi
        fi
        ;;
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

# ── Salin file ────────────────────────────────────────────────
if [[ "$install_mode" == "1" ]]; then
    _CURRENT_STEP=0
    echo ""
    _sep
    _grad " INSTALASI KOMPONEN" 0 210 255 160 80 255
    _sep
    echo ""

    _run "Salin file ZV-Manager" "berhasil" bash -c "
        mkdir -p '$INSTALL_DIR'
        cp -r '$SCRIPT_DIR'/* '$INSTALL_DIR/'
        find '$INSTALL_DIR' -name '*.sh' -exec chmod +x {} \;
        find '$INSTALL_DIR' -name '*.py' -exec chmod +x {} \;
        chmod +x '$INSTALL_DIR/checker/zv-checker' 2>/dev/null
        cp '$INSTALL_DIR/zv-agent.sh' /usr/local/bin/zv-agent
        chmod +x /usr/local/bin/zv-agent
        cp '$INSTALL_DIR/zv-vmess-agent.sh' /usr/local/bin/zv-vmess-agent
        chmod +x /usr/local/bin/zv-vmess-agent
    "
fi

# ── Setup Domain ──────────────────────────────────────────────
if [[ "$install_mode" == "restore_skip_domain" ]]; then
    _note "Domain" "dipertahankan dari backup"
    _note "SSL" "dipertahankan dari backup"
else
    PUBLIC_IP=$(curl -s --max-time 10 ipv4.icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')
    echo ""
    echo -e "  ${D}IP Publik VPS:${NC} ${W}${PUBLIC_IP}${NC}"
    echo ""
    read -rp "  Domain untuk VPS ini (kosongkan = pakai IP): " _input_domain
    _input_domain=$(echo "$_input_domain" | tr -d '[:space:]')
    if [[ -n "$_input_domain" && ! "$_input_domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$_input_domain" > /etc/zv-manager/domain
        printf "  ${G}✔${NC}  ${W}%-35s${NC}  ${D}%s${NC}\n" "Domain" "$_input_domain"
    else
        echo "$PUBLIC_IP" > /etc/zv-manager/domain
        printf "  ${G}✔${NC}  ${W}%-35s${NC}  ${D}%s${NC}\n" "Domain" "menggunakan IP: $PUBLIC_IP"
    fi
    echo ""

    _run "Setup SSL" "sertifikat dipasang" \
        bash -c "source '$INSTALL_DIR/core/ssl.sh' && setup_ssl"
fi

_run "System Setup"    "selesai" bash -c "source '$INSTALL_DIR/core/system.sh' && run_system_setup"
_run "OpenSSH"         "berhasil dipasang" bash -c "source '$INSTALL_DIR/services/ssh/install.sh' && install_ssh"
_run "Dropbear"        "berhasil dipasang" bash -c "source '$INSTALL_DIR/services/dropbear/install.sh' && install_dropbear"
_run "Nginx"           "berhasil dipasang" bash -c "source '$INSTALL_DIR/services/nginx/install.sh' && install_nginx"
_run "WebSocket Proxy" "berhasil dipasang" bash -c "source '$INSTALL_DIR/services/websocket/install.sh' && install_websocket"
_run "UDP Custom"      "berhasil dipasang" bash -c "source '$INSTALL_DIR/services/udp/install.sh' && install_udp_custom"
_run "BadVPN UDPGW"    "berhasil dipasang" bash -c "source '$INSTALL_DIR/services/badvpn/install.sh' && install_badvpn"
_run "Xray VMess"      "berhasil dipasang" bash -c "source '$INSTALL_DIR/services/xray/install.sh' && install_xray"

# ── Cron jobs ─────────────────────────────────────────────────
_progress "Cron jobs"
{
cat > /etc/cron.d/zv-autokill <<'CRONEOF'
* * * * * root for i in 1 2 3 4 5 6; do /bin/bash /etc/zv-manager/cron/autokill.sh; sleep 10; done
CRONEOF
cat > /etc/cron.d/zv-trial <<'CRONEOF'
*/1 * * * * root /bin/bash /etc/zv-manager/cron/trial-cleanup.sh
CRONEOF
cat > /etc/cron.d/zv-tg-notify <<'CRONEOF'
0 * * * * root /bin/bash /etc/zv-manager/cron/tg-notify.sh
CRONEOF
cat > /etc/cron.d/zv-expired <<'CRONEOF'
* * * * * root for i in 1 2 3 4 5; do /bin/bash /etc/zv-manager/cron/expired.sh; sleep 12; done
CRONEOF
cat > /etc/cron.d/zv-license <<'CRONEOF'
5 0 * * * root /bin/bash /etc/zv-manager/cron/license-check.sh
0 7 * * * root /bin/bash /etc/zv-manager/cron/daily-report.sh
CRONEOF
cat > /etc/cron.d/zv-bw-check <<'CRONEOF'
* * * * * root for i in 1 2 3 4 5 6; do /bin/bash /etc/zv-manager/cron/bw-check.sh; sleep 10; done
*/5 * * * * root /bin/bash /etc/zv-manager/cron/bw-vmess.sh
* * * * * root /bin/bash /etc/zv-manager/cron/ip-limit.sh
CRONEOF
cat > /etc/cron.d/zv-watchdog <<'CRONEOF'
*/5 * * * * root /bin/bash /etc/zv-manager/cron/watchdog.sh
CRONEOF
cat > /etc/cron.d/zv-worker-check <<'CRONEOF'
*/5 * * * * root /bin/bash /etc/zv-manager/cron/worker-check.sh
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
/bin/bash /etc/zv-manager/cron/check-update.sh &>/dev/null &
/bin/bash /etc/zv-manager/cron/status-page.sh &>/dev/null &
} >> "$_INSTALL_LOG" 2>&1
_done_step "Cron jobs" "semua terjadwal"

# ── Bandwidth tracking ────────────────────────────────────────
_progress "Bandwidth tracking"
{
mkdir -p /tmp/zv-bw
chmod +x /etc/zv-manager/core/bw-session.sh
if ! grep -q "bw-session.sh" /etc/pam.d/sshd; then
    echo "session optional pam_exec.so /etc/zv-manager/core/bw-session.sh" >> /etc/pam.d/sshd
fi
source /etc/zv-manager/core/bandwidth.sh
for cf in /etc/zv-manager/accounts/ssh/*.conf; do
    [[ -f "$cf" ]] || continue
    uname=$(grep "^USERNAME=" "$cf" | cut -d= -f2 | tr -d '[:space:]')
    [[ -n "$uname" ]] && _bw_init_user "$uname"
done
} >> "$_INSTALL_LOG" 2>&1
_done_step "Bandwidth tracking" "aktif"

# ── Global command ────────────────────────────────────────────
_progress "Command menu"
{
mkdir -p /etc/zv-manager/servers
ln -sf /etc/zv-manager/menu/menu.sh /usr/local/bin/menu
chmod +x /usr/local/bin/menu
} >> "$_INSTALL_LOG" 2>&1
_done_step "Command 'menu'" "siap digunakan"

# ── Restore: recreate SSH users + inject Xray + install bot ──
if [[ "$install_mode" == restore_* ]]; then
    echo ""
    _sep
    _grad " RESTORE AKUN & SERVICES" 0 210 255 160 80 255
    _sep
    echo ""

    local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null | tr -d '[:space:]')
    ssh_ok=0
    for cf in /etc/zv-manager/accounts/ssh/*.conf; do
        [[ -f "$cf" ]] || continue
        _u=$(grep "^USERNAME=" "$cf" | cut -d= -f2 | tr -d '"[:space:]')
        _p=$(grep "^PASSWORD=" "$cf" | cut -d= -f2 | tr -d '"[:space:]')
        _srv=$(grep "^SERVER=" "$cf" | cut -d= -f2 | tr -d '"')
        _sip=""
        for sc in /etc/zv-manager/servers/*.conf; do
            _sname=$(grep "^NAME=" "$sc" 2>/dev/null | cut -d= -f2 | tr -d '"')
            [[ "$_sname" == "$_srv" ]] && _sip=$(grep "^IP=" "$sc" 2>/dev/null | cut -d= -f2 | tr -d '"') && break
        done
        if [[ -z "$_sip" || "$_sip" == "$local_ip" ]]; then
            if [[ -n "$_u" && -n "$_p" ]]; then
                ! id "$_u" &>/dev/null && useradd -M -s /bin/false "$_u" 2>/dev/null && echo "$_u:$_p" | chpasswd 2>/dev/null
                ssh_ok=$((ssh_ok+1))
            fi
        fi
    done >> "$_INSTALL_LOG" 2>&1
    printf "  ${G}✔${NC}  ${W}%-35s${NC}  ${D}%s${NC}\n" "Recreate SSH users" "${ssh_ok} akun"

    vmess_ok=0
    for cf in /etc/zv-manager/accounts/vmess/*.conf; do
        [[ -f "$cf" ]] || continue
        _u=$(grep "^USERNAME=" "$cf" | cut -d= -f2 | tr -d '"[:space:]')
        _uuid=$(grep "^UUID=" "$cf" | cut -d= -f2 | tr -d '"[:space:]')
        _srv=$(grep "^SERVER=" "$cf" | cut -d= -f2 | tr -d '"')
        _sip=""
        for sc in /etc/zv-manager/servers/*.conf; do
            _sname=$(grep "^NAME=" "$sc" 2>/dev/null | cut -d= -f2 | tr -d '"')
            [[ "$_sname" == "$_srv" ]] && _sip=$(grep "^IP=" "$sc" 2>/dev/null | cut -d= -f2 | tr -d '"') && break
        done
        if [[ -z "$_sip" || "$_sip" == "$local_ip" ]]; then
            if [[ -n "$_u" && -n "$_uuid" ]]; then
                /usr/local/bin/xray api adu -s "127.0.0.1:10085" -inbound "vmess-ws" \
                    -user "{\"vmess\":{\"id\":\"${_uuid}\",\"email\":\"${_u}@vmess\",\"alterId\":0}}" &>/dev/null || true
                /usr/local/bin/xray api adu -s "127.0.0.1:10085" -inbound "vmess-grpc" \
                    -user "{\"vmess\":{\"id\":\"${_uuid}\",\"email\":\"${_u}@vmess\",\"alterId\":0}}" &>/dev/null || true
                vmess_ok=$((vmess_ok+1))
            fi
        fi
    done >> "$_INSTALL_LOG" 2>&1
    bash /usr/local/bin/zv-vmess-agent rebuild-config >> "$_INSTALL_LOG" 2>&1 || true
    systemctl restart zv-xray >> "$_INSTALL_LOG" 2>&1
    printf "  ${G}✔${NC}  ${W}%-35s${NC}  ${D}%s${NC}\n" "Recreate VMess clients" "${vmess_ok} akun"

    { source /opt/zv-telegram/install.sh && install_telegram_bot; } >> "$_INSTALL_LOG" 2>&1
    printf "  ${G}✔${NC}  ${W}%-35s${NC}  ${D}aktif${NC}\n" "Telegram Bot"

    _restore_date=$(TZ="Asia/Jakarta" date +"%Y-%m-%d %H:%M WIB")
    _new_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null | tr -d '[:space:]')
    cat > /etc/zv-manager/.restore_pending << FLAGEOF
SSH_OK=${ssh_ok}
VMESS_OK=${vmess_ok}
IP=${_new_ip}
DATE=${_restore_date}
FLAGEOF
    printf "  ${G}✔${NC}  ${W}%-35s${NC}  ${D}bot akan notif admin saat startup${NC}\n" "Flag restore"
fi

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
for svc in ssh dropbear nginx zv-wss zv-udp zv-xray; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        printf "  ${G}  ✔${NC}  %s\n" "$svc"
    else
        printf "  ${R}  ✘${NC}  %-20s  ${R}tidak aktif${NC}\n" "$svc"
    fi
done
echo ""
timer_end
echo ""
echo -e "  ${O}Reboot diperlukan agar semua service aktif.${NC}"
echo ""
read -rp "  Reboot sekarang? [y/n]: " reboot_ans
[[ "$reboot_ans" =~ ^[Yy]$ ]] && echo "  Rebooting..." && sleep 2 && reboot
