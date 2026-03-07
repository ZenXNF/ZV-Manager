#!/bin/bash
# ============================================================
#   ZV-Manager - Setup Halaman Web Status
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh

NGINX_PORT=$(grep "^NGINX_PORT=" /etc/zv-manager/config.conf 2>/dev/null | cut -d= -f2 | tr -d '"')
NGINX_PORT=${NGINX_PORT:-81}
WEB_DIR="/var/www/zv-manager"
STATUS_CRON="/etc/cron.d/zv-status-page"
STATUS_SCRIPT="/etc/zv-manager/cron/status-page.sh"

_is_web_installed() {
    [[ -f "$STATUS_CRON" && -d "$WEB_DIR" ]]
}

_install_web() {
    clear
    echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
    echo -e " │         ${BWHITE}INSTALL HALAMAN WEB STATUS${NC}          │"
    echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  Halaman web ini menampilkan status semua server"
    echo -e "  secara real-time dan bisa diakses oleh user."
    echo ""
    
    echo -e "  ${BWHITE}Contoh    :${NC} ${BYELLOW}https://${DOMAIN}/status${NC}"
    echo -e "  ${BWHITE}Update    :${NC} ${BYELLOW}Otomatis setiap 5 menit${NC}"
    echo ""
    read -rp "  Lanjutkan install? [y/N]: " conf
    [[ "${conf,,}" != "y" ]] && return

    echo ""
    print_info "Membuat direktori web..."
    mkdir -p "$WEB_DIR"
    chown -R www-data:www-data "$WEB_DIR" 2>/dev/null || true

    print_info "Mengkonfigurasi nginx..."
    # Cek apakah nginx sudah ada konfigurasi port ini
    if ! nginx -T 2>/dev/null | grep -q "location /status"; then
        cat > /etc/nginx/sites-available/zv-status << NGINXEOF
server {
    
    server_name _;
    root ${WEB_DIR};
    index index.html;
    location / {
        try_files \$uri \$uri/ /index.html;
    }
    access_log off;
}
NGINXEOF
        ln -sf /etc/nginx/sites-available/zv-status \
                /etc/nginx/sites-enabled/zv-status 2>/dev/null || true
        nginx -t &>/dev/null && systemctl reload nginx &>/dev/null || true
    fi

    print_info "Menambahkan cron status page..."
    cat > "$STATUS_CRON" << CRONEOF
# ZV-Manager status page — update tiap 5 menit
*/5 * * * * root /bin/bash ${STATUS_SCRIPT} >/dev/null 2>&1
CRONEOF

    print_info "Generate halaman pertama kali..."
    bash "$STATUS_SCRIPT" 2>/dev/null

    echo ""
    # Default host = IPv4
    local local_ip
    local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null)
    echo "$local_ip" > /etc/zv-manager/web-host

    print_ok "Halaman web berhasil diinstall!"
    echo ""
    echo -e "  ${BWHITE}Akses di :${NC} ${BGREEN}https://${DOMAIN}/status${NC}"
    echo ""
    echo -e "  ${BYELLOW}Ingin menggunakan domain custom?${NC}"
    read -rp "  Ganti ke domain? [y/N]: " ganti
    if [[ "${ganti,,}" == "y" ]]; then
        _change_host
        bash "$STATUS_SCRIPT" 2>/dev/null
    fi
    press_any_key
}

_uninstall_web() {
    clear
    echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
    echo -e " │        ${BWHITE}UNINSTALL HALAMAN WEB STATUS${NC}         │"
    echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BRED}Ini akan menghapus halaman web dan cron update.${NC}"
    echo ""
    read -rp "  Yakin uninstall? [y/N]: " conf
    [[ "${conf,,}" != "y" ]] && return

    rm -f "$STATUS_CRON"
    rm -f /etc/nginx/sites-enabled/zv-status
    rm -f /etc/nginx/sites-available/zv-status
    rm -rf "$WEB_DIR"
    nginx -t &>/dev/null && systemctl reload nginx &>/dev/null || true

    echo ""
    print_ok "Halaman web berhasil dihapus."
    press_any_key
}

_change_host() {
    local local_ip current
    local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null)
    current=$(cat /etc/zv-manager/web-host 2>/dev/null || echo "$local_ip")

    clear
    echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
    echo -e " │         ${BWHITE}PILIH ALAMAT WEB STATUS${NC}             │"
    echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  Saat ini  : ${BYELLOW}${current}${NC}"
    echo ""
    echo -e "  ${BGREEN}[1]${NC} IPv4 — ${local_ip}"
    echo -e "  ${BGREEN}[2]${NC} Domain (masukkan manual)"
    echo -e "  ${BRED}[0]${NC} Kembali"
    echo ""
    read -rp "  Pilihan: " ch
    case "$ch" in
        1)
            echo "$local_ip" > /etc/zv-manager/web-host
            print_ok "Berubah ke IPv4: ${local_ip}"
            sleep 1
            ;;
        2)
            echo ""
            read -rp "  Masukkan domain (contoh: status.zenxu.my.id): " input_domain
            input_domain="${input_domain// /}"
            if [[ -z "$input_domain" ]]; then
                print_error "Domain tidak boleh kosong!"; sleep 1; return
            fi
            print_info "Memverifikasi domain ${input_domain}..."
            local resolved
            resolved=$(dig +short "$input_domain" A 2>/dev/null | head -1)
            if [[ -z "$resolved" ]]; then
                print_error "Domain tidak bisa di-resolve. Pastikan DNS sudah dikonfigurasi."
                press_any_key; return
            fi
            if [[ "$resolved" != "$local_ip" ]]; then
                print_error "Domain mengarah ke ${resolved}, bukan ke VPS ini (${local_ip})."
                press_any_key; return
            fi
            echo "$input_domain" > /etc/zv-manager/web-host
            print_ok "Domain valid! Berubah ke: ${input_domain}"
            sleep 1
            ;;
    esac
}

_open_web_info() {
    local local_ip host
    local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null)
    host=$(cat /etc/zv-manager/web-host 2>/dev/null || echo "$local_ip")
    clear
    echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
    echo -e " │          ${BWHITE}INFO HALAMAN WEB STATUS${NC}             │"
    echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BWHITE}Status    :${NC} ${BGREEN}Aktif${NC}"
    echo -e "  ${BWHITE}URL       :${NC} ${BYELLOW}https://${DOMAIN}/status${NC}"
    
    echo -e "  ${BWHITE}Update    :${NC} ${BYELLOW}Otomatis setiap 5 menit${NC}"
    echo ""
    echo -e "  ${BGREEN}[1]${NC} Refresh sekarang"
    echo -e "  ${BGREEN}[2]${NC} Ganti domain/IPv4"
    echo -e "  ${BRED}[3]${NC} Uninstall"
    echo -e "  ${BRED}[0]${NC} Kembali"
    echo ""
    read -rp "  Pilihan: " ch
    case "$ch" in
        1)
            print_info "Refresh halaman..."
            bash "$STATUS_SCRIPT" 2>/dev/null
            print_ok "Selesai! Buka https://${DOMAIN}/status"
            press_any_key
            ;;
        2) _change_host; bash "$STATUS_SCRIPT" 2>/dev/null ;;
        3) _uninstall_web ;;
    esac
}

setup_web_menu() {
    if _is_web_installed; then
        _open_web_info
    else
        _install_web
    fi
}

setup_web_menu
