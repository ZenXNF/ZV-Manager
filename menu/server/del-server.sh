#!/bin/bash
# ============================================================
#   ZV-Manager - Hapus Server
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh

SERVER_DIR="/etc/zv-manager/servers"

del_server() {
    clear
    echo -e "${BCYAN} ┌─────────────────────────────────────────────┐${NC}"
    echo -e " │             ${BWHITE}HAPUS SERVER${NC}                      │"
    echo -e "${BCYAN} └─────────────────────────────────────────────┘${NC}"
    echo ""

    local count=0
    for conf in "${SERVER_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue
        unset NAME IP DOMAIN PORT
        source "$conf"
        count=$((count + 1))
        echo -e "  ${BGREEN}[${count}]${NC} ${NAME} — ${IP}:${PORT}"
    done

    if [[ $count -eq 0 ]]; then
        print_error "Belum ada server yang ditambahkan!"
        press_any_key
        return
    fi

    echo ""
    read -rp "  Nama server yang akan dihapus: " name

    if [[ ! -f "${SERVER_DIR}/${name}.conf" ]]; then
        print_error "Server '${name}' tidak ditemukan!"
        press_any_key
        return
    fi

    if confirm "Yakin hapus server '${name}'?"; then
        rm -f "${SERVER_DIR}/${name}.conf"
        print_ok "Server '${name}' berhasil dihapus"
    else
        print_info "Dibatalkan"
    fi

    press_any_key
}

del_server
