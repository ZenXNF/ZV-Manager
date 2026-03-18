#!/bin/bash
source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/helpers.sh

menu_server() {
    while true; do
        clear
        _section "MANAJEMEN SERVER"
        echo ""
        echo -e "  $(_grad '[1]' 0 210 255 160 80 255) Tambah Server        $(_grad '[2]' 0 210 255 160 80 255) List Server"
        echo -e "  $(_grad '[3]' 0 210 255 160 80 255) Connect ke Server    $(_grad '[4]' 0 210 255 160 80 255) Hapus Server"
        echo -e "  $(_grad '[5]' 0 210 255 160 80 255) Deploy Agent         $(_grad '[6]' 0 210 255 160 80 255) Setting Telegram"
        echo -e "  $(_grad '[7]' 0 210 255 160 80 255) Auto Reboot Worker"
        echo ""
        echo -e "  \e[38;2;255;80;80m[0/7]\e[0m Kembali"
        echo ""
        read -rp "  Pilihan [0-7]: " choice
        case $choice in
            1) bash /etc/zv-manager/menu/server/add-server.sh ;;
            2) bash /etc/zv-manager/menu/server/list-server.sh ;;
            3) bash /etc/zv-manager/menu/server/connect-server.sh ;;
            4) bash /etc/zv-manager/menu/server/del-server.sh ;;
            5) bash /etc/zv-manager/menu/server/deploy-agent.sh ;;
            6) bash /etc/zv-manager/menu/server/tg-server-setting.sh ;;
            7) bash /etc/zv-manager/menu/server/worker-reboot.sh ;;
            0) break ;;
            *) echo -e "  ${BRED}Pilihan tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}
menu_server
