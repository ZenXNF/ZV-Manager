#!/bin/bash
# ============================================================
#   ZV-Manager - Auto Reboot Scheduler
# ============================================================
source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/utils/logger.sh

CRON_FILE="/etc/cron.d/zv-reboot"

_get_current_schedule() {
    if [[ ! -f "$CRON_FILE" ]]; then
        echo ""
        return
    fi
    local entry
    entry=$(grep -v "^#" "$CRON_FILE" | grep -v "^$" | head -1)
    [[ -z "$entry" ]] && echo "" && return
    local hour min
    min=$(awk '{print $1}' <<< "$entry")
    hour=$(awk '{print $2}' <<< "$entry")
    printf "%02d:%02d" "$hour" "$min"
}

set_auto_reboot() {
    while true; do
        clear
        echo -e "${BCYAN} ┌─────────────────────────────────────────────┐${NC}"
        echo -e " │            ${BWHITE}AUTO REBOOT SCHEDULER${NC}             │"
        echo -e "${BCYAN} └─────────────────────────────────────────────┘${NC}"
        echo ""

        # Tampilkan jadwal aktif
        local current
        current=$(_get_current_schedule)
        if [[ -n "$current" ]]; then
            echo -e "  ${BWHITE}Jadwal aktif :${NC} ${BGREEN}Setiap hari jam ${current} WIB${NC}"
        else
            echo -e "  ${BWHITE}Jadwal aktif :${NC} ${BYELLOW}Tidak ada (auto reboot mati)${NC}"
        fi

        echo ""
        echo -e "  ${BWHITE}[1]${NC} Set jam reboot"
        echo -e "  ${BWHITE}[2]${NC} Matikan auto reboot"
        echo -e "  ${BWHITE}[0]${NC} Kembali"
        echo ""
        read -rp "  Pilihan: " choice

        case "$choice" in
            1)
                echo ""
                echo -e "  ${BYELLOW}Masukkan jam reboot (format HH:MM, contoh: 03:00)${NC}"
                echo -e "  ${BYELLOW}Rekomendasi: dini hari saat traffic rendah (00:00 – 05:00)${NC}"
                echo ""
                while true; do
                    read -rp "  Jam reboot [HH:MM]: " input_time
                    if [[ "$input_time" =~ ^([01][0-9]|2[0-3]):([0-5][0-9])$ ]]; then
                        local hour min
                        hour=$(echo "$input_time" | cut -d: -f1 | sed 's/^0//')
                        min=$(echo "$input_time" | cut -d: -f2 | sed 's/^0//')
                        [[ -z "$hour" ]] && hour=0
                        [[ -z "$min"  ]] && min=0
                        {
                            echo "# ZV-Manager - Auto Reboot"
                            echo "${min} ${hour} * * * root /sbin/reboot"
                        } > "$CRON_FILE"
                        service cron restart &>/dev/null
                        echo ""
                        print_ok "Auto reboot diset jam $(printf '%02d:%02d' "$hour" "$min") WIB setiap hari."
                        press_any_key
                        break
                    else
                        echo -e "  ${BRED}Format salah. Gunakan HH:MM (contoh: 03:00)${NC}"
                    fi
                done
                ;;
            2)
                rm -f "$CRON_FILE"
                service cron restart &>/dev/null
                echo ""
                print_ok "Auto reboot dimatikan."
                press_any_key
                ;;
            0) return ;;
            *) print_error "Pilihan tidak valid." ; sleep 1 ;;
        esac
    done
}

set_auto_reboot
