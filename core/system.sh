#!/bin/bash
# ============================================================
#   ZV-Manager - System Setup
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh

install_dependencies() {
    print_section "Menginstall Dependencies Sistem"

    export DEBIAN_FRONTEND=noninteractive

    print_info "Membersihkan package konflik..."
    apt-get remove --purge -y ufw firewalld exim4 apache2 bind9 sendmail &>/dev/null
    print_ok "Package konflik dihapus"

    print_info "Update package list..."
    apt-get update -y &>/dev/null
    print_ok "Package list diperbarui"

    print_info "Menginstall packages... (mohon tunggu)"
    apt-get install -y \
        curl wget git \
        openssl ca-certificates \
        python3 \
        cron at \
        iptables \
        fail2ban \
        vnstat \
        chrony \
        nginx \
        dropbear \
        openssh-server \
        sshpass &>/dev/null
    print_ok "Packages selesai diinstall"

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
    print_section "Aktifkan BBR"

    if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q "bbr"; then
        print_info "BBR sudah aktif, skip..."
        return
    fi

    modprobe tcp_bbr 2>/dev/null
    echo "tcp_bbr" >> /etc/modules-load.d/modules.conf

    cat >> /etc/sysctl.conf <<SYSCTL

# ZV-Manager - BBR & Network Optimization
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_forward = 1
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
SYSCTL

    sysctl -p &>/dev/null
    print_success "BBR"
}

block_torrent() {
    print_section "Blokir Torrent"

    # Cek apakah rule sudah ada untuk menghindari duplikat saat update
    if iptables -C FORWARD -m string --string "BitTorrent" --algo bm -j DROP 2>/dev/null; then
        print_info "Rule torrent sudah ada, skip..."
        print_success "Blokir Torrent"
        return
    fi

    # FIX: hapus --algo bm duplikat yang menyebabkan error di Ubuntu 24.04
    iptables -A FORWARD -m string --string "get_peers"          --algo bm -j DROP
    iptables -A FORWARD -m string --string "announce_peer"      --algo bm -j DROP
    iptables -A FORWARD -m string --string "find_node"          --algo bm -j DROP
    iptables -A FORWARD -m string --string "BitTorrent"         --algo bm -j DROP
    iptables -A FORWARD -m string --string "BitTorrent protocol" --algo bm -j DROP
    iptables -A FORWARD -m string --string "peer_id="           --algo bm -j DROP
    iptables -A FORWARD -m string --string ".torrent"           --algo bm -j DROP
    iptables -A FORWARD -m string --string "info_hash"          --algo bm -j DROP

    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true

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
    block_torrent
}
