#!/bin/bash
# ============================================================
#   ZV-Manager - Tambah Server
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/helpers.sh

SERVER_DIR="/etc/zv-manager/servers"
mkdir -p "$SERVER_DIR"

add_server() {
    clear
    echo -e "${BCYAN} ┌─────────────────────────────────────────────┐${NC}"
    echo -e " │           ${BWHITE}TAMBAH SERVER BARU${NC}                │"
    echo -e "${BCYAN} └─────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BYELLOW}Tip: Neva (server ini sendiri) juga bisa ditambahkan.${NC}"
    echo ""
    read -rp "  Nama server (contoh: neva, vps-sg): " name
    read -rp "  IP Address                        : " ip
    read -rp "  Port SSH             [default: 22]: " port
    read -rp "  Username             [default: root]: " user
    read -rsp "  Password                           : " pass
    echo ""
    echo ""

    # Default values
    [[ -z "$port" ]] && port=22
    [[ -z "$user" ]] && user=root
    [[ -z "$name" || -z "$ip" || -z "$pass" ]] && {
        print_error "Nama, IP, dan password wajib diisi!"
        press_any_key
        return
    }

    # Cek nama duplikat
    if [[ -f "${SERVER_DIR}/${name}.conf" ]]; then
        print_error "Server '${name}' sudah ada!"
        press_any_key
        return
    fi

    # Simpan dengan permission ketat
    cat > "${SERVER_DIR}/${name}.conf" <<EOF
NAME=${name}
IP=${ip}
PORT=${port}
USER=${user}
PASS=${pass}
ADDED=$(date +"%Y-%m-%d %H:%M")
EOF
    chmod 600 "${SERVER_DIR}/${name}.conf"

    echo ""
    print_ok "Server '${name}' (${ip}:${port}) berhasil ditambahkan!"
    press_any_key
}

add_server
