#!/bin/bash
# ============================================================
#   ZV-Manager - Menu Sistem
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh

menu_system() {
    while true; do
        clear
        echo -e "${BCYAN}  ┌──────────────────────────────────────────────┐${NC}"
        echo -e "  │               ${BWHITE}SISTEM${NC}                          │"
        echo -e "${BCYAN}  └──────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "  ${BGREEN}[1]${NC} Clear Cache          ${BGREEN}[2]${NC} Auto Reboot"
        echo -e "  ${BGREEN}[3]${NC} Edit Banner          ${BGREEN}[4]${NC} Manajemen SSL"
        echo -e "  ${BGREEN}[5]${NC} Setup Telegram Bot   ${BGREEN}[6]${NC} Backup & Restore"
        echo -e "  ${BGREEN}[7]${NC} Halaman Web Status   ${BGREEN}[8]${NC} Uninstall"
        echo ""
        echo -e "  ${BRED}[0]${NC} Kembali"
        echo ""
        read -rp "  Pilihan: " choice

        case $choice in
            1) bash /etc/zv-manager/menu/system/clear-cache.sh ;;
            2) bash /etc/zv-manager/menu/system/auto-reboot.sh ;;
            3) bash /etc/zv-manager/menu/system/edit-banner.sh ;;
            4) bash /etc/zv-manager/menu/system/setup-ssl.sh ;;
            5) bash /etc/zv-manager/menu/system/setup-telegram.sh ;;
            6) bash /etc/zv-manager/menu/system/backup.sh ;;
            7) bash /etc/zv-manager/menu/system/setup-web.sh ;;
            8)
                echo ""
                echo -e "  ${BRED}⚠  PERINGATAN: Ini akan menghapus semua komponen ZV-Manager!${NC}"
                echo ""
                bash /etc/zv-manager/uninstall.sh
                exit 0
                ;;
            0) break ;;
            *) echo -e "  ${BRED}Pilihan tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}

menu_system
