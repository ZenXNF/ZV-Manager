#!/bin/bash
# ============================================================
#   ZV-Manager — Cron Cek Izin Harian
#   Dijalankan setiap hari jam 01:00 oleh /etc/cron.d/zv-license
#   Kalau grace period habis → auto uninstall otomatis
# ============================================================

CHECKER_BIN="/etc/zv-manager/checker/zv-checker"
LOG="/var/log/zv-manager/license.log"
LICENSE_INFO="/etc/zv-manager/license.info"

_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [cron-license] $1" >> "$LOG" 2>/dev/null
}

# Cetak ke terminal + log (hanya kalau ada TTY)
_print() {
    if [ -t 1 ]; then
        echo -e "$1"
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [cron-license] $1" >> "$LOG" 2>/dev/null
}

# Simpan info izin ke cache license.info
_save_license_info() {
    local zvinfo="$1"
    local data="${zvinfo#*:}"

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
    chmod 600 "$LICENSE_INFO" 2>/dev/null
}

# Kalau checker tidak ada, skip
if [[ ! -f "$CHECKER_BIN" ]]; then
    _log "SKIP: $CHECKER_BIN tidak ditemukan"
    exit 0
fi

[[ ! -x "$CHECKER_BIN" ]] && chmod +x "$CHECKER_BIN"

# Ambil IP publik
public_ip=$(curl -s --max-time 10 https://ipv4.icanhazip.com 2>/dev/null \
         || wget -qO- --timeout=10 https://ipinfo.io/ip 2>/dev/null)
public_ip=$(echo "$public_ip" | tr -d '[:space:]')

if [[ -z "$public_ip" ]]; then
    _log "SKIP: gagal ambil IP publik (koneksi?)"
    exit 0
fi

# Jalankan checker, tangkap full output
full_output=$("$CHECKER_BIN" "$public_ip" 2>&1)
exit_code=$?

# Pisahkan baris ##ZVINFO dari output user
zvinfo_line=$(echo "$full_output" | grep "^##ZVINFO:")
clean_output=$(echo "$full_output" | grep -v "^##ZVINFO:")

# Tampilkan ke terminal kalau ada (dijalankan manual)
if [ -t 1 ]; then
    echo ""
    echo "$clean_output"
fi

# Simpan info ke cache license.info
if [[ -n "$zvinfo_line" ]]; then
    _save_license_info "$zvinfo_line"
fi

case $exit_code in
    0)
        _log "OK: IP $public_ip — izin aktif"
        ;;
    1)
        _log "TOLAK: IP $public_ip tidak terdaftar di whitelist"
        ;;
    2)
        _log "PERINGATAN: IP $public_ip — dalam grace period, izin segera habis"
        ;;
    3)
        _log "KADALUARSA: IP $public_ip — grace period habis, memulai auto uninstall"

        if [[ -f "/etc/zv-manager/uninstall.sh" ]]; then
            _log "Menjalankan uninstall.sh --silent ..."
            # Kalau ada terminal (dijalankan manual), tampilkan progress
            if [ -t 1 ]; then
                bash /etc/zv-manager/uninstall.sh --silent 2>&1 | tee -a "$LOG"
            else
                bash /etc/zv-manager/uninstall.sh --silent >> "$LOG" 2>&1
            fi
            _log "Auto uninstall selesai"
        else
            _log "ERROR: uninstall.sh tidak ditemukan!"
        fi
        ;;
    4)
        _log "SKIP: gagal fetch daftar izin (koneksi?)"
        ;;
    *)
        _log "UNKNOWN exit code: $exit_code"
        ;;
esac

exit 0
