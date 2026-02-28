#!/bin/bash
# ============================================================
#   ZV-Manager - System Checker
# ============================================================

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        echo -e "\033[1;31m[ERROR]\033[0m Script harus dijalankan sebagai root!"
        exit 1
    fi
}

check_os() {
    local os_id
    os_id=$(grep -w "^ID" /etc/os-release | cut -d= -f2 | tr -d '"')
    local os_version
    os_version=$(grep -w "^VERSION_ID" /etc/os-release | cut -d= -f2 | tr -d '"')

    if [[ "$os_id" == "ubuntu" ]]; then
        print_ok "OS: Ubuntu $os_version — Didukung"
    elif [[ "$os_id" == "debian" ]]; then
        print_ok "OS: Debian $os_version — Didukung"
    else
        print_error "OS tidak didukung: $os_id"
        exit 1
    fi
}

check_arch() {
    local arch
    arch=$(uname -m)
    if [[ "$arch" == "x86_64" ]]; then
        print_ok "Arsitektur: $arch — Didukung"
    else
        print_error "Arsitektur tidak didukung: $arch"
        exit 1
    fi
}

check_virt() {
    local virt
    virt=$(systemd-detect-virt 2>/dev/null)
    if [[ "$virt" == "openvz" ]]; then
        print_error "OpenVZ tidak didukung"
        exit 1
    fi
    print_ok "Virtualisasi: $virt"
}

check_internet() {
    if ! curl -s --max-time 5 icanhazip.com &>/dev/null; then
        print_error "Tidak ada koneksi internet!"
        exit 1
    fi
    print_ok "Koneksi internet: OK"
}

get_public_ip() {
    PUBLIC_IP=$(curl -s --max-time 10 ipv4.icanhazip.com)
    if [[ -z "$PUBLIC_IP" ]]; then
        print_error "Gagal mendapatkan IP publik"
        exit 1
    fi
    print_ok "IP Publik: $PUBLIC_IP"
}

get_network_interface() {
    NET_IFACE=$(ip -4 route show default | awk '{print $5}' | head -1)
    if [[ -z "$NET_IFACE" ]]; then
        print_error "Gagal mendeteksi network interface"
        exit 1
    fi
    print_ok "Network Interface: $NET_IFACE"
}

run_all_checks() {
    check_root
    check_os
    check_arch
    check_virt
    check_internet
    get_public_ip
    get_network_interface
}
