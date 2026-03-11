#!/bin/bash
# ============================================================
#   ZV-Manager - Update online users count per VMess account
#   Cron: setiap 1 menit
#   Update /var/www/zv-manager/api/online-{user}.json
# ============================================================

XRAY_BIN="/usr/local/bin/xray"
API_ADDR="127.0.0.1:10085"
API_DIR="/var/www/zv-manager/api"

[[ ! -f "$XRAY_BIN" ]] && exit 0

for f in /etc/zv-manager/accounts/vmess/*.conf; do
    [[ -f "$f" ]] || continue
    unset USERNAME EXPIRED_TS
    source "$f" 2>/dev/null
    [[ -z "$USERNAME" ]] && continue

    # Cek expired
    now_ts=$(date +%s)
    [[ -n "$EXPIRED_TS" && "$EXPIRED_TS" -lt "$now_ts" ]] && online=0 && {
        echo "{\"online\":0,\"username\":\"$USERNAME\"}" > "${API_DIR}/online-${USERNAME}.json"
        continue
    }

    # Query Xray API + reset stats (pakai --reset agar traffic period = 1 menit)
    online=$("$XRAY_BIN" api statsquery -s "$API_ADDR" \
        --pattern "user>>>${USERNAME}@vmess>>>traffic" --reset 2>/dev/null | \
        python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    stats = d.get('stat', [])
    # Ada traffic dalam 1 menit terakhir = online
    has_traffic = any(int(s.get('value', 0)) > 0 for s in stats)
    print(1 if has_traffic else 0)
except:
    print(0)
" 2>/dev/null || echo "0")

    echo "{\"online\":${online:-0},\"username\":\"$USERNAME\"}" \
        > "${API_DIR}/online-${USERNAME}.json"
done

chown -R www-data:www-data "$API_DIR" 2>/dev/null
