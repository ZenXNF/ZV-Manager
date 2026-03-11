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

if [[ "$EUID" -ne 0 ]]; then
    echo "  [!] Jalankan script ini sebagai root!"
    exit 1
fi
if [[ "$(uname -m)" != "x86_64" ]]; then
    echo "  [!] Arsitektur tidak didukung: $(uname -m)"
    exit 1
fi

# ── Helpers output ────────────────────────────────────────────
_step() {
    # $1=label, $2=ok_msg, $3+=command
    local name="$1" ok_msg="$2"; shift 2
    echo -e "\033[33m  ──────────────────────────────────────\033[0m"
    printf  "  \033[1m%s\033[0m\n" "$name"
    echo -e "\033[33m  ──────────────────────────────────────\033[0m"
    printf  "  \033[33m>\033[0m  Memproses...\r"
    if "$@" >> "$_INSTALL_LOG" 2>&1; then
        printf "\033[2K"
        printf "  \033[32m+\033[0m  \033[1m%-35s\033[0m  %s\n\n" "$name" "$ok_msg"
    else
        printf "\033[2K"
        printf "  \033[31m!\033[0m  \033[1m%-35s\033[0m  \033[31mgagal (lihat $_INSTALL_LOG)\033[0m\n\n" "$name"
    fi
}

_step_inline() {
    # Tanpa header section — langsung 1 baris dengan spinner
    local name="$1" ok_msg="$2"; shift 2
    printf "  \033[33m>\033[0m  %-38s\r" "$name"
    if "$@" >> "$_INSTALL_LOG" 2>&1; then
        printf "\033[2K"
        printf "  \033[32m+\033[0m  \033[1m%-35s\033[0m  %s\n" "$name" "$ok_msg"
    else
        printf "\033[2K"
        printf "  \033[31m!\033[0m  \033[1m%-35s\033[0m  \033[31mgagal (lihat $_INSTALL_LOG)\033[0m\n" "$name"
    fi
}

_note() {
    printf "  \033[33m-\033[0m  \033[1m%-35s\033[0m  \033[33m%s\033[0m\n" "$1" "$2"
}

_ok() {
    printf "  \033[32m+\033[0m  \033[1m%-35s\033[0m  %s\n" "$1" "$2"
}

# ── Banner ────────────────────────────────────────────────────
clear
printf "\033[1;36m"
echo "  ╔══════════════════════════════════════╗"
echo "  ║       Z V - M A N A G E R           ║"
echo "  ║  SSH Tunneling Manager               ║"
echo "  ║  Ubuntu 24.04 LTS                   ║"
echo "  ╚══════════════════════════════════════╝"
printf "\033[0m\n"

# ── Clone / Update repo ───────────────────────────────────────
echo -e "\033[33m  ──────────────────────────────────────\033[0m"
echo -e "  \033[1mPersiapan\033[0m"
echo -e "\033[33m  ──────────────────────────────────────\033[0m"

if ! command -v git &>/dev/null; then
    _step_inline "Instalasi git" "berhasil" apt-get install -y git
fi

if [[ ! -d "$REPO_DIR/.git" ]]; then
    _step_inline "Download ZV-Manager" "berhasil" \
        bash -c "rm -rf '$REPO_DIR' && git clone -q '$GITHUB_URL' '$REPO_DIR'"
else
    _step_inline "Update repo" "berhasil" \
        bash -c "git -C '$REPO_DIR' fetch -q origin && git -C '$REPO_DIR' reset -q --hard origin/main"
fi
echo ""

if [[ ! -d "$REPO_DIR" ]]; then
    echo "  [!] Gagal download repo dari GitHub!"
    exit 1
fi

SCRIPT_DIR="$REPO_DIR"
find "$REPO_DIR" -name "*.sh" -exec chmod +x {} \;
find "$REPO_DIR" -name "*.py" -exec chmod +x {} \;
chmod +x "$REPO_DIR/checker/zv-checker" 2>/dev/null

