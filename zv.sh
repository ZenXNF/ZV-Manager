#!/bin/bash
# ============================================================
#   ZV-Manager - One-liner Installer
#   wget -q https://raw.githubusercontent.com/ZenXNF/ZV-Manager/main/zv.sh && chmod +x zv.sh && bash zv.sh
# ============================================================

if [[ "$EUID" -ne 0 ]]; then
    echo "[ERROR] Jalankan sebagai root!"
    exit 1
fi

echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║       Z V - M A N A G E R           ║"
echo "  ║  Mempersiapkan instalasi...          ║"
echo "  ╚══════════════════════════════════════╝"
echo ""

# Install git kalau belum ada
if ! command -v git &>/dev/null; then
    echo "[ INFO ] Menginstall git..."
    apt-get install -y git &>/dev/null
fi

# Hapus folder lama kalau ada
rm -rf /root/ZV-Manager

echo "[ INFO ] Mengunduh ZV-Manager..."
git clone -q https://github.com/ZenXNF/ZV-Manager.git /root/ZV-Manager

if [[ ! -f /root/ZV-Manager/install.sh ]]; then
    echo "[ERROR] Gagal mengunduh ZV-Manager!"
    exit 1
fi

cd /root/ZV-Manager
chmod +x install.sh
find . -name "*.sh" -exec chmod +x {} \;

echo "[ INFO ] Memulai instalasi..."
echo ""
bash install.sh
