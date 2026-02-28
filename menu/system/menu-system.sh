#!/bin/bash
# ============================================================
#   ZV-Manager - System Menu
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/helpers.sh

restart_all_services() {
    clear
    print_section "Restart Semua Service"

    for svc in ssh dropbear nginx zv-ws zv-wss zv-udp zv-badvpn fail2ban; do
        if systemctl list-units --type=service | grep -q "$svc"; then
            restart_service "$svc"
        fi
    done

    press_any_key
}

show_running_services() {
    clear
    echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
    echo -e " │             ${BWHITE}STATUS LAYANAN${NC}                    │"
    echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
    echo ""

    local services=("ssh" "dropbear" "nginx" "zv-ws" "zv-wss" "zv-udp" "zv-badvpn" "fail2ban")
    for svc in "${services[@]}"; do
        if systemctl list-units --type=service --all | grep -q "$svc"; then
            if systemctl is-active --quiet "$svc"; then
                echo -e "  ${BGREEN}●${NC} ${svc}: ${BGREEN}Running${NC}"
            else
                echo -e "  ${BRED}●${NC} ${svc}: ${BRED}Stopped${NC}"
            fi
        fi
    done

    echo ""
    press_any_key
}

menu_system() {
    while true; do
        clear
        echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
        echo -e " │            ${BWHITE}MENU SYSTEM${NC}                       │"
        echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "  ${BGREEN}[1]${NC} Restart Semua Service"
        echo -e "  ${BGREEN}[2]${NC} Status Semua Service"
        echo -e "  ${BGREEN}[3]${NC} Clear Cache"
        echo -e "  ${BGREEN}[4]${NC} Set Auto Reboot"
        echo ""
        echo -e "  ${BRED}[0]${NC} Kembali ke Menu Utama"
        echo ""
        read -rp "  Pilihan: " choice

        case $choice in
            1) restart_all_services ;;
            2) show_running_services ;;
            3) bash /etc/zv-manager/menu/system/clear-cache.sh ;;
            4) bash /etc/zv-manager/menu/system/auto-reboot.sh ;;
            0) break ;;
            *) echo -e "  ${BRED}Pilihan tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}

menu_system
