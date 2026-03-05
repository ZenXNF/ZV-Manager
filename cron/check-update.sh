#!/bin/bash
# ============================================================
#   ZV-Manager - Cek Versi Terbaru dari GitHub
#   Dipanggil cron sekali sehari jam 06:00
#   Hasil disimpan ke /tmp/zv-update-available
# ============================================================

GITHUB_RAW="https://raw.githubusercontent.com/ZenXNF/ZV-Manager/main/config.conf"
CACHE="/tmp/zv-update-available"
LOCAL_CONF="/etc/zv-manager/config.conf"

# Ambil versi lokal
local_ver=$(grep "^SCRIPT_VERSION=" "$LOCAL_CONF" 2>/dev/null | cut -d= -f2 | tr -d '"[:space:]')
[[ -z "$local_ver" ]] && exit 0

# Ambil versi terbaru dari GitHub (timeout 10 detik)
latest_ver=$(curl -sf --max-time 10 "$GITHUB_RAW" 2>/dev/null \
    | grep "^SCRIPT_VERSION=" | cut -d= -f2 | tr -d '"[:space:]')
[[ -z "$latest_ver" ]] && exit 0

# Bandingkan — kalau beda, simpan ke cache
if [[ "$latest_ver" != "$local_ver" ]]; then
    echo "$latest_ver" > "$CACHE"
else
    rm -f "$CACHE"
fi
