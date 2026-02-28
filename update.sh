#!/bin/bash
# ============================================================
#   ZV-Manager - Updater
#   wget -q https://raw.githubusercontent.com/ZenXNF/ZV-Manager/main/update.sh && bash update.sh
# ============================================================

if [[ "$EUID" -ne 0 ]]; then
    echo "[ERROR] Jalankan sebagai root!"
    exit 1
fi

echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║       Z V - M A N A G E R           ║"
echo "  ║  Updater                             ║"
echo "  ╚══════════════════════════════════════╝"
echo ""

# Cek git tersedia
if ! command -v git &>/dev/null; then
    echo "[ INFO ] Menginstall git..."
    apt-get install -y git &>/dev/null
fi

# Cek apakah repo sudah ada
if [[ ! -d /root/ZV-Manager/.git ]]; then
    echo "[ INFO ] Repo belum ada, clone fresh..."
    rm -rf /root/ZV-Manager
    git clone -q https://github.com/ZenXNF/ZV-Manager.git /root/ZV-Manager
else
    echo "[ INFO ] Mengambil update terbaru..."
    cd /root/ZV-Manager
    git fetch -q origin
    git reset -q --hard origin/main
fi

if [[ ! -d /root/ZV-Manager ]]; then
    echo "[ERROR] Gagal mengunduh update!"
    exit 1
fi

cd /root/ZV-Manager

echo "[ INFO ] Menyalin file ke /etc/zv-manager..."
find . -name "*.sh" -exec chmod +x {} \;
find . -name "*.py" -exec chmod +x {} \;
cp -r . /etc/zv-manager/

echo "[ INFO ] Restart services..."
for svc in nginx zv-ws zv-wss zv-udp zv-badvpn; do
    if systemctl is-enabled "$svc" &>/dev/null; then
        systemctl restart "$svc" &>/dev/null && echo " ✔  $svc restarted" || echo " ✘  $svc gagal restart"
    fi
done

echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║      UPDATE SELESAI!                 ║"
echo "  ╚══════════════════════════════════════╝"
echo ""
echo "  Ketik 'menu' untuk membuka ZV-Manager"
echo ""
