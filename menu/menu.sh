#!/bin/bash
# ============================================================
#   ZV-Manager - Main Menu
#   Versi: 1.0.0
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/config.conf

show_header() {
    local ip domain
    ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null || curl -s --max-time 5 ipv4.icanhazip.com)
    domain=$(cat /etc/zv-manager/domain 2>/dev/null)
    local today
    today=$(date +"%A, %d %B %Y — %H:%M")

    clear
    echo -e "${BCYAN}  ╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${BCYAN}  ║${NC}  ${BWHITE}ZV-Manager${NC} ${BYELLOW}v${SCRIPT_VERSION}${NC}                                ${BCYAN}║${NC}"
    echo -e "${BCYAN}  ╠══════════════════════════════════════════════════╣${NC}"
    echo -e "${BCYAN}  ║${NC}  ${BWHITE}IP     :${NC} ${BGREEN}${ip}${NC}"
    echo -e "${BCYAN}  ║${NC}  ${BWHITE}Domain :${NC} ${BGREEN}${domain}${NC}"
    echo -e "${BCYAN}  ║${NC}  ${BWHITE}Waktu  :${NC} ${BYELLOW}${today}${NC}"
    echo -e "${BCYAN}  ╚══════════════════════════════════════════════════╝${NC}"
    echo ""
}

main_menu() {
    while true; do
        show_header
        echo -e "  ${BWHITE}┌─────────────────────────────────────────┐${NC}"
        echo -e "  │          ${BWHITE}MENU UTAMA${NC}                      │"
        echo -e "  ${BWHITE}└─────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "  ${BGREEN}[1]${NC} Manajemen SSH"
        echo -e "  ${BGREEN}[2]${NC} Informasi Server"
        echo -e "  ${BGREEN}[3]${NC} System & Services"
        echo ""
        echo -e "  ${BYELLOW}[r]${NC} Restart Semua Service"
        echo -e "  ${BRED}[x]${NC} Keluar"
        echo ""
        read -rp "  Pilihan: " choice

        case $choice in
            1) bash /etc/zv-manager/menu/ssh/menu-ssh.sh ;;
            2) bash /etc/zv-manager/menu/info/server-info.sh ;;
            3) bash /etc/zv-manager/menu/system/menu-system.sh ;;
            r|R)
                for svc in ssh dropbear nginx zv-ws zv-wss zv-udp; do
                    systemctl restart "$svc" &>/dev/null
                done
                echo -e "  ${BGREEN}Semua service di-restart!${NC}"
                sleep 2
                ;;
            x|X|0) clear; exit 0 ;;
            *) echo -e "  ${BRED}Pilihan tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}

main_menu
