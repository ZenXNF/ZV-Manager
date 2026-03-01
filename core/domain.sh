#!/bin/bash
# ============================================================
#   ZV-Manager - Domain Setup
#   Langsung pakai IP — domain hanya diisi saat certbot
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh

setup_domain() {
    # Langsung ambil IP publik, tidak perlu tanya user
    local ip
    ip=$(curl -s --max-time 10 ipv4.icanhazip.com)
    echo "$ip" > /etc/zv-manager/domain
    print_ok "IP Address digunakan sebagai host: $ip"
}
