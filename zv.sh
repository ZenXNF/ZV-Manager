#!/bin/bash
# ============================================================
#   ZV-Manager - One-liner Installer
#   wget -qO zv.sh https://raw.githubusercontent.com/ZenXNF/ZV-Manager/main/zv.sh && bash zv.sh
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

# Hapus file installer lama supaya tidak ada duplikat
rm -f /root/zv.sh /root/zv.sh.1 /root/zv.sh.2 2>/dev/null

# Hapus folder lama kalau ada
rm -rf /root/ZV-Manager

echo "[ INFO ] Mengunduh ZV-Manager..."
git clone -q https://github.com/ZenXNF/ZV-Manager.git /root/ZV-Manager

if [[ ! -f /root/ZV-Manager/install.sh ]]; then
    echo "[ERROR] Gagal mengunduh ZV-Manager!"
    exit 1
fi

cd /root/ZV-Manager
find . -name "*.sh" -exec chmod +x {} \;
find . -name "*.py" -exec chmod +x {} \;
chmod +x checker/zv-checker 2>/dev/null  # FIX: binary tidak punya ekstensi .sh

echo "[ INFO ] Memulai instalasi..."
echo ""
bash install.sh
