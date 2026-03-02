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

    # --- issue.net ---
    # HTTP Custom hanya support tag HTML terbatas: <font color>, <br>, <div>
    # CSS style= tidak diparse → pakai atribut HTML4: <div align="center">
    # Semua dalam satu baris per div, tidak ada newline antar tag
    grep -q "^Banner" "$sshd_config" || echo "Banner /etc/issue.net" >> "$sshd_config"
    cat > /etc/issue.net <<'BANNEREOF'
<div align="center"><font color="#00ffff">▬▬▬ஜ۩۞۩ஜ▬▬▬</font></div><div align="center"><font color="#ffff00">⚡ ZV-Manager SSH Tunnel ⚡</font></div><div align="center"><font color="#00ffff">▬▬▬ஜ۩۞۩ஜ▬▬▬</font></div><div align="center"><font color="#ffffff">! SYARAT PENGGUNAAN !</font></div><div align="center"><font color="#ff4444">✗ DILARANG SPAM</font></div><div align="center"><font color="#ff4444">✗ DILARANG DDoS</font></div><div align="center"><font color="#ff4444">✗ DILARANG HACK / CARDING</font></div><div align="center"><font color="#ff4444">✗ DILARANG TORRENT</font></div><div align="center"><font color="#ff4444">✗ DILARANG BERBAGI AKUN</font></div><div align="center"><font color="#00ff00">✔ Melanggar = Ban Permanen</font></div><div align="center"><font color="#00ffff">▬▬▬ஜ۩۞۩ஜ▬▬▬</font></div>
BANNEREOF

    # --- MOTD berwarna — tampil di Termius setelah login ---
    # Ubuntu 24.04: PrintMotd no → PAM yang handle via pam_motd.so
    sed -i 's/^#\?PrintMotd.*/PrintMotd no/' "$sshd_config"
    grep -q "^PrintMotd" "$sshd_config" || echo "PrintMotd no" >> "$sshd_config"

    chmod -x /etc/update-motd.d/* 2>/dev/null

    cat > /etc/update-motd.d/00-zv-manager <<'MOTDEOF'
#!/bin/bash
R='\033[0;31m'
G='\033[0;32m'
Y='\033[0;33m'
C='\033[0;36m'
W='\033[1;37m'
NC='\033[0m'

USER_CONF="/etc/zv-manager/accounts/ssh/${PAM_USER}.conf"
EXPIRED=""
LIMIT=""
if [[ -f "$USER_CONF" ]]; then
    EXPIRED=$(grep "^EXPIRED=" "$USER_CONF" | cut -d= -f2)
    LIMIT=$(grep "^LIMIT=" "$USER_CONF" | cut -d= -f2)
fi

DOMAIN=$(cat /etc/zv-manager/domain 2>/dev/null)
NOW=$(date +"%d %b %Y %H:%M")

echo ""
echo -e "${C}  =================================${NC}"
echo -e "  ${W}ZV-Manager SSH Tunnel${NC}"
echo -e "${C}  =================================${NC}"
echo -e "  ${Y}User   :${NC} ${W}${PAM_USER}${NC}"
echo -e "  ${Y}Server :${NC} ${G}${DOMAIN}${NC}"
echo -e "  ${Y}Waktu  :${NC} ${NOW}"
[[ -n "$EXPIRED" ]] && echo -e "  ${Y}Expired:${NC} ${R}${EXPIRED}${NC}"
[[ -n "$LIMIT"   ]] && echo -e "  ${Y}Limit  :${NC} ${LIMIT} perangkat"
echo -e "${C}  =================================${NC}"
echo -e "  ${R}✗ Spam  ✗ DDoS  ✗ Torrent${NC}"
echo -e "${C}  =================================${NC}"
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
