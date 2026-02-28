#!/bin/bash
# ============================================================
#   ZV-Manager - Uninstaller
# ============================================================

if [[ "$EUID" -ne 0 ]]; then
    echo "[ERROR] Jalankan sebagai root!"
    exit 1
fi

echo ""
echo "⚠️  PERINGATAN: Ini akan menghapus ZV-Manager dan semua konfigurasinya!"
echo ""
read -rp "Yakin ingin uninstall? [y/n]: " confirm
[[ ! "$confirm" =~ ^[Yy]$ ]] && echo "Dibatalkan." && exit 0

echo "[ INFO ] Menghentikan semua service ZV-Manager..."
systemctl stop zv-ws zv-wss zv-udp zv-badvpn 2>/dev/null
systemctl disable zv-ws zv-wss zv-udp zv-badvpn 2>/dev/null
rm -f /etc/systemd/system/zv-*.service
systemctl daemon-reload

echo "[ INFO ] Menghapus cron jobs..."
rm -f /etc/cron.d/zv-*

echo "[ INFO ] Menghapus file ZV-Manager..."
rm -rf /etc/zv-manager
rm -f /usr/local/bin/menu
rm -f /usr/local/bin/zv-ws-proxy.py

echo "[ INFO ] Membersihkan .profile..."
cat > /root/.profile <<'EOF'
if [ "$BASH" ]; then
    if [ -f ~/.bashrc ]; then
        . ~/.bashrc
    fi
fi
mesg n 2>/dev/null || true
EOF

echo ""
echo "✔ ZV-Manager berhasil diuninstall."
echo ""
