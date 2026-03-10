#!/bin/bash
# ============================================================
#   ZV-Manager - Domain Setup
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh

setup_domain() {
    local ip
    ip=$(curl -s --max-time 10 ipv4.icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')

    echo ""
    echo -e "  IP Publik VPS: ${BWHITE}${ip}${NC}"
    echo ""
    read -rp "  Domain untuk VPS ini (kosongkan = pakai IP): " input_domain
    input_domain=$(echo "$input_domain" | tr -d '[:space:]')

    if [[ -n "$input_domain" && ! "$input_domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$input_domain" > /etc/zv-manager/domain
        print_ok "Domain digunakan: $input_domain"
    else
        echo "$ip" > /etc/zv-manager/domain
        print_ok "IP Address digunakan sebagai host: $ip"
    fi
}
