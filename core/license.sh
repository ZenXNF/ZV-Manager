#!/bin/bash
# ============================================================
#   ZV-Manager — License Checker
#   Dipanggil dari install.sh dan update.sh sebelum apapun.
#   Menggunakan binary zv-checker (ELF Go) untuk validasi IP.
# ============================================================

CHECKER_BIN="/etc/zv-manager/checker/zv-checker"
CHECKER_LOG="/var/log/zv-manager/license.log"

_log_license() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$CHECKER_LOG" 2>/dev/null
}

check_license() {
    # Pastikan log file ada
    mkdir -p /var/log/zv-manager
    touch "$CHECKER_LOG"

    # Cari binary — bisa dari INSTALL_DIR (saat fresh install)
    # atau dari path permanen (saat update / cron)
    local checker="$CHECKER_BIN"
    if [[ ! -f "$checker" ]]; then
        # Saat fresh install, file belum di-copy ke /etc/zv-manager
        # coba cari dari direktori script yang sedang berjalan
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
        checker="$script_dir/checker/zv-checker"
    fi

    if [[ ! -f "$checker" ]]; then
        echo ""
        echo -e "\033[1;31m  [!] File zv-checker tidak ditemukan!\033[0m"
        echo -e "\033[0;33m  Jalankan dari direktori repo ZV-Manager yang lengkap.\033[0m"
        echo ""
        _log_license "GAGAL: zv-checker tidak ditemukan"
        exit 1
    fi

    if [[ ! -x "$checker" ]]; then
        chmod +x "$checker"
    fi

    # Ambil IP publik
    local public_ip
    public_ip=$(curl -s --max-time 10 https://ipv4.icanhazip.com 2>/dev/null \
             || wget -qO- --timeout=10 https://ipinfo.io/ip 2>/dev/null)
    public_ip=$(echo "$public_ip" | tr -d '[:space:]')

    if [[ -z "$public_ip" ]]; then
        echo ""
        echo -e "\033[1;31m  [!] Gagal mendapatkan IP publik VPS.\033[0m"
        echo -e "\033[0;33m  Periksa koneksi internet VPS.\033[0m"
        echo ""
        _log_license "GAGAL: tidak bisa ambil IP publik"
        exit 1
    fi

    # Jalankan checker, tangkap output dan exit code
    local checker_output
    checker_output=$("$checker" "$public_ip" 2>&1)
    local exit_code=$?

    # Selalu tampilkan output checker ke layar
    echo ""
    echo "$checker_output"

    case $exit_code in
        0)
            # Lolos — lanjut proses install/update
            _log_license "OK: IP $public_ip diizinkan"
            ;;
        1)
            # IP tidak terdaftar — stop total
            _log_license "TOLAK: IP $public_ip tidak terdaftar"
            exit 1
            ;;
        2)
            # Masih dalam grace period — lanjut tapi sudah ada warning dari output checker
            _log_license "PERINGATAN: IP $public_ip dalam grace period"
            echo -e "\033[1;33m  Melanjutkan proses...\033[0m"
            echo ""
            sleep 3
            ;;
        3)
            # Grace period habis — jalankan uninstall lalu keluar
            _log_license "KADALUARSA: IP $public_ip grace period habis, memulai uninstall"
            echo ""
            echo -e "\033[1;31m  Memulai penghapusan otomatis ZV-Manager...\033[0m"
            echo ""
            sleep 3
            _run_auto_uninstall
            exit 1
            ;;
        4)
            # Gagal fetch — ini bisa terjadi kalau internet mati sementara
            # Kita tidak blokir install supaya tidak merugikan user yang inetnya bermasalah
            _log_license "PERINGATAN: Gagal fetch daftar izin (koneksi?), dilewati"
            echo ""
            echo -e "\033[1;33m  [!] Tidak bisa mengakses daftar izin.\033[0m"
            echo -e "\033[0;33m  Proses dilanjutkan. Pastikan koneksi internet stabil.\033[0m"
            echo ""
            sleep 2
            ;;
        *)
            _log_license "UNKNOWN exit code $exit_code dari checker"
            ;;
    esac
}

_run_auto_uninstall() {
    local uninstall_script="/etc/zv-manager/uninstall.sh"
    if [[ -f "$uninstall_script" ]]; then
        bash "$uninstall_script" --silent
    else
        # Uninstall darurat kalau script utama tidak ada
        _emergency_cleanup
    fi
}

_emergency_cleanup() {
    # Pembersihan minimal kalau uninstall.sh tidak ada
    systemctl stop zv-wss zv-stunnel zv-udp 2>/dev/null
    systemctl disable zv-wss zv-stunnel zv-udp 2>/dev/null
    rm -f /etc/systemd/system/zv-*.service
    systemctl daemon-reload 2>/dev/null
    rm -f /etc/cron.d/zv-*
    rm -rf /etc/zv-manager
    rm -f /usr/local/bin/menu
    rm -f /usr/local/bin/zv-ws-proxy.py
}
