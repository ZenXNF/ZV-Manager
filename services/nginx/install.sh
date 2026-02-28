#!/bin/bash
# ============================================================
#   ZV-Manager - Nginx Installer & Configurator
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/config.conf

install_nginx() {
    print_section "Install & Konfigurasi Nginx"

    # Install nginx dengan stream module
    apt-get install -y nginx libnginx-mod-stream &>/dev/null
    systemctl stop nginx &>/dev/null

    local domain
    domain=$(cat /etc/zv-manager/domain)

    local ssl_cert="/etc/zv-manager/ssl/cert.pem"
    local ssl_key="/etc/zv-manager/ssl/key.pem"

    # Hapus config default
    rm -f /etc/nginx/sites-enabled/default
    rm -f /etc/nginx/sites-available/default
    rm -f /etc/nginx/conf.d/*.conf

    # --- nginx.conf utama dengan stream block ---
    # stream{} dipakai untuk port 443 agar HTTP CONNECT bisa lewat (level TCP)
    # http{}  dipakai untuk port 80 WS biasa dan port info web
    cat > /etc/nginx/nginx.conf <<NGINXMAIN
user www-data;
worker_processes auto;
pid /var/run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 1024;
    multi_accept on;
}

# ── HTTP block: WS port 80 + web info port 81 ──
http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;
    client_max_body_size 32M;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    gzip on;
    gzip_vary on;
    gzip_comp_level 5;
    gzip_types text/plain application/json application/javascript text/css;

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    map \$http_upgrade \$connection_upgrade {
        default upgrade;
        ''      close;
    }

    # WS HTTP port 80 — forward ke ws-proxy
    server {
        listen ${WS_PORT};
        server_name ${domain};

        location / {
            proxy_pass http://127.0.0.1:8880;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \$connection_upgrade;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
            proxy_buffering off;
        }
    }

    # Web info page port 81
    server {
        listen ${NGINX_PORT};
        server_name ${domain};
        root /var/www/zv-manager;
        index index.html;
        location / {
            try_files \$uri \$uri/ =404;
        }
    }
}

# ── STREAM block: port 443 SSL ──
# Stream bekerja di level TCP — bisa handle HTTP CONNECT langsung
# HTTP Custom, HTTP Injector, NapsternetV semua pakai CONNECT method
stream {
    # SSL termination di level stream
    server {
        listen ${WSS_PORT} ssl;

        ssl_certificate     ${ssl_cert};
        ssl_certificate_key ${ssl_key};
        ssl_protocols       TLSv1.2 TLSv1.3;
        ssl_ciphers         HIGH:!aNULL:!MD5;
        ssl_session_cache   shared:SSL:10m;
        ssl_session_timeout 10m;
        ssl_handshake_timeout 10s;

        # Setelah SSL terputus, forward raw TCP ke ws-proxy
        # ws-proxy yang akan handle baik WebSocket maupun HTTP CONNECT
        proxy_pass 127.0.0.1:8880;
        proxy_timeout 3600s;
        proxy_connect_timeout 10s;
    }
}
NGINXMAIN

    # Buat direktori web
    mkdir -p /var/www/zv-manager
    chown -R www-data:www-data /var/www/zv-manager

    # Test dan start nginx
    if nginx -t &>/dev/null; then
        systemctl enable nginx &>/dev/null
        systemctl start nginx &>/dev/null
        print_success "Nginx"
    else
        print_error "Nginx config error! Cek: nginx -t"
        nginx -t
    fi
}
