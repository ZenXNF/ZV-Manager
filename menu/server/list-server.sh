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
    printf "  ${BWHITE}%-4s %-10s %-22s %-20s %-5s${NC}\n" "No." "Nama" "Domain" "IP" "Port"
    echo -e "  ${BCYAN}──────────────────────────────────────────────────────${NC}"

    for conf in "${SERVER_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue
        unset NAME IP DOMAIN PORT USER
        source "$conf"
        count=$((count + 1))
        # Kalau domain sama dengan IP (belum diisi), tampilkan "-"
        local disp_domain="${DOMAIN:-$IP}"
        printf "  ${BGREEN}%-4s${NC} %-10s %-22s %-20s %-5s\n" \
            "${count}." "$NAME" "$disp_domain" "$IP" "$PORT"
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
