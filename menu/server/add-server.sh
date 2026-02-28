#!/bin/bash
# ============================================================
#   ZV-Manager - Tambah Server
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh

SERVER_DIR="/etc/zv-manager/servers"
mkdir -p "$SERVER_DIR"

add_server() {
    clear
    echo -e "${BCYAN} ┌─────────────────────────────────────────────┐${NC}"
    echo -e " │           ${BWHITE}TAMBAH SERVER BARU${NC}                │"
    echo -e "${BCYAN} └─────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BYELLOW}Tip: Neva (VPS ini sendiri) juga bisa ditambahkan.${NC}"
    echo ""
    read -rp "  Nama server (contoh: neva, vps-sg)  : " name
    read -rp "  IP Address                           : " ip
    read -rp "  Domain (contoh: neva.zenxu.my.id)   : " domain
    read -rp "  Port SSH              [default: 22]  : " port
    read -rp "  Username              [default: root]: " user
    read -rsp "  Password                             : " pass
    echo ""
    echo ""

    [[ -z "$port" ]] && port=22
    [[ -z "$user" ]] && user=root
    [[ -z "$domain" ]] && domain="$ip"

    [[ -z "$name" || -z "$ip" || -z "$pass" ]] && {
        print_error "Nama, IP, dan password wajib diisi!"
        press_any_key
        return
    }

    if [[ -f "${SERVER_DIR}/${name}.conf" ]]; then
        print_error "Server '${name}' sudah ada!"
        press_any_key
        return
    fi

    # Kutip ADDED agar spasi di tanggal tidak dianggap command
    cat > "${SERVER_DIR}/${name}.conf" <<CONFEOF
NAME="${name}"
IP="${ip}"
DOMAIN="${domain}"
PORT="${port}"
USER="${user}"
PASS="${pass}"
ADDED="$(date +"%Y-%m-%d %H:%M")"
CONFEOF
    chmod 600 "${SERVER_DIR}/${name}.conf"

    echo ""
    print_ok "Server '${name}' berhasil ditambahkan!"
    echo -e "  ${BWHITE}IP     :${NC} ${BGREEN}${ip}${NC}"
    echo -e "  ${BWHITE}Domain :${NC} ${BGREEN}${domain}${NC}"
    echo -e "  ${BWHITE}Port   :${NC} ${BGREEN}${port}${NC}"
    press_any_key
}

add_server
