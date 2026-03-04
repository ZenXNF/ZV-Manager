#!/bin/bash
# ============================================================
#   ZV-Manager - Setup SSL Certificate
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/core/ssl.sh

_show_ssl_status() {
    local ssl_type
    ssl_type=$(cat /etc/zv-manager/ssl/ssl-type 2>/dev/null || echo "self-signed")
    local domain
    domain=$(cat /etc/zv-manager/domain 2>/dev/null || echo "-")

    local exp_date="-"
    if [[ -f "/etc/zv-manager/ssl/cert.pem" ]]; then
        exp_date=$(openssl x509 -in /etc/zv-manager/ssl/cert.pem -noout -enddate 2>/dev/null \
            | cut -d= -f2 | awk '{print $1,$2,$4}')
    fi

    echo ""
    echo -e "  ${BWHITE}Tipe SSL  :${NC} ${BGREEN}${ssl_type}${NC}"
    echo -e "  ${BWHITE}Domain    :${NC} ${BYELLOW}${domain}${NC}"
    echo -e "  ${BWHITE}Berlaku   :${NC} ${exp_date}"
    echo ""
}

_setup_self_signed() {
    clear
    echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
    echo -e " │         ${BWHITE}GENERATE SSL SELF-SIGNED${NC}              │"
    echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BYELLOW}Self-signed tidak dipercaya browser, tapi cukup${NC}"
    echo -e "  ${BYELLOW}untuk koneksi SSH via WebSocket/UDP.${NC}"
    echo ""

    if confirm "Lanjut generate SSL self-signed?"; then
        rm -f /etc/zv-manager/ssl/ssl-type
        setup_ssl
        systemctl restart zv-stunnel &>/dev/null || true
        echo ""
        print_ok "SSL self-signed berhasil dibuat!"
    fi

    press_any_key
}

_setup_wildcard() {
    clear
    echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
    echo -e " │     ${BWHITE}LET'S ENCRYPT WILDCARD SSL${NC}               │"
    echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BYELLOW}Syarat:${NC}"
    echo -e "  ${BWHITE}1.${NC} Domain sudah diarahkan ke IP VPS ini"
    echo -e "  ${BWHITE}2.${NC} DNS dikelola di Cloudflare"
    echo -e "  ${BWHITE}3.${NC} Cloudflare API Token dengan izin Zone:DNS:Edit"
    echo ""
    echo -e "  ${BCYAN}Cara dapat API Token Cloudflare:${NC}"
    echo -e "  ${BWHITE}→${NC} cloudflare.com → My Profile → API Tokens"
    echo -e "  ${BWHITE}→${NC} Create Token → Edit zone DNS"
    echo ""

    local domain
    domain=$(cat /etc/zv-manager/domain 2>/dev/null)

    read -rp "  Domain utama (contoh: server.zenxnf.com) [${domain}]: " input_domain
    [[ -n "$input_domain" ]] && domain="$input_domain"

    if [[ -z "$domain" || "$domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_error "Domain tidak valid! Harus berupa domain, bukan IP."
        press_any_key
        return
    fi

    echo ""
    read -rsp "  Cloudflare API Token: " cf_token
    echo ""

    if [[ -z "$cf_token" ]]; then
        print_error "API Token tidak boleh kosong!"
        press_any_key
        return
    fi

    echo ""
    echo -e "  ${BWHITE}Domain   :${NC} ${BGREEN}*.${domain}${NC} + ${BGREEN}${domain}${NC}"
    echo ""

    if ! confirm "Lanjut request wildcard cert?"; then
        print_info "Dibatalkan."
        press_any_key
        return
    fi

    echo ""
    setup_ssl_wildcard "$domain" "$cf_token"

    if is_letsencrypt; then
        echo ""
        print_ok "Nginx & Stunnel di-reload dengan cert baru..."
        systemctl reload nginx &>/dev/null || systemctl restart nginx &>/dev/null
        systemctl restart zv-stunnel &>/dev/null || true

        echo ""
        echo -e "  ${BCYAN}┌─────────────────────────────────────────┐${NC}"
        echo -e "  ${BCYAN}│${NC}  ${BWHITE}Wildcard SSL Aktif!${NC}"
        echo -e "  ${BCYAN}├─────────────────────────────────────────┤${NC}"
        echo -e "  ${BCYAN}│${NC}  ${BGREEN}*.${domain}${NC} → VPS ini"
        echo -e "  ${BCYAN}│${NC}  Renew otomatis tiap hari jam 03:00"
        echo -e "  ${BCYAN}│${NC}"
        echo -e "  ${BCYAN}│${NC}  ${BYELLOW}Contoh bug host yang bisa dipakai:${NC}"
        echo -e "  ${BCYAN}│${NC}  ${BWHITE}WS  :${NC} free.${domain}:80"
        echo -e "  ${BCYAN}│${NC}  ${BWHITE}WSS :${NC} cdn.${domain}:443"
        echo -e "  ${BCYAN}│${NC}  ${BWHITE}SNI :${NC} subdomain apapun.${domain}"
        echo -e "  ${BCYAN}└─────────────────────────────────────────┘${NC}"
    fi

    press_any_key
}

_renew_manual() {
    clear
    echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
    echo -e " │           ${BWHITE}RENEW SSL CERTIFICATE${NC}               │"
    echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
    echo ""

    if ! is_letsencrypt; then
        print_info "SSL yang aktif adalah self-signed."
        print_info "Akan di-regenerate ulang..."
        echo ""
        setup_ssl
    else
        print_info "Mencoba renew Let's Encrypt certificate..."
        echo ""
        renew_ssl_wildcard
    fi

    press_any_key
}

setup_ssl_menu() {
    while true; do
        clear
        echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
        echo -e " │            ${BWHITE}MANAJEMEN SSL${NC}                      │"
        echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"

        _show_ssl_status

        echo -e "${BCYAN}  ──────────────────────────────────────────────${NC}"
        echo ""
        echo -e "  ${BGREEN}[1]${NC} SSL Self-Signed ${BYELLOW}(default)${NC}"
        echo -e "  ${BGREEN}[2]${NC} Let's Encrypt Wildcard ${BGREEN}(*.domain.com)${NC}"
        echo -e "  ${BGREEN}[3]${NC} Renew / Refresh Certificate"
        echo ""
        echo -e "  ${BRED}[0]${NC} Kembali"
        echo ""
        read -rp "  Pilihan: " choice

        case "$choice" in
            1) _setup_self_signed ;;
            2) _setup_wildcard    ;;
            3) _renew_manual      ;;
            0) break ;;
            *) echo -e "  ${BRED}Pilihan tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}

setup_ssl_menu
