#!/bin/bash
source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/helpers.sh

menu_info() {
    while true; do
        clear
        _section "INFO & STATISTIK"
        echo ""
        echo -e "  $(_grad '[1]' 0 210 255 160 80 255) Info Server"
        echo -e "  $(_grad '[2]' 0 210 255 160 80 255) Statistik Penjualan"
        echo ""
        echo -e "  \e[38;2;255;80;80m[0]\e[0m Kembali"
        echo ""
        read -rp "  Pilihan [0-2]: " choice
        case $choice in
            1) bash /etc/zv-manager/menu/info/server-info.sh ;;
            2) bash /etc/zv-manager/menu/info/statistik.sh ;;
            0) break ;;
            *) echo -e "  ${BRED}Pilihan tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}
menu_info
