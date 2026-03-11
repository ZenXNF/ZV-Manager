#!/bin/bash
# ============================================================
#   ZV-Manager - Daily Report ke Admin Telegram
#   Dipanggil via cron setiap hari jam 07:00
#   Laporan: akun aktif SSH+VMess, expired hari ini,
#            expiring soon (3 hari), estimasi revenue
# ============================================================

source /etc/zv-manager/core/telegram.sh
tg_load || exit 0

LOG="/var/log/zv-manager/install.log"
today=$(date +"%Y-%m-%d")
now_ts=$(date +%s)
soon_ts=$(( now_ts + 3 * 86400 ))  # 3 hari ke depan

# ── Hitung akun SSH ──────────────────────────────────────────
ssh_aktif=0; ssh_expired=0; ssh_expiring=0
ssh_revenue_est=0

for conf in /etc/zv-manager/accounts/ssh/*.conf; do
    [[ -f "$conf" ]] || continue
    unset IS_TRIAL EXPIRED_TS SERVER
    source "$conf"
    [[ "$IS_TRIAL" == "1" ]] && continue
    [[ -z "$EXPIRED_TS" ]] && continue

    if [[ "$EXPIRED_TS" -lt "$now_ts" ]]; then
        ssh_expired=$((ssh_expired + 1))
    elif [[ "$EXPIRED_TS" -le "$soon_ts" ]]; then
        ssh_expiring=$((ssh_expiring + 1))
        ssh_aktif=$((ssh_aktif + 1))
    else
        ssh_aktif=$((ssh_aktif + 1))
        # Hitung estimasi revenue dari sisa hari
        local_sname="$SERVER"
        if [[ -n "$local_sname" ]]; then
            harga=$(grep "^TG_HARGA_HARI=" "/etc/zv-manager/servers/${local_sname}.tg.conf" 2>/dev/null \
                    | cut -d= -f2 | tr -d '"' | tr -dc '0-9')
            sisa_hari=$(( (EXPIRED_TS - now_ts) / 86400 ))
            [[ -n "$harga" && "$harga" -gt 0 ]] && \
                ssh_revenue_est=$((ssh_revenue_est + harga * sisa_hari))
        fi
    fi
done

# ── Hitung akun VMess ────────────────────────────────────────
vmess_aktif=0; vmess_expired=0; vmess_expiring=0
vmess_revenue_est=0

if [[ -d /etc/zv-manager/accounts/vmess ]]; then
    for conf in /etc/zv-manager/accounts/vmess/*.conf; do
        [[ -f "$conf" ]] || continue
        unset IS_TRIAL EXPIRED_TS SERVER
        source "$conf"
        [[ "$IS_TRIAL" == "1" ]] && continue
        [[ -z "$EXPIRED_TS" ]] && continue

        if [[ "$EXPIRED_TS" -lt "$now_ts" ]]; then
            vmess_expired=$((vmess_expired + 1))
        elif [[ "$EXPIRED_TS" -le "$soon_ts" ]]; then
            vmess_expiring=$((vmess_expiring + 1))
            vmess_aktif=$((vmess_aktif + 1))
        else
            vmess_aktif=$((vmess_aktif + 1))
            local_sname="$SERVER"
            if [[ -n "$local_sname" ]]; then
                harga=$(grep "^TG_HARGA_VMESS_HARI=\|^TG_HARGA_HARI=" \
                        "/etc/zv-manager/servers/${local_sname}.tg.conf" 2>/dev/null \
                        | head -1 | cut -d= -f2 | tr -d '"' | tr -dc '0-9')
                sisa_hari=$(( (EXPIRED_TS - now_ts) / 86400 ))
                [[ -n "$harga" && "$harga" -gt 0 ]] && \
                    vmess_revenue_est=$((vmess_revenue_est + harga * sisa_hari))
            fi
        fi
    done
fi

# ── Hitung revenue hari ini dari log ─────────────────────────
LOG_FILE="/var/log/zv-manager/install.log"
revenue_today=0
while IFS= read -r line; do
    [[ "$line" == *"$(date +"%Y-%m-%d")"* ]] || continue
    if echo "$line" | grep -qE "\] (BELI|RENEW|BW_BELI|VMESS_BELI|VMESS_BW_BELI|VMESS_RENEW):"; then
        total=$(echo "$line" | grep -oP "total=\K[0-9]+")
        [[ -n "$total" ]] && revenue_today=$((revenue_today + total))
    fi
done < "$LOG_FILE"

# ── Format angka ─────────────────────────────────────────────
_fmt() {
    local n="$1"
    printf "%'d" "$n" 2>/dev/null || echo "$n"
}

# ── Bangun pesan ─────────────────────────────────────────────
total_aktif=$((ssh_aktif + vmess_aktif))
total_expiring=$((ssh_expiring + vmess_expiring))
total_rev_est=$((ssh_revenue_est + vmess_revenue_est))

msg="📊 <b>Laporan Harian ZV-Manager</b>
━━━━━━━━━━━━━━━━━━━
📅 Tanggal : $(TZ="Asia/Jakarta" date +"%d %b %Y")

🔑 <b>SSH Tunnel</b>
├ Aktif     : ${ssh_aktif} akun
├ Expiring  : ${ssh_expiring} akun (3 hari)
└ Expired   : ${ssh_expired} akun

⚡ <b>VMess</b>
├ Aktif     : ${vmess_aktif} akun
├ Expiring  : ${vmess_expiring} akun (3 hari)
└ Expired   : ${vmess_expired} akun

💰 <b>Revenue</b>
├ Hari ini  : Rp$(_fmt "$revenue_today")
└ Est. total: Rp$(_fmt "$total_rev_est")

📈 Total Aktif  : ${total_aktif} akun
⚠️ Akan Expired : ${total_expiring} akun
━━━━━━━━━━━━━━━━━━━"

# ── Kirim ke admin ───────────────────────────────────────────
[[ -z "$TG_TOKEN" || -z "$TG_ADMIN_ID" ]] && exit 0

python3 - << PYEOF
import json, urllib.request
token   = "${TG_TOKEN}"
chat_id = "${TG_ADMIN_ID}"
text    = """${msg}"""
payload = json.dumps({
    "chat_id":    chat_id,
    "parse_mode": "HTML",
    "text":       text
}).encode()
req = urllib.request.Request(
    f"https://api.telegram.org/bot{token}/sendMessage",
    data=payload,
    headers={"Content-Type": "application/json"}
)
try:
    urllib.request.urlopen(req, timeout=15)
except Exception as e:
    print(f"Error: {e}")
PYEOF

echo "[$(date '+%Y-%m-%d %H:%M:%S')] DAILY_REPORT: sent to admin" >> "$LOG"
