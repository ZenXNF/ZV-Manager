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
    echo -e "  ${BWHITE}Port      :${NC} ${BYELLOW}${NGINX_PORT}${NC}"
    echo -e "  ${BWHITE}Contoh    :${NC} ${BYELLOW}http://IP-VPS:${NGINX_PORT}${NC}"
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
    if ! nginx -T 2>/dev/null | grep -q "listen ${NGINX_PORT}"; then
        cat > /etc/nginx/sites-available/zv-status << NGINXEOF
server {
    listen ${NGINX_PORT};
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
    print_ok "Halaman web berhasil diinstall!"
    echo ""
    local local_ip
    local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null)
    echo -e "  ${BWHITE}Akses di :${NC} ${BGREEN}http://${local_ip}:${NGINX_PORT}${NC}"
    echo ""
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

_open_web_info() {
    local local_ip
    local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null)
    clear
    echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
    echo -e " │          ${BWHITE}INFO HALAMAN WEB STATUS${NC}             │"
    echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BWHITE}Status    :${NC} ${BGREEN}Aktif${NC}"
    echo -e "  ${BWHITE}URL       :${NC} ${BYELLOW}http://${local_ip}:${NGINX_PORT}${NC}"
    echo -e "  ${BWHITE}Port      :${NC} ${BYELLOW}${NGINX_PORT}${NC}"
    echo -e "  ${BWHITE}Update    :${NC} ${BYELLOW}Otomatis setiap 5 menit${NC}"
    echo -e "  ${BWHITE}File web  :${NC} ${BYELLOW}${WEB_DIR}/index.html${NC}"
    echo ""
    echo -e "  ${BGREEN}[1]${NC} Refresh sekarang"
    echo -e "  ${BRED}[2]${NC} Uninstall"
    echo -e "  ${BRED}[0]${NC} Kembali"
    echo ""
    read -rp "  Pilihan: " ch
    case "$ch" in
        1)
            print_info "Refresh halaman..."
            bash "$STATUS_SCRIPT" 2>/dev/null
            print_ok "Selesai! Buka http://${local_ip}:${NGINX_PORT}"
            press_any_key
            ;;
        2) _uninstall_web ;;
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
