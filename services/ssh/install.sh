#!/bin/bash
# ============================================================
#   ZV-Manager - SSH Service Installer
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/config.conf

install_ssh() {
    print_section "Konfigurasi OpenSSH"

    # Pastikan openssh-server terinstall
    apt-get install -y openssh-server &>/dev/null

    local sshd_config="/etc/ssh/sshd_config"

    # Backup config asli
    cp "$sshd_config" "${sshd_config}.bak.$(date +%F)" 2>/dev/null

    # Terapkan konfigurasi
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' "$sshd_config"
    sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' "$sshd_config"
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' "$sshd_config"
    sed -i 's/^#\?AcceptEnv.*/#AcceptEnv/' "$sshd_config"

    # Hapus port lama dan set ulang
    sed -i '/^Port /d' "$sshd_config"

    # Tambahkan port di awal file
    {
        echo "Port ${SSH_PORT}"
        echo "Port ${SSH_PORT_2}"
        echo "Port ${SSH_PORT_3}"
        cat "$sshd_config"
    } > "${sshd_config}.tmp"
    mv "${sshd_config}.tmp" "$sshd_config"

    # Tambahkan banner
    # Cek apakah Banner sudah ada di config
    grep -q "^Banner" "$sshd_config" || echo "Banner /etc/issue.net" >> "$sshd_config"

    # Isi banner — plain text tanpa ANSI
    # SSH protocol tidak render warna di banner, ditampilkan as-is
    cat > /etc/issue.net <<'BANNEREOF'
╔══════════════════════════════════════════════════╗
║        --- WELCOME TO ZV-MANAGER ---             ║
╚══════════════════════════════════════════════════╝

        ! TERM OF SERVICE !
        NO SPAM
        NO DDOS
        NO HACKING & CARDING
        NO TORRENT !!
        NO MULTI LOGIN !!

══════════════════════════════════════════════════
BANNEREOF

    # Setup /etc/shells
    grep -qx '/bin/false' /etc/shells || echo '/bin/false' >> /etc/shells
    grep -qx '/usr/sbin/nologin' /etc/shells || echo '/usr/sbin/nologin' >> /etc/shells

    # Buat direktori untuk data akun
    mkdir -p /etc/zv-manager/accounts/ssh

    # Restart SSH
    systemctl enable ssh &>/dev/null
    systemctl restart ssh &>/dev/null

    print_success "OpenSSH (Port: ${SSH_PORT}, ${SSH_PORT_2}, ${SSH_PORT_3})"
}
