#!/bin/bash
# ============================================================
#   ZV-Manager - Menu Info & Statistik
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/helpers.sh

menu_info() {
    while true; do
        clear
        echo -e "${BCYAN}  ┌──────────────────────────────────────────────┐${NC}"
        echo -e "  │           ${BWHITE}INFO & STATISTIK${NC}                  │"
        echo -e "${BCYAN}  └──────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "  ${BGREEN}[1]${NC} Info Server"
        echo -e "  ${BGREEN}[2]${NC} Statistik Penjualan"
        echo ""
        echo -e "  ${BRED}[0]${NC} Kembali"
        echo ""
        read -rp "  Pilihan: " choice

        case $choice in
            1) bash /etc/zv-manager/menu/info/server-info.sh ;;
            2) bash /etc/zv-manager/menu/info/statistik.sh ;;
            0) break ;;
            *) echo -e "  ${BRED}Pilihan tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}

menu_info
