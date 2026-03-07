#!/bin/bash
# ============================================================
#   ZV-Manager - SSL Certificate Setup
#   Mode 1: Self-Signed (default, tanpa domain)
#   Mode 2: Let's Encrypt Wildcard via Cloudflare DNS
# ============================================================

source /etc/zv-manager/utils/colors.sh 2>/dev/null || true
source /etc/zv-manager/utils/logger.sh 2>/dev/null || true

SSL_DIR="/etc/zv-manager/ssl"
LE_CRED="/etc/zv-manager/cloudflare.ini"

# ============================================================
# MODE 1: Self-Signed (fallback / tanpa domain)
# ============================================================
setup_ssl() {
    print_section "Generate SSL Certificate (Self-Signed)"

    mkdir -p "$SSL_DIR"

    local domain_file; domain_file=$(cat /etc/zv-manager/domain 2>/dev/null | tr -d "[:space:]")

    # Gunakan domain jika bukan IP, fallback ke IP publik
    local cn
    if [[ -n "$domain_file" && ! "$domain_file" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # /etc/zv-manager/domain sudah berisi domain — pakai langsung
        cn="$domain_file"
    else
        # Coba cari domain dari server conf
        local local_ip; local_ip="$domain_file"
        cn="$local_ip"
        for conf in /etc/zv-manager/servers/*.conf; do
            [[ -f "$conf" ]] || continue
            unset IP DOMAIN
            source "$conf"
            if [[ "$IP" == "$local_ip" && -n "$DOMAIN" && "$DOMAIN" != "$local_ip" ]]; then
                cn="$DOMAIN"
                break
            fi
        done
        # Kalau masih IP, fallback ke IP publik VPS
        [[ -z "$cn" ]] && cn=$(curl -s --max-time 5 ipv4.icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')
    fi

    print_info "Generate certificate untuk: $cn"

    openssl genrsa -out "$SSL_DIR/key.pem" 2048 &>/dev/null
    openssl req -new -x509 \
        -key "$SSL_DIR/key.pem" \
        -out "$SSL_DIR/cert.pem" \
        -days 3650 \
        -subj "/CN=${cn}" &>/dev/null

    cat "$SSL_DIR/key.pem" "$SSL_DIR/cert.pem" > "$SSL_DIR/stunnel.pem"

    chmod 600 "$SSL_DIR/key.pem"
    chmod 644 "$SSL_DIR/cert.pem"
    chmod 600 "$SSL_DIR/stunnel.pem"

    print_success "SSL Self-Signed"
}

# ============================================================
# MODE 2: Let's Encrypt Wildcard via Cloudflare DNS challenge
# Butuh: domain, Cloudflare API Token (Zone:DNS:Edit)
# ============================================================
setup_ssl_wildcard() {
    local domain="$1"
    local cf_token="$2"

    [[ -z "$domain" || -z "$cf_token" ]] && {
        print_error "Argumen tidak lengkap: setup_ssl_wildcard <domain> <cf_token>"
        return 1
    }

    print_section "Let's Encrypt Wildcard SSL"
    print_info "Domain   : *.${domain}"
    print_info "Provider : Cloudflare DNS Challenge"
    echo ""

    # Install certbot + plugin cloudflare
    print_info "Menginstall certbot + plugin Cloudflare..."
    apt-get install -y certbot python3-certbot-dns-cloudflare &>/dev/null
    if ! command -v certbot &>/dev/null; then
        print_error "Gagal install certbot!"
        return 1
    fi

    # Simpan Cloudflare credentials
    mkdir -p "$(dirname "$LE_CRED")"
    cat > "$LE_CRED" <<EOF
dns_cloudflare_api_token = ${cf_token}
EOF
    chmod 600 "$LE_CRED"

    # Request wildcard cert
    print_info "Meminta wildcard certificate... (bisa 30-60 detik)"
    local le_log="/tmp/certbot-zv.log"
    certbot certonly \
        --dns-cloudflare \
        --dns-cloudflare-credentials "$LE_CRED" \
        --dns-cloudflare-propagation-seconds 30 \
        -d "*.${domain}" \
        -d "${domain}" \
        --non-interactive \
        --agree-tos \
        --register-unsafely-without-email \
        --quiet \
        2>&1 | tee "$le_log" | grep -E "error|Error|warning|Congratulations|Successfully" || true

    local le_cert="/etc/letsencrypt/live/${domain}/fullchain.pem"
    local le_key="/etc/letsencrypt/live/${domain}/privkey.pem"

    if [[ ! -f "$le_cert" ]]; then
        print_error "Wildcard cert gagal dibuat! Cek log: $le_log"
        print_info "Fallback ke self-signed..."
        setup_ssl
        return 1
    fi

    print_ok "Wildcard certificate berhasil!"

    # Salin ke SSL_DIR supaya stunnel & service lain pakai path yang sama
    mkdir -p "$SSL_DIR"
    cp "$le_cert" "$SSL_DIR/cert.pem"
    cp "$le_key"  "$SSL_DIR/key.pem"
    cat "$SSL_DIR/key.pem" "$SSL_DIR/cert.pem" > "$SSL_DIR/stunnel.pem"

    chmod 600 "$SSL_DIR/key.pem"
    chmod 644 "$SSL_DIR/cert.pem"
    chmod 600 "$SSL_DIR/stunnel.pem"

    # Simpan info domain wildcard
    echo "$domain" > /etc/zv-manager/domain
    echo "wildcard" > /etc/zv-manager/ssl/ssl-type

    # Setup auto-renew cron (certbot renew sudah handle sendiri)
    _setup_ssl_renew_cron "$domain"

    print_success "Let's Encrypt Wildcard SSL (*.${domain})"
}


# ============================================================
# MODE 3: Let's Encrypt via HTTP-01 Challenge (tanpa Cloudflare)
# Butuh: domain pointing ke IP VPS, port 80 bisa diakses
# ============================================================
setup_ssl_letsencrypt() {
    local domain="${1:-$(cat /etc/zv-manager/domain 2>/dev/null)}"

    if [[ -z "$domain" || "$domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_error "Domain belum diset atau masih berupa IP!"
        print_info "Set domain dulu: echo 'namadomain.com' > /etc/zv-manager/domain"
        return 1
    fi

    print_section "Let's Encrypt SSL (HTTP-01 Challenge)"
    print_info "Domain: ${domain}"
    echo ""

    # Install certbot
    print_info "Menginstall certbot..."
    apt-get install -y certbot &>/dev/null
    if ! command -v certbot &>/dev/null; then
        print_error "Gagal install certbot!"
        return 1
    fi

    # Stop nginx sementara agar port 80 bebas untuk standalone challenge
    systemctl stop nginx &>/dev/null

    print_info "Meminta certificate... (10-30 detik)"
    certbot certonly         --standalone         --non-interactive         --agree-tos         --register-unsafely-without-email         -d "${domain}"         --quiet 2>/tmp/certbot-zv.log

    local le_cert="/etc/letsencrypt/live/${domain}/fullchain.pem"
    local le_key="/etc/letsencrypt/live/${domain}/privkey.pem"

    # Start nginx lagi
    systemctl start nginx &>/dev/null

    if [[ ! -f "$le_cert" ]]; then
        print_error "Certificate gagal! Pastikan domain pointing ke IP VPS ini."
        print_info "Cek log: cat /tmp/certbot-zv.log"
        print_info "Fallback ke self-signed..."
        setup_ssl
        return 1
    fi

    print_ok "Certificate Let's Encrypt berhasil!"

    # Salin ke SSL_DIR
    mkdir -p "$SSL_DIR"
    cp "$le_cert" "$SSL_DIR/cert.pem"
    cp "$le_key"  "$SSL_DIR/key.pem"
    cat "$SSL_DIR/key.pem" "$SSL_DIR/cert.pem" > "$SSL_DIR/stunnel.pem"
    chmod 600 "$SSL_DIR/key.pem" "$SSL_DIR/stunnel.pem"
    chmod 644 "$SSL_DIR/cert.pem"

    echo "$domain" > /etc/zv-manager/domain
    echo "letsencrypt" > /etc/zv-manager/ssl/ssl-type

    _setup_ssl_renew_cron "$domain"
    systemctl reload nginx &>/dev/null || systemctl restart nginx &>/dev/null

    print_success "Let's Encrypt SSL aktif untuk ${domain}"
}

# ============================================================
# Cek apakah cert yang aktif adalah Let's Encrypt
# ============================================================
is_letsencrypt() {
    local t; t=$(cat /etc/zv-manager/ssl/ssl-type 2>/dev/null)
    [[ "$t" == "wildcard" || "$t" == "letsencrypt" ]]
}

# ============================================================
# Renew wildcard cert (dipanggil dari cron atau manual)
# ============================================================
renew_ssl_wildcard() {
    if ! is_letsencrypt; then
        print_info "SSL bukan Let's Encrypt, skip renew."
        return 0
    fi

    print_info "Renew Let's Encrypt certificate..."
    certbot renew --quiet 2>/dev/null

    local domain
    domain=$(cat /etc/zv-manager/domain 2>/dev/null)
    # Coba path langsung dulu, lalu fallback ke first available
    local le_cert="/etc/letsencrypt/live/${domain}/fullchain.pem"
    local le_key="/etc/letsencrypt/live/${domain}/privkey.pem"
    # Jika tidak ada, cari cert pertama yang tersedia
    if [[ ! -f "$le_cert" ]]; then
        le_cert=$(find /etc/letsencrypt/live/ -name "fullchain.pem" 2>/dev/null | head -1)
        le_key=$(find /etc/letsencrypt/live/ -name "privkey.pem" 2>/dev/null | head -1)
    fi

    if [[ -f "$le_cert" ]]; then
        cp "$le_cert" "$SSL_DIR/cert.pem"
        cp "$le_key"  "$SSL_DIR/key.pem"
        cat "$SSL_DIR/key.pem" "$SSL_DIR/cert.pem" > "$SSL_DIR/stunnel.pem"
        chmod 600 "$SSL_DIR/key.pem"
        chmod 600 "$SSL_DIR/stunnel.pem"

        systemctl reload nginx &>/dev/null || systemctl restart nginx &>/dev/null
        print_ok "Certificate berhasil diperbarui!"
    else
        print_error "Renew gagal! Cert tidak ditemukan."
        return 1
    fi
}

# ============================================================
# Setup cron renew otomatis
# ============================================================
_setup_ssl_renew_cron() {
    cat > /etc/cron.d/zv-ssl-renew <<'CRONEOF'
# ZV-Manager - Auto Renew Let's Encrypt (tiap hari jam 03:00)
0 3 * * * root /bin/bash /etc/zv-manager/core/ssl.sh renew >> /var/log/zv-manager/ssl-renew.log 2>&1
CRONEOF
    service cron restart &>/dev/null
}

# ============================================================
# Regenerate (self-signed atau renew LE)
# ============================================================
regenerate_ssl() {
    if is_letsencrypt; then
        renew_ssl_wildcard
    else
        setup_ssl
    fi

    systemctl reload nginx &>/dev/null || systemctl restart nginx &>/dev/null
    print_ok "SSL Certificate diperbarui & service di-reload"
}

# ============================================================
# Entry point kalau dipanggil langsung (dari cron)
# ============================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    source /etc/zv-manager/utils/colors.sh 2>/dev/null || true
    source /etc/zv-manager/utils/logger.sh 2>/dev/null || true
    case "$1" in
        renew)       renew_ssl_wildcard ;;
        letsencrypt) setup_ssl_letsencrypt "$2" ;;
    esac
fi