# ── Cek izin ─────────────────────────────────────────────────
source "$SCRIPT_DIR/core/license.sh"
check_license

# ── Pilihan mode instalasi ────────────────────────────────────
echo ""
echo -e "\033[1;36m  ┌──────────────────────────────────────┐"
echo    "  │        Pilih Mode Instalasi          │"
echo -e "  └──────────────────────────────────────┘\033[0m"
echo ""
echo -e "  \033[1;32m[1]\033[0m  Install Baru"
echo -e "  \033[1;32m[2]\033[0m  Restore dari Backup"
echo -e "  \033[1;31m[0]\033[0m  Batal"
echo ""
read -rp "  Pilihan: " install_mode

case "$install_mode" in
    2)
        echo ""
        echo -e "  \033[1;33mMasukkan path lengkap file backup (.tar.gz):\033[0m"
        echo    "  Contoh: /root/zv-backup-otak-2026-03-06.tar.gz"
        echo ""
        read -rp "  Path file backup: " BACKUP_FILE
        if [[ ! -f "$BACKUP_FILE" ]]; then
            echo ""
            echo -e "  \033[1;31m[!] File tidak ditemukan: ${BACKUP_FILE}\033[0m"
            echo -e "  \033[1;33m    Lanjut dengan install baru...\033[0m"
            echo ""
            install_mode="1"
        else
            echo ""
            echo -e "\033[33m  ──────────────────────────────────────\033[0m"
            echo -e "  \033[1mRestore Backup\033[0m"
            echo -e "\033[33m  ──────────────────────────────────────\033[0m"

            _step_inline "Salin file ZV-Manager" "berhasil" bash -c "
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

            _step_inline "Restore data backup" "berhasil" \
                tar -xzf "$BACKUP_FILE" -C "$INSTALL_DIR/" 2>/dev/null
            echo ""

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

# ── Salin file ────────────────────────────────────────────────
if [[ "$install_mode" == "1" ]]; then
    _step_inline "Salin file ZV-Manager" "berhasil" bash -c "
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
    echo ""
fi

# ── Load utils ────────────────────────────────────────────────
source "$SCRIPT_DIR/utils/colors.sh"
source "$SCRIPT_DIR/utils/logger.sh"
source "$SCRIPT_DIR/utils/checker.sh"
source "$SCRIPT_DIR/utils/helpers.sh"
source "$SCRIPT_DIR/config.conf"

# ── System check ─────────────────────────────────────────────
echo -e "\033[33m  ──────────────────────────────────────\033[0m"
echo -e "  \033[1mMemeriksa Sistem\033[0m"
echo -e "\033[33m  ──────────────────────────────────────\033[0m"
run_all_checks
echo ""

timer_start

# ── Install services ──────────────────────────────────────────
echo -e "\033[33m  ──────────────────────────────────────\033[0m"
echo -e "  \033[1mInstalasi Komponen\033[0m"
echo -e "\033[33m  ──────────────────────────────────────\033[0m"
echo ""

_step "System Setup" "selesai" \
    bash -c "source '$INSTALL_DIR/core/system.sh' && run_system_setup"

if [[ "$install_mode" == "restore_skip_domain" ]]; then
    _note "Domain" "dipertahankan dari backup"
else
    _step "Setup Domain" "selesai" \
        bash -c "source '$INSTALL_DIR/core/domain.sh' && setup_domain"
fi

if [[ "$install_mode" == "restore_skip_domain" ]]; then
    _note "SSL / Stunnel" "dipertahankan dari backup"
else
    _step "Setup SSL" "sertifikat dipasang" \
        bash -c "source '$INSTALL_DIR/core/ssl.sh' && setup_ssl"
fi

_step "OpenSSH" "berhasil dipasang" \
    bash -c "source '$INSTALL_DIR/services/ssh/install.sh' && install_ssh"

_step "Dropbear" "berhasil dipasang" \
    bash -c "source '$INSTALL_DIR/services/dropbear/install.sh' && install_dropbear"

