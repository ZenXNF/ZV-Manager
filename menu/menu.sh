#!/bin/bash
# ============================================================
#   ZV-Manager - Main Menu
#   Versi: 1.0.0
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/config.conf

# Status satu service: ● hijau kalau aktif, ● merah kalau mati
svc_status() {
    local name="$1"
    if systemctl is-active --quiet "$name" 2>/dev/null; then
        echo -e "${BGREEN}●${NC}"
    else
        echo -e "${BRED}●${NC}"
    fi
}

show_header() {
    local ip domain today
    ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null || curl -s --max-time 5 ipv4.icanhazip.com)
    domain=$(cat /etc/zv-manager/domain 2>/dev/null)
    today=$(date +"%A, %d %B %Y — %H:%M")

    # Kumpulkan status semua service (cepat, paralel)
    local s_ssh s_db s_nginx s_wss s_udp
    s_ssh=$(svc_status ssh)
    s_db=$(svc_status dropbear)
    s_nginx=$(svc_status nginx)
    s_wss=$(svc_status zv-wss)
    s_udp=$(svc_status zv-udp)

    clear
    echo -e "${BCYAN}  ╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${BCYAN}  ║${NC}  ${BWHITE}ZV-Manager${NC} ${BYELLOW}v${SCRIPT_VERSION}${NC}                                ${BCYAN}║${NC}"
    echo -e "${BCYAN}  ╠══════════════════════════════════════════════════╣${NC}"
    echo -e "${BCYAN}  ║${NC}  ${BWHITE}IP     :${NC} ${BGREEN}${ip}${NC}"
    echo -e "${BCYAN}  ║${NC}  ${BWHITE}Domain :${NC} ${BGREEN}${domain}${NC}"
    echo -e "${BCYAN}  ║${NC}  ${BWHITE}Waktu  :${NC} ${BYELLOW}${today}${NC}"
    echo -e "${BCYAN}  ╠══════════════════════════════════════════════════╣${NC}"
    echo -e "${BCYAN}  ║${NC}  ${s_ssh} SSH  ${s_db} Dropbear  ${s_nginx} Nginx  ${s_wss} WS  ${s_udp} UDP"
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
        echo -e "  ${BGREEN}[2]${NC} Manajemen Server"
        echo -e "  ${BGREEN}[3]${NC} Informasi Server"
        echo -e "  ${BGREEN}[4]${NC} System & Services"
        echo ""
        echo -e "  ${BYELLOW}[r]${NC} Restart Semua Service"
        echo -e "  ${BRED}[0]${NC} Keluar"
        echo ""
        read -rp "  Pilihan: " choice

        case $choice in
            1) bash /etc/zv-manager/menu/ssh/menu-ssh.sh ;;
            2) bash /etc/zv-manager/menu/server/menu-server.sh ;;
            3) bash /etc/zv-manager/menu/info/server-info.sh ;;
            4) bash /etc/zv-manager/menu/system/menu-system.sh ;;
            r|R)
                for svc in ssh dropbear nginx zv-wss zv-udp; do
                    systemctl restart "$svc" &>/dev/null
                done
                echo -e "  ${BGREEN}Semua service di-restart!${NC}"
                sleep 2
                ;;
            0) clear; exit 0 ;;
            *) echo -e "  ${BRED}Pilihan tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}

main_menu
