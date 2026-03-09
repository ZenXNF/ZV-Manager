#!/bin/bash
# ============================================================
#   ZV-Manager - Nginx Installer & Configurator
#   Port 80  : SSH WS + VMess WS (non-SSL)
#   Port 443 : SSH WS + VMess WS/gRPC + Status/API (SSL)
#   Stunnel dihapus — nginx langsung handle SSL di 443
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/config.conf

WS_PORT=${WS_PORT:-80}
WSS_PORT=${WSS_PORT:-443}
SSL_CERT="/etc/zv-manager/ssl/cert.pem"
SSL_KEY="/etc/zv-manager/ssl/key.pem"

install_nginx() {
    print_section "Install & Konfigurasi Nginx"

    apt-get install -y nginx &>/dev/null
    systemctl stop nginx &>/dev/null

    local domain
    domain=$(cat /etc/zv-manager/domain)

    rm -f /etc/nginx/sites-enabled/default
    rm -f /etc/nginx/sites-available/default
    rm -f /etc/nginx/conf.d/*.conf

    # Buat direktori web
    mkdir -p /var/www/zv-manager/api
    chown -R www-data:www-data /var/www/zv-manager

    cat > /etc/nginx/nginx.conf <<NGINXMAIN
user www-data;
worker_processes auto;
pid /var/run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 1024;
    multi_accept on;
}

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

    # ──────────────────────────────────────────────────────
    # Port 80 — non-SSL (SSH WS + VMess WS)
    # catch-all untuk bug host / wildcard host
    # ──────────────────────────────────────────────────────
    server {
        listen ${WS_PORT} default_server;
        server_name _;

        location /vmess {
            proxy_pass http://127.0.0.1:10001;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \$connection_upgrade;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
            proxy_buffering off;
        }

        # ── Status Page via HTTP ────────────────────────────
        location /status {
            root /var/www/zv-manager;
            try_files /index.html =404;
            add_header Cache-Control "no-cache";
        }

        location = /favicon.ico {
            root /var/www/zv-manager;
            log_not_found off;
        }

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

    # ──────────────────────────────────────────────────────
    # Port 443 — SSL (SSH WS + VMess WS/gRPC + Status + API)
    # Menggantikan: stunnel port 443 + nginx port 8443 + nginx port 81
    # ──────────────────────────────────────────────────────
    server {
        listen ${WSS_PORT} ssl http2 default_server;
        server_name ${domain} _;

        ssl_certificate     ${SSL_CERT};
        ssl_certificate_key ${SSL_KEY};
        ssl_protocols       TLSv1.2 TLSv1.3;
        ssl_ciphers         HIGH:!aNULL:!MD5;
        ssl_session_cache   shared:SSL:10m;
        ssl_session_timeout 10m;

        # ── VMess gRPC ──────────────────────────────────
        location /vmess-grpc {
            grpc_pass grpc://127.0.0.1:10002;
            grpc_set_header Host \$host;
            grpc_read_timeout 3600s;
            grpc_send_timeout 3600s;
        }

        # ── VMess WebSocket (TLS) ───────────────────────
        location /vmess {
            proxy_pass http://127.0.0.1:10001;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \$connection_upgrade;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
            proxy_buffering off;
        }

        # ── Status Page — akses via root / maupun /status ──
        location /status {
            alias /var/www/zv-manager/;
            index index.html;
            try_files \$uri \$uri/ index.html;
        }

        location = / {
            root /var/www/zv-manager;
            index index.html;
            try_files /index.html =404;
            add_header Cache-Control "no-cache";
        }

        # ── Dashboard Akun VMess ─────────────────────────
        location /api/ {
            alias /var/www/zv-manager/api/;
            add_header Content-Type text/html;
        }

        # ── SSH WebSocket (TLS) — catch-all ─────────────
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
}
NGINXMAIN

    if nginx -t &>/dev/null; then
        systemctl enable nginx &>/dev/null
        systemctl start nginx &>/dev/null

        # Nonaktifkan stunnel — nginx sudah handle 443
        systemctl stop zv-stunnel &>/dev/null
        systemctl disable zv-stunnel &>/dev/null

        print_success "Nginx (SSH+VMess WS port ${WS_PORT} | SSH+VMess WS/gRPC+Status+API port ${WSS_PORT} SSL)"
    else
        print_error "Nginx config error! Cek: nginx -t"
        nginx -t
    fi
}
