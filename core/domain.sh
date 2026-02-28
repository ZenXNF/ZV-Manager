#!/bin/bash
# ============================================================
#   ZV-Manager - Domain / IP Setup
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh

setup_domain() {
    clear
    print_section "Setup Domain / IP"

    echo -e "  ${BWHITE}Pilih tipe host yang digunakan:${NC}"
    echo ""
    echo -e "  ${BGREEN}[1]${NC} Gunakan Domain Sendiri"
    echo -e "  ${BGREEN}[2]${NC} Gunakan IP Address VPS"
    echo ""
    read -rp "  Pilihan [1/2]: " choice

    case $choice in
        1)
            echo ""
            read -rp "  Masukkan domain kamu (contoh: vpn.example.com): " domain_input
            if [[ -z "$domain_input" ]]; then
                print_error "Domain tidak boleh kosong!"
                setup_domain
                return
            fi
            echo "$domain_input" > /etc/zv-manager/domain
            print_ok "Domain disimpan: $domain_input"
            ;;
        2)
            local ip
            ip=$(curl -s --max-time 10 ipv4.icanhazip.com)
            echo "$ip" > /etc/zv-manager/domain
            print_ok "IP Address digunakan: $ip"
            ;;
        *)
            print_error "Pilihan tidak valid!"
            setup_domain
            ;;
    esac
}
