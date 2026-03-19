#!/bin/bash
source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh

menu_system() {
    while true; do
        clear
        _section "SISTEM"
        echo ""
        echo -e "  $(_grad '[1]' 0 210 255 160 80 255) Clear Cache          $(_grad '[2]' 0 210 255 160 80 255) Auto Reboot"
        echo -e "  $(_grad '[3]' 0 210 255 160 80 255) Edit Banner          $(_grad '[4]' 0 210 255 160 80 255) Manajemen SSL"
        echo -e "  $(_grad '[5]' 0 210 255 160 80 255) Setup Telegram Bot   $(_grad '[6]' 0 210 255 160 80 255) Backup & Restore"
        echo -e "  $(_grad '[7]' 0 210 255 160 80 255) Halaman Web Status   $(_grad '[8]' 0 210 255 160 80 255) Uninstall"
        echo ""
        echo -e "  \e[38;2;255;80;80m[0]\e[0m Kembali"
        echo ""
        read -rp "  Pilihan [0-8]: " choice
        case $choice in
            1) bash /etc/zv-manager/menu/system/clear-cache.sh ;;
            2) bash /etc/zv-manager/menu/system/auto-reboot.sh ;;
            3) bash /etc/zv-manager/menu/system/edit-banner.sh ;;
            4) bash /etc/zv-manager/menu/system/setup-ssl.sh ;;
            5) bash /etc/zv-manager/menu/system/setup-telegram.sh ;;
            6) bash /etc/zv-manager/menu/system/backup.sh ;;
            7) bash /etc/zv-manager/menu/system/setup-web.sh ;;
            8)
                clear
                echo -e "${BRED}  ╔══════════════════════════════════════════════════╗${NC}"
                echo -e "${BRED}  ║   ⚠  PERINGATAN: UNINSTALL ZV-MANAGER           ║${NC}"
                echo -e "${BRED}  ╚══════════════════════════════════════════════════╝${NC}"
                echo ""
                echo -e "  Ini akan ${BRED}MENGHAPUS SEMUA${NC} komponen ZV-Manager!"
                echo -e "  Semua akun, setting, dan data akan terhapus permanen."
                echo ""
                read -rp "  Ketik 'HAPUS' untuk konfirmasi: " _conf1
                if [[ "$_conf1" != "HAPUS" ]]; then
                    echo -e "  ${BYELLOW}Dibatalkan.${NC}"; sleep 1
                else
                    bash /etc/zv-manager/uninstall.sh
                    exit 0
                fi
                ;;
            0) break ;;
            *) echo -e "  ${BRED}Pilihan tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}
menu_system