_step "Nginx" "berhasil dipasang" \
    bash -c "source '$INSTALL_DIR/services/nginx/install.sh' && install_nginx"

_step "WebSocket Proxy" "berhasil dipasang" \
    bash -c "source '$INSTALL_DIR/services/websocket/install.sh' && install_websocket"

_step "UDP Custom" "berhasil dipasang" \
    bash -c "source '$INSTALL_DIR/services/udp/install.sh' && install_udp_custom"

_step "BadVPN UDPGW" "berhasil dipasang" \
    bash -c "source '$INSTALL_DIR/services/badvpn/install.sh' && install_badvpn"

_step "Xray VMess" "berhasil dipasang" \
    bash -c "source '$INSTALL_DIR/services/xray/install.sh' && install_xray"

# ── Cron jobs ─────────────────────────────────────────────────
echo -e "\033[33m  ──────────────────────────────────────\033[0m"
echo -e "  \033[1mSetup Cron Jobs\033[0m"
echo -e "\033[33m  ──────────────────────────────────────\033[0m"
echo ""
{
cat > /etc/cron.d/zv-autokill <<'CRONEOF'
# ZV-Manager - Auto Kill Multi-Login (tiap 10 detik)
* * * * * root for i in 1 2 3 4 5 6; do /bin/bash /etc/zv-manager/cron/autokill.sh; sleep 10; done
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
# SSH IP check tiap 10 detik (loop 6x per menit)
* * * * * root for i in 1 2 3 4 5 6; do /bin/bash /etc/zv-manager/cron/bw-check.sh; sleep 10; done
*/5 * * * * root /bin/bash /etc/zv-manager/cron/bw-vmess.sh
* * * * * root /bin/bash /etc/zv-manager/cron/ip-limit.sh
# VMess online check tiap 30 detik (loop 2x per menit)
* * * * * root for i in 1 2; do /bin/bash /etc/zv-manager/cron/vmess-online.sh; sleep 30; done
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
/bin/bash /etc/zv-manager/cron/check-update.sh &>/dev/null &
/bin/bash /etc/zv-manager/cron/status-page.sh &>/dev/null &
} >> "$_INSTALL_LOG" 2>&1
_ok "Cron jobs" "semua terjadwal"
echo ""

# ── Bandwidth tracking ────────────────────────────────────────
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
_ok "Bandwidth tracking" "aktif"

# ── Global command ────────────────────────────────────────────
{
mkdir -p /etc/zv-manager/servers
ln -sf /etc/zv-manager/menu/menu.sh /usr/local/bin/menu
chmod +x /usr/local/bin/menu
} >> "$_INSTALL_LOG" 2>&1
_ok "Command 'menu'" "siap digunakan"

