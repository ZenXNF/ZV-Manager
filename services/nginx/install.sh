#!/bin/bash
# ============================================================
#   ZV-Manager - Nginx Installer & Configurator
#   Support wildcard host / bug host — catch-all server_name
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/config.conf

# Fallback port default jika config kosong
WS_PORT=${WS_PORT:-80}
WSS_PORT=${WSS_PORT:-443}
NGINX_PORT=${NGINX_PORT:-81}

install_nginx() {
    print_section "Install & Konfigurasi Nginx"

    apt-get install -y nginx &>/dev/null
    systemctl stop nginx &>/dev/null

    local domain
    domain=$(cat /etc/zv-manager/domain)

    # Hapus config default
    rm -f /etc/nginx/sites-enabled/default
    rm -f /etc/nginx/sites-available/default
    rm -f /etc/nginx/conf.d/*.conf

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
    # Port 80 — WS non-SSL, catch-all host header
    # Menerima koneksi dengan Host: apapun (wildcard / bug host)
    # Contoh: free.facebook.com, cdn.apapun.com, dll
    # ──────────────────────────────────────────────────────
    server {
        listen ${WS_PORT} default_server;
        server_name _;

        # VMess WebSocket
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

        # SSH WebSocket (catch-all)
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

    # VMess gRPC (port 8443, TLS via stunnel/cert langsung)
    server {
        listen 8443 ssl http2;
        server_name ${domain} _;
        ssl_certificate /etc/zv-manager/ssl/cert.pem;
        ssl_certificate_key /etc/zv-manager/ssl/key.pem;
        ssl_protocols TLSv1.2 TLSv1.3;

        location /vmess-grpc {
            grpc_pass grpc://127.0.0.1:10002;
            grpc_set_header Host \$host;
        }

        # VMess WS TLS juga lewat sini
        location /vmess {
            proxy_pass http://127.0.0.1:10001;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \$connection_upgrade;
            proxy_set_header Host \$host;
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
            proxy_buffering off;
        }
    }

    # ──────────────────────────────────────────────────────
    # Port 81 — halaman info web (domain spesifik)
    # ──────────────────────────────────────────────────────
    server {
        listen ${NGINX_PORT};
        server_name ${domain} _;
        root /var/www/zv-manager;
        index index.html;
        location / {
            try_files \$uri \$uri/ =404;
        }
    }
}
NGINXMAIN

    mkdir -p /var/www/zv-manager
    chown -R www-data:www-data /var/www/zv-manager

    if nginx -t &>/dev/null; then
        systemctl enable nginx &>/dev/null
        systemctl start nginx &>/dev/null
        print_success "Nginx (SSH WS port ${WS_PORT}, VMess WS port ${WS_PORT}/vmess, VMess TLS port 8443, info port ${NGINX_PORT})"
    else
        print_error "Nginx config error! Cek: nginx -t"
        nginx -t
    fi
}
