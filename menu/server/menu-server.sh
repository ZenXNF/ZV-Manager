#!/bin/bash
# ============================================================
#   ZV-Manager - Server Management Menu
# ============================================================

source /etc/zv-manager/utils/colors.sh

menu_server() {
    while true; do
        clear
        echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
        echo -e " │          ${BWHITE}MENU MANAJEMEN SERVER${NC}               │"
        echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "  ${BGREEN}[1]${NC} Tambah Server"
        echo -e "  ${BGREEN}[2]${NC} List Server"
        echo -e "  ${BGREEN}[3]${NC} Connect ke Server"
        echo -e "  ${BGREEN}[4]${NC} Hapus Server"
        echo ""
        echo -e "  ${BRED}[0]${NC} Kembali ke Menu Utama"
        echo ""
        read -rp "  Pilihan: " choice

        case $choice in
            1) bash /etc/zv-manager/menu/server/add-server.sh ;;
            2) bash /etc/zv-manager/menu/server/list-server.sh ;;
            3) bash /etc/zv-manager/menu/server/connect-server.sh ;;
            4) bash /etc/zv-manager/menu/server/del-server.sh ;;
            0) break ;;
            *) echo -e "  ${BRED}Pilihan tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}

menu_server
