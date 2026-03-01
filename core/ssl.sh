#!/bin/bash
# ============================================================
#   ZV-Manager - SSL Certificate Setup
#   Selalu self-signed — domain hanya untuk SSH server
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh

SSL_DIR="/etc/zv-manager/ssl"

setup_ssl() {
    print_section "Generate SSL Certificate (Self-Signed)"

    mkdir -p "$SSL_DIR"

    local host
    host=$(cat /etc/zv-manager/domain)

    print_info "Generate certificate untuk: $host"

    openssl genrsa -out "$SSL_DIR/key.pem" 2048 &>/dev/null
    openssl req -new -x509 \
        -key "$SSL_DIR/key.pem" \
        -out "$SSL_DIR/cert.pem" \
        -days 3650 \
        -subj "/C=ID/ST=Indonesia/L=Jakarta/O=ZV-Manager/CN=$host" &>/dev/null

    cat "$SSL_DIR/key.pem" "$SSL_DIR/cert.pem" > "$SSL_DIR/stunnel.pem"

    chmod 600 "$SSL_DIR/key.pem"
    chmod 644 "$SSL_DIR/cert.pem"
    chmod 600 "$SSL_DIR/stunnel.pem"

    print_success "SSL Self-Signed"
}
