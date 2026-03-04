#!/bin/bash
# ============================================================
#   ZV-Manager - Menu Server
# ============================================================

source /etc/zv-manager/utils/colors.sh

menu_server() {
    while true; do
        clear
        echo -e "${BCYAN}  ┌──────────────────────────────────────────────┐${NC}"
        echo -e "  │           ${BWHITE}MANAJEMEN SERVER${NC}                  │"
        echo -e "${BCYAN}  └──────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "  ${BGREEN}[1]${NC} Tambah Server        ${BGREEN}[2]${NC} List Server"
        echo -e "  ${BGREEN}[3]${NC} Connect ke Server    ${BGREEN}[4]${NC} Hapus Server"
        echo -e "  ${BGREEN}[5]${NC} Deploy Agent         ${BGREEN}[6]${NC} Setting Telegram"
        echo ""
        echo -e "  ${BRED}[0]${NC} Kembali"
        echo ""
        read -rp "  Pilihan: " choice

        case $choice in
            1) bash /etc/zv-manager/menu/server/add-server.sh ;;
            2) bash /etc/zv-manager/menu/server/list-server.sh ;;
            3) bash /etc/zv-manager/menu/server/connect-server.sh ;;
            4) bash /etc/zv-manager/menu/server/del-server.sh ;;
            5) bash /etc/zv-manager/menu/server/deploy-agent.sh ;;
            6) bash /etc/zv-manager/menu/server/tg-server-setting.sh ;;
            0) break ;;
            *) echo -e "  ${BRED}Pilihan tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}

menu_server
