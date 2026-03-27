#!/bin/bash
# ============================================================
#   ZV-Manager - Setup Halaman Web Status
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh

WEB_DIR="/var/www/zv-manager"
STATUS_SCRIPT="/etc/zv-manager/cron/status-page.sh"
WEB_MARKER="/etc/zv-manager/.web-installed"

_is_web_installed() {
    [[ -f "$WEB_MARKER" && -d "$WEB_DIR" ]]
}

_get_url() {
    local host; host=$(cat /etc/zv-manager/web-host 2>/dev/null)
    [[ -z "$host" ]] && { echo ""; return; }
    # IP → port 8080 (sudah serve status page dari nginx utama)
    # Domain → https (port 443 via ssl_preread → nginx:8443)
    [[ "$host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && echo "http://${host}:8080" || echo "https://${host}"
}

_install_web() {
    clear
    _sep
    _grad " INSTALL HALAMAN WEB STATUS" 0 210 255 160 80 255
    _sep
    echo ""
    echo -e "  Halaman web menampilkan status server secara real-time."
    echo -e "  Dapat diakses oleh user/reseller kamu."
    echo ""

    # Default host
    local local_ip; local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null)
    local domain; domain=$(cat /etc/zv-manager/domain 2>/dev/null | tr -d '[:space:]')
    local default_host="$local_ip"
    # Jika domain bukan IP, pakai domain
    if [[ -n "$domain" && ! "$domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        default_host="$domain"
        echo -e "  ${D}Default :${NC} ${W}https://${domain}${NC} ${D}(domain)${NC}"
    else
        echo -e "  ${D}Default :${NC} ${W}http://${local_ip}:8080${NC} ${D}(IPv4)${NC}"
    fi
    echo ""
    read -rp "  Install sekarang? [y/N]: " conf
    [[ "${conf,,}" != "y" ]] && return

    echo ""
    mkdir -p "$WEB_DIR"
    chown -R www-data:www-data "$WEB_DIR" 2>/dev/null || true

    # Nginx config — hanya dibutuhkan untuk domain dengan Let's Encrypt
    # Mode IP: port 8080 sudah handle di nginx.conf utama, tidak perlu site terpisah
    _write_web_nginx() {
        local host; host=$(cat /etc/zv-manager/web-host 2>/dev/null)
        # IP mode → tidak perlu nginx site, port 8080 sudah cukup
        if [[ "$host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            return 0
        fi
        local cert="/etc/letsencrypt/live/${host}/fullchain.pem"
        local key="/etc/letsencrypt/live/${host}/privkey.pem"
        if [[ -f "$cert" ]]; then
            # Domain + Let's Encrypt cert → HTTPS via port 443
            cat > /etc/nginx/sites-available/zv-status << NGINXEOF
server {
    listen 80;
    server_name ${host};
    return 301 https://\$host\$request_uri;
}
server {
    listen 8444 ssl;
    server_name ${host};
    ssl_certificate ${cert};
    ssl_certificate_key ${key};
    root ${WEB_DIR};
    index index.html;
    location / { try_files \$uri \$uri/ =404; }
    location ~* \.(json|js|css|png|ico)$ {
        add_header Cache-Control "no-cache";
        try_files \$uri =404;
    }
    access_log off;
}
NGINXEOF
        else
            # Domain tapi belum ada cert → pakai self-signed via port 8443
            # Traffic lewat: 443 ssl_preread → 18443 → ws-proxy → nginx 8443
            # Tidak perlu site terpisah, 8443 sudah handle domain
            return 0
        fi
        ln -sf /etc/nginx/sites-available/zv-status \
                /etc/nginx/sites-enabled/zv-status 2>/dev/null || true
        nginx -t &>/dev/null && systemctl reload nginx &>/dev/null || true
    }

    if ! nginx -T 2>/dev/null | grep -q "zv-status\|var/www/zv-manager"; then
        _write_web_nginx
    fi

    # Set default host
    echo "$default_host" > /etc/zv-manager/web-host

    # Marker file
    touch "$WEB_MARKER"

    # Tambah cron status-page
    printf '%s\n' "*/5 * * * * root /bin/bash /etc/zv-manager/cron/status-page.sh" \
        > /etc/cron.d/zv-status-page

    # Generate halaman pertama
    bash "$STATUS_SCRIPT" 2>/dev/null

    echo ""
    local url; url=$(_get_url)
    print_ok "Halaman web berhasil diinstall!"
    echo -e "  ${D}Akses di :${NC} ${G}${url}${NC}"
    echo ""
    press_any_key
}

_uninstall_web() {
    clear
    _sep
    _grad " UNINSTALL HALAMAN WEB STATUS" 255 50 50 255 150 0
    _sep
    echo ""
    echo -e "  ${BRED}Ini akan menghapus halaman web status.${NC}"
    echo ""
    read -rp "  Yakin uninstall? [y/N]: " conf
    [[ "${conf,,}" != "y" ]] && return

    rm -f "$WEB_MARKER"
    rm -f /etc/cron.d/zv-status-page
    rm -f /etc/nginx/sites-enabled/zv-status
    rm -f /etc/nginx/sites-available/zv-status
    rm -rf "$WEB_DIR"
    rm -f /etc/zv-manager/web-host
    nginx -t &>/dev/null && systemctl reload nginx &>/dev/null || true

    echo ""
    print_ok "Halaman web berhasil dihapus."
    press_any_key
}

_change_host() {
    local local_ip; local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null)
    local current; current=$(cat /etc/zv-manager/web-host 2>/dev/null || echo "$local_ip")

    clear
    _sep
    _grad " GANTI ALAMAT WEB STATUS" 0 210 255 160 80 255
    _sep
    echo ""
    echo -e "  ${D}Saat ini :${NC} ${W}${current}${NC}"
    echo ""
    echo -e "  $(_grad '[1]' 0 210 255 160 80 255) IPv4 — ${local_ip}"
    echo -e "  $(_grad '[2]' 0 210 255 160 80 255) Domain (masukkan manual)"
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
            read -rp "  Domain (contoh: status.zenxu.my.id): " input_domain
            input_domain="${input_domain// /}"
            [[ -z "$input_domain" ]] && { print_error "Domain tidak boleh kosong!"; sleep 1; return; }
            print_info "Memverifikasi domain ${input_domain}..."
            local resolved
            resolved=$(dig +short "$input_domain" A 2>/dev/null | head -1)
            [[ -z "$resolved" ]] && resolved=$(host -t A "$input_domain" 2>/dev/null | awk '/has address/{print $4}' | head -1)
            if [[ -z "$resolved" ]]; then
                print_error "Domain tidak bisa di-resolve."; press_any_key; return
            fi
            if [[ "$resolved" != "$local_ip" ]]; then
                print_error "Domain mengarah ke ${resolved}, bukan ${local_ip}."; press_any_key; return
            fi
            echo "$input_domain" > /etc/zv-manager/web-host
            print_ok "Domain valid! Berubah ke: ${input_domain}"
            sleep 1
            ;;
    esac
}

_web_info() {
    while true; do
    local url; url=$(_get_url)
    local ssl_type; ssl_type=$(cat /etc/zv-manager/ssl/ssl-type 2>/dev/null || echo "self-signed")
    local ssl_label
    [[ "$ssl_type" == "letsencrypt" || "$ssl_type" == "wildcard" ]] && \
        ssl_label="${BGREEN}Let's Encrypt ✓${NC}" || ssl_label="${BYELLOW}Self-Signed${NC}"

    clear
    _sep
    _grad " HALAMAN WEB STATUS" 0 210 255 160 80 255
    _sep
    echo ""
    echo -e "  ${BWHITE}Status :${NC} ${BGREEN}Aktif ●${NC}"
    echo -e "  ${BWHITE}URL    :${NC} ${BYELLOW}${url:-belum diset}${NC}"
    echo -e "  ${BWHITE}SSL    :${NC} ${ssl_label}"
    echo -e "  ${BWHITE}Update :${NC} ${BYELLOW}Otomatis setiap 5 menit${NC}"
    echo ""
    echo -e "  $(_grad '[1]' 0 210 255 160 80 255) Refresh sekarang"
    echo -e "  $(_grad '[2]' 0 210 255 160 80 255) Ganti domain/IPv4"
    echo -e "  $(_grad '[3]' 0 210 255 160 80 255) Request Let's Encrypt SSL"
    echo -e "  ${BRED}[4]${NC} Uninstall"
    echo ""
    echo -e "  ${BRED}[0]${NC} Kembali"
    echo ""
    read -rp "  Pilihan: " ch
    case "$ch" in
        1)
            print_info "Refresh halaman..."
            bash "$STATUS_SCRIPT" 2>/dev/null
            print_ok "Selesai! Buka ${url}"
            press_any_key
            ;;
        2)
            _change_host
            bash "$STATUS_SCRIPT" 2>/dev/null
            ;;
        3)
            local cur_host; cur_host=$(cat /etc/zv-manager/web-host 2>/dev/null)
            if [[ -z "$cur_host" || "$cur_host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                print_error "Set domain dulu via opsi [2] sebelum request SSL!"
                press_any_key; continue
            fi
            read -rp "  Request Let's Encrypt untuk ${cur_host}? [y/N]: " yn
            [[ "$yn" != "y" && "$yn" != "Y" ]] && continue
            source /etc/zv-manager/core/ssl.sh
            setup_ssl_letsencrypt "$cur_host"
            # Update nginx config pakai cert baru
            local cert="/etc/letsencrypt/live/${cur_host}/fullchain.pem"
            local key="/etc/letsencrypt/live/${cur_host}/privkey.pem"
            if [[ -f "$cert" ]]; then
                cat > /etc/nginx/sites-available/zv-status << NGINXEOF
server {
    listen 80;
    server_name ${cur_host};
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl;
    server_name ${cur_host};
    ssl_certificate ${cert};
    ssl_certificate_key ${key};
    root /var/www/zv-manager;
    index index.html;
    location / { try_files \$uri \$uri/ /index.html; }
    access_log off;
}
NGINXEOF
                nginx -t &>/dev/null && systemctl reload nginx &>/dev/null
                echo "ssl-type=letsencrypt" > /etc/zv-manager/ssl/ssl-type 2>/dev/null || true
            fi
            press_any_key
            ;;
        4) _uninstall_web; break ;;
        0) break ;;
        *) ;;
    esac
    done
}

# ── Main ──────────────────────────────────────────────────────
if _is_web_installed; then
    _web_info
else
    _install_web
fi
