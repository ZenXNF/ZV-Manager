#!/bin/bash
# ============================================================
#   ZV-Manager - Auto Reboot Scheduler
# ============================================================
source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/utils/logger.sh

set_auto_reboot() {
    clear
    echo -e "${BCYAN} ┌─────────────────────────────────────────────┐${NC}"
    echo -e " │            ${BWHITE}SET AUTO REBOOT${NC}                   │"
    echo -e "${BCYAN} └─────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BGREEN}[1]${NC} Setiap hari jam 00:00"
    echo -e "  ${BGREEN}[2]${NC} Setiap hari jam 03:00"
    echo -e "  ${BGREEN}[3]${NC} Setiap hari jam 05:00"
    echo -e "  ${BGREEN}[4]${NC} Matikan Auto Reboot"
    echo ""
    read -rp "  Pilihan: " choice

    case $choice in
        1) echo "0 0 * * * root /sbin/reboot" > /etc/cron.d/zv-reboot; print_ok "Auto reboot jam 00:00" ;;
        2) echo "0 3 * * * root /sbin/reboot" > /etc/cron.d/zv-reboot; print_ok "Auto reboot jam 03:00" ;;
        3) echo "0 5 * * * root /sbin/reboot" > /etc/cron.d/zv-reboot; print_ok "Auto reboot jam 05:00" ;;
        4) rm -f /etc/cron.d/zv-reboot; print_ok "Auto reboot dimatikan" ;;
        *) print_error "Pilihan tidak valid!" ;;
    esac

    service cron restart &>/dev/null
    press_any_key
}

set_auto_reboot
