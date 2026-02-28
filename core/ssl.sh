#!/bin/bash
# ============================================================
#   ZV-Manager - SSL Certificate Setup
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh

SSL_DIR="/etc/zv-manager/ssl"

generate_self_signed() {
    print_section "Generate Self-Signed SSL Certificate"

    mkdir -p "$SSL_DIR"

    local domain
    domain=$(cat /etc/zv-manager/domain)

    openssl genrsa -out "$SSL_DIR/key.pem" 2048 &>/dev/null
    openssl req -new -x509 \
        -key "$SSL_DIR/key.pem" \
        -out "$SSL_DIR/cert.pem" \
        -days 3650 \
        -subj "/C=ID/ST=Indonesia/L=Jakarta/O=ZV-Manager/CN=$domain" &>/dev/null

    # Gabungkan untuk stunnel
    cat "$SSL_DIR/key.pem" "$SSL_DIR/cert.pem" > "$SSL_DIR/stunnel.pem"

    chmod 600 "$SSL_DIR/key.pem"
    chmod 644 "$SSL_DIR/cert.pem"
    chmod 600 "$SSL_DIR/stunnel.pem"

    print_success "SSL Self-Signed"
}

generate_certbot() {
    print_section "Generate SSL Certificate via Certbot"

    local domain
    domain=$(cat /etc/zv-manager/domain)

    # Install certbot
    apt-get install -y certbot &>/dev/null

    # Stop nginx dulu supaya port 80 free
    systemctl stop nginx &>/dev/null

    # Generate certificate
    certbot certonly \
        --standalone \
        --non-interactive \
        --agree-tos \
        --register-unsafely-without-email \
        -d "$domain" &>/dev/null

    if [[ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then
        mkdir -p "$SSL_DIR"
        # Symlink ke lokasi ZV-Manager
        ln -sf "/etc/letsencrypt/live/$domain/fullchain.pem" "$SSL_DIR/cert.pem"
        ln -sf "/etc/letsencrypt/live/$domain/privkey.pem" "$SSL_DIR/key.pem"
        # Buat stunnel.pem
        cat "/etc/letsencrypt/live/$domain/privkey.pem" \
            "/etc/letsencrypt/live/$domain/fullchain.pem" > "$SSL_DIR/stunnel.pem"
        chmod 600 "$SSL_DIR/stunnel.pem"
        print_success "SSL Certbot (Let's Encrypt)"
    else
        print_warning "Certbot gagal, fallback ke self-signed..."
        generate_self_signed
    fi

    # Restart nginx
    systemctl start nginx &>/dev/null
}

setup_ssl() {
    clear
    print_section "Setup SSL"

    local domain
    domain=$(cat /etc/zv-manager/domain)

    # Kalau pakai IP address, langsung self-signed
    if [[ "$domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_info "Menggunakan IP Address, generate self-signed certificate..."
        generate_self_signed
        return
    fi

    echo ""
    echo -e "  ${BWHITE}Pilih tipe SSL:${NC}"
    echo ""
    echo -e "  ${BGREEN}[1]${NC} Let's Encrypt (Certbot) — Gratis, perlu domain valid"
    echo -e "  ${BGREEN}[2]${NC} Self-Signed — Langsung jadi, cocok untuk IP/domain lokal"
    echo ""
    read -rp "  Pilihan [1/2]: " choice

    case $choice in
        1) generate_certbot ;;
        2) generate_self_signed ;;
        *) print_error "Pilihan tidak valid!"; setup_ssl ;;
    esac
}
