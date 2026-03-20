#!/bin/bash
# ============================================================
#   ZV-Manager - List Server
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh

SERVER_DIR="/etc/zv-manager/servers"

list_servers() {
    clear
    _sep
    _grad " DAFTAR SERVER" 255 0 127 0 210 255
    _sep
    echo ""

    local count=0
    printf "  ${BWHITE}%-4s %-10s %-22s %-20s %-5s${NC}\n" "No." "Nama" "Domain" "IP" "Port"
    echo -e "  ${BCYAN}──────────────────────────────────────────────────────${NC}"

    local _ipvps; _ipvps=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null | tr -d "[:space:]")
    for conf in "${SERVER_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue
        [[ "$conf" == *.tg.conf ]] && continue
        unset NAME IP DOMAIN PORT USER
        source "$conf"
        count=$((count + 1))
        # Fallback IP ke ipvps untuk server lokal (IP tidak disimpan di conf)
        local disp_ip="${IP:-${_ipvps}}"
        local disp_port="${PORT:-22}"
        local disp_domain="${DOMAIN:-$disp_ip}"
        printf "  ${BGREEN}%-4s${NC} %-10s %-22s %-20s %-5s\n" \
            "${count}." "$NAME" "$disp_domain" "$disp_ip" "$disp_port"
    done

    if [[ $count -eq 0 ]]; then
        echo -e "  ${BYELLOW}Belum ada server yang ditambahkan.${NC}"
    fi

    echo ""
    echo -e "  ${BYELLOW}Total: ${count} server${NC}"
    echo ""
    press_any_key
}

list_servers