# ── Restore: recreate SSH users + inject Xray + install bot ──
if [[ "$install_mode" == restore_* ]]; then
    echo ""
    echo -e "\033[33m  ──────────────────────────────────────\033[0m"
    echo -e "  \033[1mRestore Akun & Services\033[0m"
    echo -e "\033[33m  ──────────────────────────────────────\033[0m"
    echo ""

    # Recreate user Linux dari conf SSH
    local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null | tr -d '[:space:]')
    ssh_ok=0; ssh_skip=0
    for cf in /etc/zv-manager/accounts/ssh/*.conf; do
        [[ -f "$cf" ]] || continue
        _u=$(grep "^USERNAME=" "$cf" | cut -d= -f2 | tr -d '"[:space:]')
        _p=$(grep "^PASSWORD=" "$cf" | cut -d= -f2 | tr -d '"[:space:]')
        _srv=$(grep "^SERVER=" "$cf" | cut -d= -f2 | tr -d '"')
        # Cari IP server dari conf server
        _sip=""
        for sc in /etc/zv-manager/servers/*.conf; do
            _sname=$(grep "^NAME=" "$sc" 2>/dev/null | cut -d= -f2 | tr -d '"')
            if [[ "$_sname" == "$_srv" ]]; then
                _sip=$(grep "^IP=" "$sc" 2>/dev/null | cut -d= -f2 | tr -d '"')
                break
            fi
        done
        # Buat user hanya jika server ini lokal
        if [[ -z "$_sip" || "$_sip" == "$local_ip" ]]; then
            if [[ -n "$_u" && -n "$_p" ]]; then
                if ! id "$_u" &>/dev/null; then
                    useradd -M -s /bin/false "$_u" 2>/dev/null
                    echo "$_u:$_p" | chpasswd 2>/dev/null
                fi
                ssh_ok=$((ssh_ok+1))
            fi
        fi
    done >> "$_INSTALL_LOG" 2>&1
    _ok "Recreate SSH users" "${ssh_ok} akun"

    # Inject VMess UUID ke Xray + rebuild config
    vmess_ok=0
    for cf in /etc/zv-manager/accounts/vmess/*.conf; do
        [[ -f "$cf" ]] || continue
        _u=$(grep "^USERNAME=" "$cf" | cut -d= -f2 | tr -d '"[:space:]')
        _uuid=$(grep "^UUID=" "$cf" | cut -d= -f2 | tr -d '"[:space:]')
        _srv=$(grep "^SERVER=" "$cf" | cut -d= -f2 | tr -d '"')
        _sip=""
        for sc in /etc/zv-manager/servers/*.conf; do
            _sname=$(grep "^NAME=" "$sc" 2>/dev/null | cut -d= -f2 | tr -d '"')
            if [[ "$_sname" == "$_srv" ]]; then
                _sip=$(grep "^IP=" "$sc" 2>/dev/null | cut -d= -f2 | tr -d '"')
                break
            fi
        done
        if [[ -z "$_sip" || "$_sip" == "$local_ip" ]]; then
            if [[ -n "$_u" && -n "$_uuid" ]]; then
                /usr/local/bin/xray api rmu -s "127.0.0.1:10085" -inbound "vmess-ws"   -email "placeholder@vmess" &>/dev/null || true
                /usr/local/bin/xray api rmu -s "127.0.0.1:10085" -inbound "vmess-grpc" -email "placeholder@vmess" &>/dev/null || true
                /usr/local/bin/xray api adu -s "127.0.0.1:10085" -inbound "vmess-ws" \
                    -user "{\"vmess\":{\"id\":\"${_uuid}\",\"email\":\"${_u}@vmess\",\"alterId\":0}}" &>/dev/null || true
                /usr/local/bin/xray api adu -s "127.0.0.1:10085" -inbound "vmess-grpc" \
                    -user "{\"vmess\":{\"id\":\"${_uuid}\",\"email\":\"${_u}@vmess\",\"alterId\":0}}" &>/dev/null || true
                vmess_ok=$((vmess_ok+1))
            fi
        fi
    done >> "$_INSTALL_LOG" 2>&1
    # Rebuild config.json + restart Xray
    bash /usr/local/bin/zv-vmess-agent rebuild-config >> "$_INSTALL_LOG" 2>&1 || true
    systemctl restart zv-xray >> "$_INSTALL_LOG" 2>&1

        _ok "Recreate VMess clients" "${vmess_ok} akun"

    # Install bot dependencies + start bot
    {
        source /opt/zv-telegram/install.sh && install_telegram_bot
    } >> "$_INSTALL_LOG" 2>&1
    _ok "Telegram Bot" "aktif"

    # Delay: tunggu bot fully started sebelum kirim notif
    _step_inline "Menunggu bot ready" "siap" sleep 15

    # Notif Telegram ke admin
    {
        _tg_token=$(grep "^TG_TOKEN=" /etc/zv-manager/telegram.conf 2>/dev/null | cut -d= -f2 | tr -d '"\n')
        _tg_admin=$(grep "^TG_ADMIN=" /etc/zv-manager/telegram.conf 2>/dev/null | cut -d= -f2 | tr -d '"\n')
        _new_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null | tr -d '[:space:]')
        _restore_date=$(TZ="Asia/Jakarta" date +"%Y-%m-%d %H:%M WIB")
        if [[ -n "$_tg_token" && -n "$_tg_admin" ]]; then
            _msg="🔄 <b>Restore Otak Selesai</b>
━━━━━━━━━━━━━━━━━━━
✅ SSH      : ${ssh_ok} akun di-recreate
⚡ VMess    : ${vmess_ok} akun di-inject
🤖 Bot      : aktif
🌐 IP VPS   : ${_new_ip}
📅 Waktu    : ${_restore_date}
━━━━━━━━━━━━━━━━━━━
<i>VPS siap digunakan. Tambah server via Menu Server → Tambah Server.</i>"
            curl -s -X POST "https://api.telegram.org/bot${_tg_token}/sendMessage" \
                -d "chat_id=${_tg_admin}&parse_mode=HTML" \
                --data-urlencode "text=${_msg}" \
                --max-time 15 &>/dev/null || true
        fi
    } >> "$_INSTALL_LOG" 2>&1
    _ok "Notifikasi admin" "terkirim"
fi


INSTALL_HASH=$(git -C /root/ZV-Manager rev-parse --short HEAD 2>/dev/null || echo "unknown")
sed -i "s/^COMMIT_HASH=.*/COMMIT_HASH=\"${INSTALL_HASH}\"/" /etc/zv-manager/config.conf
mkdir -p /etc/zv-manager/accounts
echo "$PUBLIC_IP" > /etc/zv-manager/accounts/ipvps
_ok "Versi" "#${INSTALL_HASH}"

