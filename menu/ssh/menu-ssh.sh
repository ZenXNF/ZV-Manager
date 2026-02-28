#!/bin/bash
# ============================================================
#   ZV-Manager - SSH Sub-Menu
# ============================================================

source /etc/zv-manager/utils/colors.sh

menu_ssh() {
    while true; do
        clear
        echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
        echo -e " │            ${BWHITE}MENU MANAJEMEN SSH${NC}                │"
        echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "  ${BGREEN}[1]${NC} Tambah Akun SSH"
        echo -e "  ${BGREEN}[2]${NC} Hapus Akun SSH"
        echo -e "  ${BGREEN}[3]${NC} List Akun SSH"
        echo -e "  ${BGREEN}[4]${NC} Perpanjang Akun SSH"
        echo -e "  ${BGREEN}[5]${NC} Lock Akun SSH"
        echo -e "  ${BGREEN}[6]${NC} Unlock Akun SSH"
        echo ""
        echo -e "  ${BRED}[0]${NC} Kembali ke Menu Utama"
        echo ""
        read -rp "  Pilihan: " choice

        case $choice in
            1) bash /etc/zv-manager/menu/ssh/add-user.sh ;;
            2) bash /etc/zv-manager/menu/ssh/del-user.sh ;;
            3) bash /etc/zv-manager/menu/ssh/list-user.sh ;;
            4) bash /etc/zv-manager/menu/ssh/renew-user.sh ;;
            5) bash /etc/zv-manager/menu/ssh/lock-user.sh ;;
            6) bash /etc/zv-manager/menu/ssh/unlock-user.sh ;;
            0) break ;;
            *) echo -e "  ${BRED}Pilihan tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}

menu_ssh
