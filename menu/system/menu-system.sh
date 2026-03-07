#!/bin/bash
# ============================================================
#   ZV-Manager - Menu System
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh

restart_all_services() {
    clear
    print_section "Restart Semua Service"
    for svc in ssh dropbear nginx zv-stunnel zv-wss zv-udp fail2ban; do
        systemctl list-units --type=service --all | grep -q "${svc}.service" && \
            restart_service "$svc"
    done
    press_any_key
}

show_running_services() {
    clear
    echo -e "${BCYAN}  ┌──────────────────────────────────────────────┐${NC}"
    echo -e "  │              ${BWHITE}STATUS LAYANAN${NC}                  │"
    echo -e "${BCYAN}  └──────────────────────────────────────────────┘${NC}"
    echo ""
    local services=(ssh dropbear nginx zv-stunnel zv-wss zv-udp zv-telegram fail2ban)
    for svc in "${services[@]}"; do
        systemctl list-units --type=service --all 2>/dev/null | grep -q "${svc}.service" || continue
        if systemctl is-active --quiet "$svc"; then
            echo -e "  ${BGREEN}●${NC} ${svc}"
        else
            echo -e "  ${BRED}●${NC} ${svc}"
        fi
    done
    echo ""
    press_any_key
}

menu_system() {
    while true; do
        clear
        echo -e "${BCYAN}  ┌──────────────────────────────────────────────┐${NC}"
        echo -e "  │             ${BWHITE}SYSTEM & SERVICES${NC}               │"
        echo -e "${BCYAN}  └──────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "  ${BGREEN}[1]${NC} Restart Services     ${BGREEN}[2]${NC} Status Services"
        echo -e "  ${BGREEN}[3]${NC} Clear Cache          ${BGREEN}[4]${NC} Auto Reboot"
        echo -e "  ${BGREEN}[5]${NC} Edit Banner          ${BGREEN}[6]${NC} Manajemen SSL"
        echo -e "  ${BGREEN}[7]${NC} Setup Telegram Bot   ${BGREEN}[8]${NC} Backup & Restore"
        echo -e "  ${BGREEN}[9]${NC} Halaman Web Status"
        echo ""
        echo -e "  ${BRED}[0]${NC} Kembali"
        echo ""
        read -rp "  Pilihan: " choice

        case $choice in
            1) restart_all_services ;;
            2) show_running_services ;;
            3) bash /etc/zv-manager/menu/system/clear-cache.sh ;;
            4) bash /etc/zv-manager/menu/system/auto-reboot.sh ;;
            5) bash /etc/zv-manager/menu/system/edit-banner.sh ;;
            6) bash /etc/zv-manager/menu/system/setup-ssl.sh ;;
            7) bash /etc/zv-manager/menu/system/setup-telegram.sh ;;
            8) bash /etc/zv-manager/menu/system/backup.sh ;;
            9) bash /etc/zv-manager/menu/system/setup-web.sh ;;
            0) break ;;
            *) echo -e "  ${BRED}Pilihan tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}

menu_system
