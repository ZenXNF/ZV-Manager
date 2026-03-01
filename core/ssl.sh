#!/bin/bash
# ============================================================
#   ZV-Manager - SSL Certificate Setup
#   Self-signed, tanpa identitas spesifik
# ============================================================

source /etc/zv-manager/utils/colors.sh 2>/dev/null || true
source /etc/zv-manager/utils/logger.sh 2>/dev/null || true

SSL_DIR="/etc/zv-manager/ssl"

setup_ssl() {
    print_section "Generate SSL Certificate (Self-Signed)"

    mkdir -p "$SSL_DIR"

    # Cari domain dari servers/*.conf yang match IP lokal
    # Kalau ada → pakai domain sebagai CN (lebih proper)
    # Kalau tidak → fallback ke IP
    local local_ip
    local_ip=$(cat /etc/zv-manager/domain 2>/dev/null)

    local cn="$local_ip"
    for conf in /etc/zv-manager/servers/*.conf; do
        [[ -f "$conf" ]] || continue
        unset IP DOMAIN
        source "$conf"
        if [[ "$IP" == "$local_ip" && -n "$DOMAIN" && "$DOMAIN" != "$local_ip" ]]; then
            cn="$DOMAIN"
            break
        fi
    done

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

# Fungsi untuk regenerate SSL dengan domain terbaru
# Dipanggil dari menu system → "Perbarui SSL Certificate"
regenerate_ssl() {
    local old_cert_info
    old_cert_info=$(openssl x509 -in "$SSL_DIR/cert.pem" -noout -subject 2>/dev/null)

    setup_ssl

    # Restart nginx agar pakai cert baru
    systemctl reload nginx &>/dev/null || systemctl restart nginx &>/dev/null

    print_ok "SSL Certificate diperbarui!"
    print_ok "Nginx di-reload dengan cert baru"
}
