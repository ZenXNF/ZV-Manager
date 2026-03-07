#!/bin/bash
# ============================================================
#   ZV-Manager - Cek Versi Terbaru dari GitHub
#   Bandingkan commit hash lokal vs GitHub (main branch)
#   Dipanggil cron sekali sehari jam 06:00
# ============================================================

GITHUB_API="https://api.github.com/repos/ZenXNF/ZV-Manager/commits/main"
CACHE="/tmp/zv-update-available"
LOCAL_CONF="/etc/zv-manager/config.conf"

# Ambil commit hash lokal
local_hash=$(grep "^COMMIT_HASH=" "$LOCAL_CONF" 2>/dev/null | cut -d= -f2 | tr -d '"[:space:]')
[[ -z "$local_hash" ]] && exit 0

# Ambil commit hash terbaru dari GitHub API (short 7 char)
latest_hash=$(curl -sf --max-time 10 "$GITHUB_API" 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['sha'][:7])" 2>/dev/null)
[[ -z "$latest_hash" ]] && exit 0

# Simpan latest ke cache untuk ditampilkan di menu
if [[ "$latest_hash" != "$local_hash" ]]; then
    echo "$latest_hash" > "$CACHE"
else
    rm -f "$CACHE"
fi
