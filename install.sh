#!/bin/bash
# ============================================================
#   ZV-Manager Installer
#   SSH Tunneling Manager for Ubuntu 24.04 LTS
#   https://github.com/ZenXNF/ZV-Manager
# ============================================================

INSTALL_DIR="/etc/zv-manager"
REPO_DIR="/root/ZV-Manager"
GITHUB_URL="https://github.com/ZenXNF/ZV-Manager.git"

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

# --- Banner ---
clear
echo -e "\033[1;36m"
echo "  ╔══════════════════════════════════════╗"
echo "  ║       Z V - M A N A G E R           ║"
echo "  ║  SSH Tunneling Manager                ║"
echo "  ║  Ubuntu 24.04 LTS                    ║"
echo "  ╚══════════════════════════════════════╝"
echo -e "\033[0m"
echo -e "\033[0;36m  ──────────────────────────────────────\033[0m"
echo ""

# --- Clone / update repo dulu sebelum apapun ---
if ! command -v git &>/dev/null; then
    echo "[ INFO ] Menginstall git..."
    apt-get install -y git &>/dev/null
fi

if [[ ! -d "$REPO_DIR/.git" ]]; then
    echo "[ INFO ] Mengunduh ZV-Manager dari GitHub..."
    rm -rf "$REPO_DIR"
    git clone -q "$GITHUB_URL" "$REPO_DIR"
else
    echo "[ INFO ] Memperbarui repo..."
    git -C "$REPO_DIR" fetch -q origin
    git -C "$REPO_DIR" reset -q --hard origin/main
fi

if [[ ! -d "$REPO_DIR" ]]; then
    echo "[ERROR] Gagal mengunduh repo dari GitHub!"
    exit 1
fi

# Setelah clone, semua operasi dari repo
SCRIPT_DIR="$REPO_DIR"
find "$REPO_DIR" -name "*.sh" -exec chmod +x {} \;
find "$REPO_DIR" -name "*.py" -exec chmod +x {} \;
chmod +x "$REPO_DIR/checker/zv-checker" 2>/dev/null

# --- Cek izin SEBELUM tanya konfirmasi ---
source "$SCRIPT_DIR/core/license.sh"
check_license

# --- Pilihan: Restore atau Install Baru ---
echo -e "\033[1;36m  ┌──────────────────────────────────────┐"
echo -e "  │        Pilih Mode Instalasi          │"
echo -e "  └──────────────────────────────────────┘\033[0m"
echo ""
echo -e "  \033[1;32m[1]\033[0m Install Baru"
echo -e "  \033[1;32m[2]\033[0m Restore dari Backup"
echo -e "  \033[1;31m[0]\033[0m Batal"
echo ""
read -rp "  Pilihan: " install_mode

