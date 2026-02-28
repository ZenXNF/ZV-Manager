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

    local ssl_cert="/etc/zv-manager/ssl/cert.pem"
    local ssl_key="/etc/zv-manager/ssl/key.pem"

    # Hapus config default
    rm -f /etc/nginx/sites-enabled/default
    rm -f /etc/nginx/sites-available/default

    # --- nginx.conf utama ---
    cat > /etc/nginx/nginx.conf <<'NGINXMAIN'
user www-data;
worker_processes auto;
pid /var/run/nginx.pid;

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

    # Cloudflare IPs
    set_real_ip_from 103.21.244.0/22;
    set_real_ip_from 103.22.200.0/22;
    set_real_ip_from 103.31.4.0/22;
    set_real_ip_from 141.101.64.0/18;
    set_real_ip_from 108.162.192.0/18;
    set_real_ip_from 190.93.240.0/20;
    set_real_ip_from 188.114.96.0/20;
    set_real_ip_from 197.234.240.0/22;
    set_real_ip_from 198.41.128.0/17;
    set_real_ip_from 162.158.0.0/15;
    set_real_ip_from 104.16.0.0/13;
    set_real_ip_from 104.24.0.0/14;
    real_ip_header CF-Connecting-IP;

    include /etc/nginx/conf.d/*.conf;
}
NGINXMAIN

    # --- Config SSL WebSocket + HTTP CONNECT untuk port 443 ---
    cat > /etc/nginx/conf.d/zv-wss.conf <<EOF
# ZV-Manager - WebSocket SSL (HTTPS) + HTTP CONNECT Tunnel
server {
    listen ${WSS_PORT} ssl;
    server_name ${domain};

    ssl_certificate     ${ssl_cert};
    ssl_certificate_key ${ssl_key};
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 10m;

    # WebSocket SSH & HTTP CONNECT — semua forward ke ws-proxy
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

# ZV-Manager - HTTP WebServer info page
server {
    listen ${NGINX_PORT};
    server_name ${domain};
    root /var/www/zv-manager;
    index index.html;
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

    # Map upgrade header untuk WebSocket
    cat > /etc/nginx/conf.d/zv-map.conf <<'MAPEOF'
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
MAPEOF

    # Buat direktori web
    mkdir -p /var/www/zv-manager
    chown -R www-data:www-data /var/www/zv-manager

    # Test dan start nginx
    nginx -t &>/dev/null && systemctl enable nginx &>/dev/null && systemctl start nginx &>/dev/null

    print_success "Nginx"
}
