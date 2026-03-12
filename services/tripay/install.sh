#!/bin/bash
# ============================================================
#   ZV-Manager - Install Tripay Webhook Service
# ============================================================

BASE="/etc/zv-manager"
TRIPAY_DIR="${BASE}/services/tripay"
CONF="${BASE}/tripay.conf"
LOG="/var/log/zv-manager/tripay.log"

source "${BASE}/utils/colors.sh"    2>/dev/null || true
source "${BASE}/utils/helpers.sh"   2>/dev/null || true

_ok()  { echo -e "  ${BGREEN}✔${NC}  $1"; }
_err() { echo -e "  ${BRED}✘${NC}  $1"; }
_info(){ echo -e "  ${BYELLOW}→${NC}  $1"; }

echo ""
echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
echo -e " │         ${BWHITE}SETUP TRIPAY PAYMENT GATEWAY${NC}          │"
echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
echo ""

# ── Buat config tripay.conf jika belum ada ───────────────────
if [[ ! -f "$CONF" ]]; then
    cat > "$CONF" <<'CONFEOF'
# ── Tripay Configuration ──────────────────────────────────────
# Isi dengan data dari dashboard Tripay (https://tripay.co.id)

# API Key dari menu Merchant → Akun → API
TRIPAY_API_KEY=

# Private Key dari menu Merchant → Akun → API
TRIPAY_PRIVATE_KEY=

# Kode merchant (contoh: T12345)
TRIPAY_MERCHANT_CODE=

# Mode: sandbox (untuk testing) atau production
TRIPAY_MODE=sandbox

# Fee QRIS: 0 = ditanggung merchant, 1 = ditanggung customer
TRIPAY_FEE_CUSTOMER=0

# Nominal preset top up (pisah koma, satuan Rupiah)
# Min Tripay: 10000
TRIPAY_NOMINAL_PRESET=10000,20000,50000,100000
CONFEOF
    _ok "Config dibuat: ${CONF}"
else
    _info "Config sudah ada: ${CONF}"
fi

# ── Copy file Python ke direktori ─────────────────────────────
mkdir -p "$TRIPAY_DIR"
cp "$(dirname "$0")/tripay_api.py" "${TRIPAY_DIR}/tripay_api.py"
cp "$(dirname "$0")/webhook.py"    "${TRIPAY_DIR}/webhook.py"
chmod +x "${TRIPAY_DIR}/webhook.py"
_ok "File webhook disalin ke ${TRIPAY_DIR}"

# ── Buat symlink tripay_api agar bisa diimport dari bot ───────
ln -sf "${TRIPAY_DIR}/tripay_api.py" \
    "${BASE}/services/telegram/tripay_api.py" 2>/dev/null
_ok "Symlink tripay_api.py → services/telegram/"

# ── Systemd service ───────────────────────────────────────────
cat > /etc/systemd/system/zv-tripay.service <<EOF
[Unit]
Description=ZV-Manager Tripay Webhook
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${TRIPAY_DIR}/webhook.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable zv-tripay &>/dev/null
systemctl restart zv-tripay
sleep 2

if systemctl is-active --quiet zv-tripay; then
    _ok "Service zv-tripay aktif"
else
    _err "Service zv-tripay gagal start — cek: journalctl -u zv-tripay -n 20"
fi

# ── Tambah nginx route /tripay/callback ───────────────────────
NGINX_TRIPAY="/etc/nginx/conf.d/zv-tripay.conf"
DOMAIN=$(cat "${BASE}/domain" 2>/dev/null | tr -d '[:space:]')

cat > "$NGINX_TRIPAY" <<EOF
# ZV-Manager Tripay Webhook
server {
    listen 80;
    server_name ${DOMAIN:-_};

    location /tripay/ {
        proxy_pass         http://127.0.0.1:18099;
        proxy_http_version 1.1;
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_read_timeout 30s;
    }
}
EOF

nginx -t &>/dev/null && systemctl reload nginx &>/dev/null && _ok "Nginx route /tripay/ aktif" \
    || _err "Nginx reload gagal — cek config"

# ── Log file ──────────────────────────────────────────────────
touch "$LOG"
chmod 644 "$LOG"

echo ""
echo -e "${BGREEN} ✔ Tripay webhook siap!${NC}"
echo ""
echo -e "  ${BWHITE}Langkah selanjutnya:${NC}"
echo -e "  ${BYELLOW}1.${NC} Isi ${BCYAN}${CONF}${NC} dengan API Key, Private Key, Merchant Code"
echo -e "  ${BYELLOW}2.${NC} Ganti ${BYELLOW}TRIPAY_MODE=production${NC} setelah testing selesai"
echo -e "  ${BYELLOW}3.${NC} Di dashboard Tripay, set Callback URL ke:"
echo -e "     ${BGREEN}https://${DOMAIN:-yourdomain.com}/tripay/callback${NC}"
echo -e "  ${BYELLOW}4.${NC} Restart service: ${BCYAN}systemctl restart zv-tripay${NC}"
echo ""
