#!/bin/bash
# ============================================================
#   ZV-Manager — License Checker
#   Dipanggil dari install.sh dan update.sh sebelum apapun.
#   Menggunakan binary zv-checker (ELF Go) untuk validasi IP.
# ============================================================

CHECKER_BIN="/etc/zv-manager/checker/zv-checker"
CHECKER_LOG="/var/log/zv-manager/license.log"
LICENSE_INFO="/etc/zv-manager/license.info"

_log_license() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$CHECKER_LOG" 2>/dev/null
}

# Simpan info izin ke file cache agar bisa dibaca menu tanpa fetch ulang
_save_license_info() {
    local zvinfo="$1"
    # Format: ##ZVINFO:name=xxx|expired=xxx|days=xxx|code=x
    local data="${zvinfo#*:}"   # hapus prefix ##ZVINFO:

    local name expired days code
    name=$(echo "$data"    | tr '|' '\n' | grep '^name='    | cut -d= -f2)
    expired=$(echo "$data" | tr '|' '\n' | grep '^expired=' | cut -d= -f2)
    days=$(echo "$data"    | tr '|' '\n' | grep '^days='    | cut -d= -f2)
    code=$(echo "$data"    | tr '|' '\n' | grep '^code='    | cut -d= -f2)

    mkdir -p "$(dirname "$LICENSE_INFO")"
    cat > "$LICENSE_INFO" <<EOF
# ZV-Manager — Cache Info Izin
# File ini diperbarui otomatis setiap kali izin dicek
# Jangan edit manual
LICENSE_NAME=$name
LICENSE_EXPIRED=$expired
LICENSE_DAYS_LEFT=$days
LICENSE_CODE=$code
LICENSE_LAST_CHECK=$(date '+%Y-%m-%d %H:%M:%S')
EOF
    chmod 600 "$LICENSE_INFO"
}

check_license() {
    mkdir -p /var/log/zv-manager
    touch "$CHECKER_LOG"

    # Cari binary — dari path permanen atau dari direktori repo saat fresh install
    local checker="$CHECKER_BIN"
    if [[ ! -f "$checker" ]]; then
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

    [[ ! -x "$checker" ]] && chmod +x "$checker"

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

    # Jalankan checker, tangkap full output
    local full_output
    full_output=$("$checker" "$public_ip" 2>&1)
    local exit_code=$?

    # Pisahkan baris ##ZVINFO dari output yang ditampilkan ke user
    local zvinfo_line
    zvinfo_line=$(echo "$full_output" | grep "^##ZVINFO:")
    local clean_output
    clean_output=$(echo "$full_output" | grep -v "^##ZVINFO:")

    # Tampilkan output ke layar (tanpa baris ##ZVINFO)
    echo ""
    echo "$clean_output"

    # Simpan info ke cache jika ada
    if [[ -n "$zvinfo_line" ]]; then
        _save_license_info "$zvinfo_line"
    fi

    case $exit_code in
        0)
            _log_license "OK: IP $public_ip diizinkan"
            ;;
        1)
            _log_license "TOLAK: IP $public_ip tidak terdaftar"
            exit 1
            ;;
        2)
            _log_license "PERINGATAN: IP $public_ip dalam grace period"
            echo -e "\033[1;33m  Melanjutkan proses...\033[0m"
            echo ""
            sleep 3
            ;;
        3)
            _log_license "KADALUARSA: IP $public_ip grace period habis, memulai uninstall"
            echo ""
            echo -e "\033[0;33m  Silahkan hubungi Telegram: @ZenXNF / t.me/ZenXNF\033[0m"
echo ""
echo -e "\033[1;31m  Memulai penghapusan otomatis ZV-Manager...\033[0m"
            echo ""
            sleep 3
            _run_auto_uninstall
            exit 1
            ;;
        4)
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
        _emergency_cleanup
    fi
}

_emergency_cleanup() {
    systemctl stop zv-wss zv-udp 2>/dev/null
    systemctl disable zv-wss zv-udp 2>/dev/null
    rm -f /etc/systemd/system/zv-*.service
    systemctl daemon-reload 2>/dev/null
    rm -f /etc/cron.d/zv-*
    rm -rf /etc/zv-manager
    rm -f /usr/local/bin/menu
    rm -f /usr/local/bin/zv-ws-proxy.py
}
