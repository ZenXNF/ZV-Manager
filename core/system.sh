#!/bin/bash
# ============================================================
#   ZV-Manager - System Setup
#   Update OS, install dependencies dasar, optimasi kernel
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh

install_dependencies() {
    print_section "Menginstall Dependencies Sistem"

    # Hapus package yang tidak perlu / konflik
    print_info "Membersihkan package konflik..."
    apt-get remove --purge -y ufw firewalld exim4 apache2 bind9 sendmail &>/dev/null
    print_ok "Package konflik dihapus"

    # Update sistem
    print_info "Update package list... (mohon tunggu)"
    apt-get update -y &>/dev/null
    print_ok "Package list diperbarui"

    print_info "Upgrade sistem... (mohon tunggu)"
    apt-get upgrade -y &>/dev/null
    print_ok "Sistem diupgrade"

    # [1] Tools dasar — curl/wget/git/sed dipakai di banyak script
    print_info "[1/4] Menginstall tools dasar..."
    apt-get install -y \
        curl wget git \
        openssl ca-certificates \
        sed iptables iptables-persistent netfilter-persistent \
        python3 cron &>/dev/null
    print_ok "[1/4] Tools dasar selesai"

    # [2] Build tools — hanya untuk compile badvpn (fallback UDP)
    print_info "[2/4] Menginstall build tools... (untuk UDP/BadVPN)"
    apt-get install -y build-essential gcc cmake make &>/dev/null
    print_ok "[2/4] Build tools selesai"

    # [3] Monitoring & keamanan
    print_info "[3/4] Menginstall monitoring & keamanan..."
    apt-get install -y fail2ban vnstat &>/dev/null
    print_ok "[3/4] Monitoring & keamanan selesai"

    # [4] Sinkronisasi waktu
    print_info "[4/4] Menginstall sinkronisasi waktu..."
    apt-get install -y chrony &>/dev/null
    print_ok "[4/4] Sinkronisasi waktu selesai"

    print_success "Dependencies"
}

setup_swap() {
    print_section "Setup Swap RAM"

    if swapon --show | grep -q "/swapfile"; then
        print_info "Swap sudah ada, skip..."
        return
    fi

    print_info "Membuat swap 1GB..."
    dd if=/dev/zero of=/swapfile bs=1024 count=1048576 &>/dev/null
    chmod 600 /swapfile
    mkswap /swapfile &>/dev/null
    swapon /swapfile &>/dev/null

    # Tambahkan ke fstab supaya persistent
    if ! grep -q "/swapfile" /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi

    print_success "Swap 1GB"
}

setup_timezone() {
    print_section "Setup Timezone"
    local tz="${TIMEZONE:-Asia/Jakarta}"
    timedatectl set-timezone "$tz" &>/dev/null
    print_ok "Timezone diset ke: $tz"
}

sync_time() {
    print_info "Sinkronisasi waktu..."
    systemctl enable chrony &>/dev/null
    systemctl restart chrony &>/dev/null
    chronyc makestep &>/dev/null
    print_ok "Waktu tersinkronisasi"
}

setup_bbr() {
    print_section "Aktifkan BBR (TCP Congestion Control)"

    # Cek apakah BBR sudah aktif
    if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q "bbr"; then
        print_info "BBR sudah aktif, skip..."
        return
    fi

    # Aktifkan BBR
    modprobe tcp_bbr 2>/dev/null
    echo "tcp_bbr" >> /etc/modules-load.d/modules.conf

    cat >> /etc/sysctl.conf <<EOF

# ZV-Manager - BBR & Network Optimization
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_forward = 1
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF

    sysctl -p &>/dev/null
    print_success "BBR"
}

setup_rc_local() {
    print_section "Setup rc.local"

    cat > /etc/systemd/system/rc-local.service <<EOF
[Unit]
Description=/etc/rc.local
ConditionPathExists=/etc/rc.local

[Service]
Type=forking
ExecStart=/etc/rc.local start
TimeoutSec=0
StandardOutput=tty
RemainAfterExit=yes
SysVStartPriority=99

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/rc.local <<EOF
#!/bin/sh -e
# ZV-Manager rc.local
exit 0
EOF

    chmod +x /etc/rc.local
    systemctl enable rc-local &>/dev/null
    systemctl start rc-local &>/dev/null
    print_success "rc.local"
}

block_torrent() {
    print_section "Blokir Torrent (iptables)"

    iptables -A FORWARD -m string --string "get_peers" --algo bm -j DROP
    iptables -A FORWARD -m string --string "announce_peer" --algo bm -j DROP
    iptables -A FORWARD -m string --string "find_node" --algo bm -j DROP
    iptables -A FORWARD -m string --algo bm --string "BitTorrent" -j DROP
    iptables -A FORWARD -m string --algo bm --string "BitTorrent protocol" -j DROP
    iptables -A FORWARD -m string --algo bm --string "peer_id=" -j DROP
    iptables -A FORWARD -m string --algo bm --string ".torrent" -j DROP
    iptables -A FORWARD -m string --algo bm --string "info_hash" -j DROP

    netfilter-persistent save &>/dev/null
    print_success "Blokir Torrent"
}

setup_log_dir() {
    mkdir -p /var/log/zv-manager
    touch /var/log/zv-manager/install.log
}

run_system_setup() {
    setup_log_dir
    install_dependencies
    setup_swap
    setup_timezone
    sync_time
    setup_bbr
    setup_rc_local
    block_torrent
}
