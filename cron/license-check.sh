#!/bin/bash
# ============================================================
#   ZV-Manager — Cron Cek Izin Harian
#   Dijalankan setiap hari jam 01:00 oleh /etc/cron.d/zv-license
#   Kalau grace period habis → auto uninstall otomatis
# ============================================================

CHECKER_BIN="/etc/zv-manager/checker/zv-checker"
LOG="/var/log/zv-manager/license.log"

_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [cron-license] $1" >> "$LOG" 2>/dev/null
}

# Kalau checker tidak ada, cron ini tidak bisa bekerja — skip saja
if [[ ! -f "$CHECKER_BIN" ]]; then
    _log "SKIP: $CHECKER_BIN tidak ditemukan"
    exit 0
fi

if [[ ! -x "$CHECKER_BIN" ]]; then
    chmod +x "$CHECKER_BIN"
fi

# Ambil IP publik
public_ip=$(curl -s --max-time 10 https://ipv4.icanhazip.com 2>/dev/null \
         || wget -qO- --timeout=10 https://ipinfo.io/ip 2>/dev/null)
public_ip=$(echo "$public_ip" | tr -d '[:space:]')

if [[ -z "$public_ip" ]]; then
    _log "SKIP: gagal ambil IP publik (koneksi?)"
    exit 0
fi

# Jalankan checker
# Kalau dijalankan manual (ada terminal), tampilkan output ke layar sekaligus log
if [ -t 1 ]; then
    "$CHECKER_BIN" "$public_ip" 2>&1 | tee -a "$LOG"
else
    "$CHECKER_BIN" "$public_ip" >> "$LOG" 2>&1
fi
exit_code=$?

case $exit_code in
    0)
        _log "OK: IP $public_ip — izin aktif"
        ;;
    1)
        # IP tidak terdaftar — aneh kalau ini muncul di cron (sudah terinstall)
        # Log saja, jangan langsung uninstall dari cron untuk keamanan
        _log "TOLAK: IP $public_ip tidak terdaftar di whitelist"
        ;;
    2)
        _log "PERINGATAN: IP $public_ip — dalam grace period, izin segera habis"
        ;;
    3)
        # Grace period habis → auto uninstall
        _log "KADALUARSA: IP $public_ip — grace period habis, memulai auto uninstall"

        if [[ -f "/etc/zv-manager/uninstall.sh" ]]; then
            _log "Menjalankan uninstall.sh --silent ..."
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