# ── Auto-launch menu saat login ───────────────────────────────
cat > /root/.profile <<'PROFILEEOF'
if [ "$BASH" ]; then
    if [ -f ~/.bashrc ]; then . ~/.bashrc; fi
fi
mesg n 2>/dev/null || true
case $- in *i*) ;; *) return ;; esac
[ -t 1 ] || return
[ -z "$SSH_TTY" ] && return
[ -n "$SSH_ORIGINAL_COMMAND" ] && return
menu
PROFILEEOF

# ── Selesai ───────────────────────────────────────────────────
ZV_IP="$PUBLIC_IP"
echo ""
printf "\033[1;32m"
echo "  ╔══════════════════════════════════════╗"
echo "  ║      INSTALASI SELESAI!              ║"
echo "  ╚══════════════════════════════════════╝"
printf "\033[0m\n"

echo -e "  \033[1mIP VPS    :\033[0m  \033[1;32m${ZV_IP}\033[0m"
echo ""
echo -e "  \033[1mPort yang aktif:\033[0m"
printf  "  \033[33m-\033[0m  %-14s  %s\n" "OpenSSH"  "22, 500, 40000"
printf  "  \033[33m-\033[0m  %-14s  %s\n" "Dropbear" "109, 143"
printf  "  \033[33m-\033[0m  %-14s  %s\n" "WS HTTP"  "80"
printf  "  \033[33m-\033[0m  %-14s  %s\n" "WS HTTPS" "443"
printf  "  \033[33m-\033[0m  %-14s  %s\n" "UDP"      "1-65535"
echo ""
echo -e "  \033[1mStatus Service:\033[0m"
for svc in ssh dropbear nginx zv-wss zv-udp; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        printf "  \033[32m+\033[0m  %s\n" "$svc"
    else
        printf "  \033[31m!\033[0m  %-20s  \033[31mtidak aktif\033[0m\n" "$svc"
    fi
done
echo ""

timer_end
echo ""
echo -e "  \033[33mReboot diperlukan agar semua service aktif.\033[0m"
echo ""
read -rp "  Reboot sekarang? [y/n]: " reboot_ans
if [[ "$reboot_ans" =~ ^[Yy]$ ]]; then
    echo "  Rebooting..."
    sleep 2
    reboot
fi
