#!/bin/bash
# ============================================================
#   ZV-Manager - List Server
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/helpers.sh

SERVER_DIR="/etc/zv-manager/servers"

list_servers() {
    clear
    echo -e "${BCYAN} ┌──────────────────────────────────────────────────────┐${NC}"
    echo -e " │                ${BWHITE}DAFTAR SERVER${NC}                        │"
    echo -e "${BCYAN} └──────────────────────────────────────────────────────┘${NC}"
    echo ""

    local count=0
    printf "  ${BWHITE}%-4s %-15s %-20s %-6s %-10s${NC}\n" "No." "Nama" "IP" "Port" "User"
    echo -e "  ${BCYAN}──────────────────────────────────────────────────────${NC}"

    for conf in "${SERVER_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue
        source "$conf"
        count=$((count + 1))
        printf "  ${BGREEN}%-4s${NC} %-15s %-20s %-6s %-10s\n" \
            "${count}." "$NAME" "$IP" "$PORT" "$USER"
    done

    if [[ $count -eq 0 ]]; then
        echo -e "  ${BYELLOW}Belum ada server yang ditambahkan.${NC}"
        echo -e "  ${BYELLOW}Pilih 'Tambah Server' untuk menambahkan.${NC}"
    fi

    echo ""
    echo -e "  ${BYELLOW}Total: ${count} server${NC}"
    echo ""
    press_any_key
}

list_servers
