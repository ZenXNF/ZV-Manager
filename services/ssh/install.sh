#!/bin/bash
# ============================================================
#   ZV-Manager - SSH Service Installer
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/config.conf

install_ssh() {
    print_section "Konfigurasi OpenSSH"

    apt-get install -y openssh-server &>/dev/null

    local sshd_config="/etc/ssh/sshd_config"

    cp "$sshd_config" "${sshd_config}.bak.$(date +%F)" 2>/dev/null

    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' "$sshd_config"
    sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' "$sshd_config"
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' "$sshd_config"
    sed -i 's/^#\?AcceptEnv.*/#AcceptEnv/' "$sshd_config"

    sed -i '/^Port /d' "$sshd_config"

    {
        echo "Port ${SSH_PORT}"
        echo "Port ${SSH_PORT_2}"
        echo "Port ${SSH_PORT_3}"
        cat "$sshd_config"
    } > "${sshd_config}.tmp"
    mv "${sshd_config}.tmp" "$sshd_config"

    # issue.net — plain text, muncul sebelum login
    grep -q "^Banner" "$sshd_config" || echo "Banner /etc/issue.net" >> "$sshd_config"
    cat > /etc/issue.net <<'BANNEREOF'
╔══════════════════════════════════════════════════╗
║           --- WELCOME TO ZV-MANAGER ---          ║
╚══════════════════════════════════════════════════╝
BANNEREOF

    # --- MOTD berwarna — muncul SETELAH login berhasil ---
    # Ubuntu 24.04: PrintMotd no → biarkan PAM yang handle via pam_motd.so
    # PrintMotd yes konflik dengan PAM di Ubuntu 24.04 dan bisa sebabkan connection reset
    sed -i 's/^#\?PrintMotd.*/PrintMotd no/' "$sshd_config"
    grep -q "^PrintMotd" "$sshd_config" || echo "PrintMotd no" >> "$sshd_config"

    # Nonaktifkan MOTD default Ubuntu yang berisik
    chmod -x /etc/update-motd.d/* 2>/dev/null

    # Buat script MOTD custom
    cat > /etc/update-motd.d/00-zv-manager <<'MOTDEOF'
#!/bin/bash
# ZV-Manager MOTD — ditampilkan setelah SSH login berhasil

# Warna
R='\033[0;31m'   # Merah
G='\033[0;32m'   # Hijau
Y='\033[0;33m'   # Kuning
B='\033[0;34m'   # Biru
C='\033[0;36m'   # Cyan
W='\033[1;37m'   # Putih terang
M='\033[0;35m'   # Magenta
NC='\033[0m'     # Reset

# Ambil info akun yang sedang login
USER_CONF="/etc/zv-manager/accounts/ssh/${PAM_USER}.conf"
EXPIRED=""
LIMIT=""
if [[ -f "$USER_CONF" ]]; then
    EXPIRED=$(grep "^EXPIRED=" "$USER_CONF" | cut -d= -f2)
    LIMIT=$(grep "^LIMIT=" "$USER_CONF" | cut -d= -f2)
fi

DOMAIN=$(cat /etc/zv-manager/domain 2>/dev/null)
NOW=$(date +"%d %B %Y — %H:%M")

echo ""
printf "${C}  ╔══════════════════════════════════════════════════╗${NC}\n"
printf "${C}  ║${NC}  ${W}⚡ ZV-MANAGER SSH TUNNEL ⚡${NC}                      ${C}║${NC}\n"
printf "${C}  ╠══════════════════════════════════════════════════╣${NC}\n"
printf "${C}  ║${NC}  ${Y}Selamat datang, ${W}${PAM_USER}${NC}!\n"
printf "${C}  ║${NC}  ${B}Server  ${NC}: ${G}${DOMAIN}${NC}\n"
printf "${C}  ║${NC}  ${B}Waktu   ${NC}: ${Y}${NOW}${NC}\n"
if [[ -n "$EXPIRED" ]]; then
printf "${C}  ║${NC}  ${B}Expired ${NC}: ${R}${EXPIRED}${NC}\n"
fi
if [[ -n "$LIMIT" ]]; then
printf "${C}  ║${NC}  ${B}Limit   ${NC}: ${W}${LIMIT} perangkat${NC}\n"
fi
printf "${C}  ╠══════════════════════════════════════════════════╣${NC}\n"
printf "${C}  ║${NC}  ${W}⚠  SYARAT DAN KETENTUAN PENGGUNAAN${NC}\n"
printf "${C}  ║${NC}\n"
printf "${C}  ║${NC}  ${R}✗${NC}  Dilarang melakukan SPAM\n"
printf "${C}  ║${NC}  ${R}✗${NC}  Dilarang melakukan serangan DDoS\n"
printf "${C}  ║${NC}  ${R}✗${NC}  Dilarang hacking, carding, atau penipuan\n"
printf "${C}  ║${NC}  ${R}✗${NC}  Dilarang mengunduh atau menyebarkan Torrent\n"
printf "${C}  ║${NC}  ${R}✗${NC}  Dilarang berbagi akun (1 akun = 1 pengguna)\n"
printf "${C}  ║${NC}  ${R}✗${NC}  Dilarang menggunakan untuk aktivitas ilegal\n"
printf "${C}  ║${NC}\n"
printf "${C}  ║${NC}  ${G}✔${NC}  Pelanggaran = akun diblokir permanen\n"
printf "${C}  ╚══════════════════════════════════════════════════╝${NC}\n"
echo ""
MOTDEOF

    chmod +x /etc/update-motd.d/00-zv-manager

    grep -qx '/bin/false' /etc/shells || echo '/bin/false' >> /etc/shells
    grep -qx '/usr/sbin/nologin' /etc/shells || echo '/usr/sbin/nologin' >> /etc/shells

    mkdir -p /etc/zv-manager/accounts/ssh

    systemctl enable ssh &>/dev/null
    systemctl restart ssh &>/dev/null

    print_success "OpenSSH (Port: ${SSH_PORT}, ${SSH_PORT_2}, ${SSH_PORT_3})"
}
