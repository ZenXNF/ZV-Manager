#!/bin/bash
# ============================================================
#   ZV-Manager - List SSH Users
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh

list_ssh_users() {
    clear
    local today
    today=$(date +"%Y-%m-%d")

    echo -e "${BCYAN} ┌──────────────────────────────────────────────────────────┐${NC}"
    echo -e " │                  ${BWHITE}DAFTAR AKUN SSH AKTIF${NC}                  │"
    echo -e "${BCYAN} └──────────────────────────────────────────────────────────┘${NC}"
    echo ""
    printf "  ${BWHITE}%-18s %-14s %-10s %-10s${NC}\n" "Username" "Expired" "Status" "Online"
    echo -e "  ${BCYAN}──────────────────────────────────────────────────────${NC}"

    local count=0
    for conf_file in /etc/zv-manager/accounts/ssh/*.conf; do
        [[ -f "$conf_file" ]] || continue
        source "$conf_file"

        # Cek status expired
        local status
        if [[ "$EXPIRED" < "$today" ]]; then
            status="${BRED}Expired${NC}"
        else
            status="${BGREEN}Aktif${NC}"
        fi

        # Cek jumlah login aktif
        local online
        online=$(who | grep -c "^$USERNAME" 2>/dev/null || echo 0)

        printf "  %-18s %-14s " "$USERNAME" "$EXPIRED"
        echo -e "$status    ${BCYAN}${online}x${NC}"

        count=$((count + 1))
    done

    echo ""
    echo -e "  ${BYELLOW}Total akun: ${count}${NC}"
    echo ""

    read -n 1 -s -r -p "  Tekan tombol apapun untuk kembali..."
    echo ""
}

list_ssh_users
