#!/bin/bash
# ============================================================
#   ZV-Manager - Nginx Installer & Configurator
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/config.conf

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

    # Nginx hanya handle HTTP (port 80 WS + port 81 info)
    # Port 443 SSL diserahkan sepenuhnya ke stunnel → ws-proxy
    # Tidak perlu stream module lagi
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

    # Port 80 — WS non-SSL, forward ke ws-proxy
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

    # Port 81 — halaman info web
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
NGINXMAIN

    mkdir -p /var/www/zv-manager
    chown -R www-data:www-data /var/www/zv-manager

    if nginx -t &>/dev/null; then
        systemctl enable nginx &>/dev/null
        systemctl start nginx &>/dev/null
        print_success "Nginx"
    else
        print_error "Nginx config error! Cek: nginx -t"
        nginx -t
    fi
}