case "$install_mode" in
    2)
        echo ""
        echo -e "  \033[1;33mMasukkan path lengkap file backup (.tar.gz):"
        echo -e "  Contoh: /root/zv-backup-otak-2026-03-06.tar.gz\033[0m"
        echo ""
        read -rp "  Path file backup: " BACKUP_FILE

        if [[ ! -f "$BACKUP_FILE" ]]; then
            echo ""
            echo -e "  \033[1;31m[ERROR] File tidak ditemukan: ${BACKUP_FILE}\033[0m"
            echo -e "  \033[1;33m        Lanjut dengan install baru...\033[0m"
            echo ""
            install_mode="1"
        else
            echo ""
            echo -e "  \033[1;32m[ INFO ] File backup ditemukan. Memulai restore...\033[0m"
            echo ""

            # Copy file dulu ke /etc/zv-manager
            mkdir -p "$INSTALL_DIR"
            cp -r "$SCRIPT_DIR"/* "$INSTALL_DIR/"
            find "$INSTALL_DIR" -name "*.sh" -exec chmod +x {} \;
            find "$INSTALL_DIR" -name "*.py" -exec chmod +x {} \;
            chmod +x "$INSTALL_DIR/checker/zv-checker" 2>/dev/null
            cp "$INSTALL_DIR/zv-agent.sh" /usr/local/bin/zv-agent
            chmod +x /usr/local/bin/zv-agent
            cp "$INSTALL_DIR/zv-vmess-agent.sh" /usr/local/bin/zv-vmess-agent
            chmod +x /usr/local/bin/zv-vmess-agent

            # Extract backup — timpa data yang ada
            echo "[ INFO ] Merestore data dari backup..."
            tar -xzf "$BACKUP_FILE" -C "$INSTALL_DIR/" 2>/dev/null
            echo -e "  \033[1;32m✔ Data berhasil direstore\033[0m"
            echo ""

            # Tanya domain baru
            echo -e "  \033[1;33mApakah domain berubah dari sebelumnya?\033[0m"
            read -rp "  Ganti domain? [y/n]: " ganti_domain
            if [[ "$ganti_domain" =~ ^[Yy]$ ]]; then
                install_mode="restore_with_domain"
            else
                install_mode="restore_skip_domain"
            fi
        fi
        ;;
    0)
        echo ""
        echo "  Instalasi dibatalkan."
        exit 0
        ;;
    *)
        install_mode="1"
        ;;
esac

echo ""
echo "[ INFO ] Menyalin file ke ${INSTALL_DIR}..."

# --- Copy semua file ke /etc/zv-manager (skip kalau restore sudah copy) ---
if [[ "$install_mode" == "1" ]]; then
    mkdir -p "$INSTALL_DIR"
    cp -r "$SCRIPT_DIR"/* "$INSTALL_DIR/"
    find "$INSTALL_DIR" -name "*.sh" -exec chmod +x {} \;
    find "$INSTALL_DIR" -name "*.py" -exec chmod +x {} \;
    chmod +x "$INSTALL_DIR/checker/zv-checker" 2>/dev/null
    cp "$INSTALL_DIR/zv-agent.sh" /usr/local/bin/zv-agent
    chmod +x /usr/local/bin/zv-agent
    cp "$INSTALL_DIR/zv-vmess-agent.sh" /usr/local/bin/zv-vmess-agent
    chmod +x /usr/local/bin/zv-vmess-agent
fi

echo "[ INFO ] File berhasil disalin"
echo ""

# --- Load utils ---
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
if [[ "$install_mode" == "restore_skip_domain" ]]; then
    echo "[ INFO ] Domain dipertahankan dari backup, skip setup domain."
else
    setup_domain
fi

source "$INSTALL_DIR/core/ssl.sh"
if [[ "$install_mode" == "restore_skip_domain" ]]; then
    echo "[ INFO ] SSL dipertahankan dari backup, skip setup SSL."
else
    setup_ssl
fi

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

source "$INSTALL_DIR/services/badvpn/install.sh"
install_badvpn

source "$INSTALL_DIR/services/xray/install.sh"
install_xray

# --- Setup Cron Jobs ---
print_section "Setup Cron Jobs"

cat > /etc/cron.d/zv-autokill <<'CRONEOF'
# ZV-Manager - Auto Kill Multi-Login
*/1 * * * * root /bin/bash /etc/zv-manager/cron/autokill.sh
CRONEOF

cat > /etc/cron.d/zv-trial <<'CRONEOF'
# ZV-Manager - Trial Account Cleanup (tiap menit)
*/1 * * * * root /bin/bash /etc/zv-manager/cron/trial-cleanup.sh
CRONEOF

cat > /etc/cron.d/zv-tg-notify <<'CRONEOF'
# ZV-Manager - Notifikasi Telegram expired (tiap jam)
0 * * * * root /bin/bash /etc/zv-manager/cron/tg-notify.sh
CRONEOF

cat > /etc/cron.d/zv-expired <<'CRONEOF'
# ZV-Manager - Auto Delete Expired Users
2 0 * * * root /bin/bash /etc/zv-manager/cron/expired.sh
CRONEOF

cat > /etc/cron.d/zv-license <<'CRONEOF'
# ZV-Manager - Cek Izin Harian (jam 00:05)
5 0 * * * root /bin/bash /etc/zv-manager/cron/license-check.sh
0 7 * * * root /bin/bash /etc/zv-manager/cron/daily-report.sh
CRONEOF

