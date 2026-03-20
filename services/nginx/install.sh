#!/bin/bash
# ============================================================
#   ZV-Manager - Nginx Installer & Configurator
#
#   Arsitektur:
#   Port 80  (stream TCP)  → ws-proxy:8880  ← HTTP Custom non-SSL
#   Port 443 (ssl_preread) → ws-proxy:8881 (TLS, bug SNI SSH+VMess)
#                          → nginx:18443 → ws-proxy:8880 (SNI domain)
#   Port 8080 (HTTP)       → VMess WS + Status Page + /api/
#   Port 8443 (HTTPS)      → VMess WS/gRPC + Status Page
#   Port 18443 (TLS)       → ws-proxy:8880 (SSH via domain SNI)
#
#   ws-proxy routing (setelah TLS):
#     CONNECT       → SSH (port 22/109/143/500/40000)
#     GET /vmess WS → Xray:10001
#     GET browser   → nginx:8080
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/config.conf

SSL_CERT="/etc/zv-manager/ssl/cert.pem"
SSL_KEY="/etc/zv-manager/ssl/key.pem"

install_nginx() {
    print_section "Install & Konfigurasi Nginx"

    apt-get install -y nginx libnginx-mod-stream &>/dev/null
    systemctl stop nginx &>/dev/null

    local domain
    domain=$(cat /etc/zv-manager/domain 2>/dev/null)

    rm -f /etc/nginx/sites-enabled/default
    rm -f /etc/nginx/sites-available/default
    rm -f /etc/nginx/conf.d/*.conf

    mkdir -p /var/www/zv-manager/api
    chown -R www-data:www-data /var/www/zv-manager

    # Cek apakah stream module tersedia
    local stream_mod=""

    cat > /etc/nginx/nginx.conf << NGINXMAIN
user www-data;
worker_processes auto;
pid /var/run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 1024;
    multi_accept on;
}

# ── STREAM: Port 80 & 443 ─────────────────────────────────────
stream {
    # Port 80 → ws-proxy (non-SSL, HTTP Custom tanpa SSL)
    server {
        listen 80;
        proxy_pass 127.0.0.1:8880;
        proxy_protocol on;
        proxy_timeout 3600s;
        proxy_connect_timeout 10s;
    }

    # Port 443 → ssl_preread (TIDAK terminate TLS)
    # SNI = domain server       → nginx:18443 → ws-proxy:8880 → SSH/VMess/browser
    # SNI = status domain       → ws-proxy:8881 (TLS) → nginx:8080 status page
    # SNI = lain (bug XL/dll)   → ws-proxy:8881 (TLS) → SSH atau VMess
    map \$ssl_preread_server_name \$backend_443 {
        ${domain}   127.0.0.1:18443;
        default     127.0.0.1:8881;
    }
    server {
        listen 443;
        ssl_preread on;
        proxy_pass \$backend_443;
        proxy_timeout 3600s;
        proxy_connect_timeout 10s;
    }

    # Port 18443 → TLS terminate → ws-proxy (untuk SSH via domain SNI)
    server {
        listen 18443 ssl;
        ssl_certificate     ${SSL_CERT};
        ssl_certificate_key ${SSL_KEY};
        ssl_protocols       TLSv1.2 TLSv1.3;
        ssl_ciphers         HIGH:!aNULL:!MD5;
        ssl_session_cache   shared:SSLSTREAM:10m;
        ssl_session_timeout 10m;
        proxy_pass          127.0.0.1:8880;
        proxy_protocol      on;
        proxy_timeout       3600s;
        proxy_connect_timeout 10s;
    }
}

# ── HTTP: Port 8080 & 8443 — VMess WS/gRPC + Status Page ─────
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

    # ── Port 8080 — VMess WS (non-SSL) + Status Page ─────────
    server {
        listen 8080 default_server;
        server_name _;

        # Status page
        location /status {
            root /var/www/zv-manager;
            try_files /index.html =404;
            add_header Cache-Control "no-cache";
        }
        location = / {
            root /var/www/zv-manager;
            index index.html;
            try_files /index.html =404;
        }
        location = /favicon.ico {
            root /var/www/zv-manager;
            log_not_found off;
        }

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

        # VLESS WebSocket
        location /vless {
            proxy_pass http://127.0.0.1:10004;
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

    # ── Port 8443 — VMess WS/gRPC (SSL) + Status Page ────────
    server {
        listen 8443 ssl http2 default_server;
        server_name ${domain} _;

        ssl_certificate     ${SSL_CERT};
        ssl_certificate_key ${SSL_KEY};
        ssl_protocols       TLSv1.2 TLSv1.3;
        ssl_ciphers         HIGH:!aNULL:!MD5;
        ssl_session_cache   shared:SSL:10m;
        ssl_session_timeout 10m;

        # Status page
        location /status {
            root /var/www/zv-manager;
            try_files /index.html =404;
            add_header Cache-Control "no-cache";
        }
        location = / {
            root /var/www/zv-manager;
            index index.html;
            try_files /index.html =404;
        }

        # VMess WebSocket (TLS)
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

        # VLESS WebSocket (TLS)
        location /vless {
            proxy_pass http://127.0.0.1:10004;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \$connection_upgrade;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
            proxy_buffering off;
        }

        # VMess gRPC (TLS)
        location /vmess-grpc {
            grpc_pass grpc://127.0.0.1:10002;
            grpc_set_header Host \$host;
            grpc_read_timeout 3600s;
            grpc_send_timeout 3600s;
        }

        # VLESS gRPC (TLS)
        location /vless-grpc {
            grpc_pass grpc://127.0.0.1:10005;
            grpc_set_header Host \$host;
            grpc_read_timeout 3600s;
            grpc_send_timeout 3600s;
        }

    }
}
NGINXMAIN

    if nginx -t &>/dev/null; then
        systemctl enable nginx &>/dev/null
        systemctl start nginx &>/dev/null
        systemctl stop zv-stunnel &>/dev/null
        systemctl disable zv-stunnel &>/dev/null
        print_success "Nginx (SSH stream :80/:443 | VMess+Status HTTP :8080/:8443)"
    else
        print_error "Nginx config error! Cek: nginx -t"
        nginx -t
    fi
}