cat > /etc/cron.d/zv-check-update <<'CRONEOF'
# ZV-Manager - Cek Update sekali sehari jam 06:00
0 6 * * * root /bin/bash /etc/zv-manager/cron/check-update.sh
CRONEOF

cat > /etc/cron.d/zv-watchdog <<'CRONEOF'
# ZV-Manager - Watchdog: monitor & auto-restart service tiap 5 menit
*/5 * * * * root /bin/bash /etc/zv-manager/cron/watchdog.sh
CRONEOF

cat > /etc/cron.d/zv-bw-check <<'CRONEOF'
# ZV-Manager - Bandwidth Check tiap 5 menit (SSH)
*/5 * * * * root /bin/bash /etc/zv-manager/cron/bw-check.sh
# ZV-Manager - Bandwidth Monitor VMess tiap 5 menit
*/5 * * * * root /bin/bash /etc/zv-manager/cron/bw-vmess.sh
# ZV-Manager - IP Limit VMess tiap menit
* * * * * root /bin/bash /etc/zv-manager/cron/ip-limit.sh
CRONEOF

cat > /etc/cron.d/zv-backup <<'CRONEOF'
# ZV-Manager - Backup harian jam 02:00
0 2 * * * root /bin/bash /etc/zv-manager/cron/backup.sh
CRONEOF

service cron restart &>/dev/null
# Jalankan cek update sekali sekarang (background, tidak blocking)
/bin/bash /etc/zv-manager/cron/check-update.sh &>/dev/null &
print_success "Cron Jobs"

# --- Setup Bandwidth Tracking (PAM) ---
print_section "Setup Bandwidth Tracking"
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
print_success "Bandwidth Tracking"

# --- Setup menu command global ---
print_section "Setup Global Command"
mkdir -p /etc/zv-manager/servers
ln -sf /etc/zv-manager/menu/menu.sh /usr/local/bin/menu
chmod +x /usr/local/bin/menu
print_ok "Command 'menu' siap digunakan"

# --- Simpan commit hash saat install ---
INSTALL_HASH=$(git -C /root/ZV-Manager rev-parse --short HEAD 2>/dev/null || echo "unknown")
sed -i "s/^COMMIT_HASH=.*/COMMIT_HASH=\"${INSTALL_HASH}\"/" /etc/zv-manager/config.conf
print_ok "Versi: #${INSTALL_HASH}"

# --- Simpan IP VPS ---
mkdir -p /etc/zv-manager/accounts
echo "$PUBLIC_IP" > /etc/zv-manager/accounts/ipvps

# --- Setup auto-launch menu saat login SSH ---
cat > /root/.profile <<'PROFILEEOF'
if [ "$BASH" ]; then
    if [ -f ~/.bashrc ]; then
        . ~/.bashrc
    fi
fi
mesg n 2>/dev/null || true

case $- in
    *i*) ;;
    *) return ;;
esac
[ -t 1 ] || return
[ -z "$SSH_TTY" ] && return
[ -n "$SSH_ORIGINAL_COMMAND" ] && return

menu
PROFILEEOF

# --- Selesai ---
ZV_IP="$PUBLIC_IP"

echo ""
echo -e "${BCYAN}"
echo "  ╔══════════════════════════════════════╗"
echo "  ║      INSTALASI SELESAI!              ║"
echo "  ╚══════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  ${BWHITE}IP VPS   :${NC} ${BGREEN}${ZV_IP}${NC}"
echo ""
echo -e "  ${BWHITE}OpenSSH  :${NC} ${BPURPLE}22, 500, 40000${NC}"
echo -e "  ${BWHITE}Dropbear :${NC} ${BPURPLE}109, 143${NC}"
echo -e "  ${BWHITE}WS HTTP  :${NC} ${BPURPLE}80${NC}"
echo -e "  ${BWHITE}WS HTTPS :${NC} ${BPURPLE}443${NC}"
echo -e "  ${BWHITE}UDP      :${NC} ${BPURPLE}1-65535${NC}"
echo ""

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
