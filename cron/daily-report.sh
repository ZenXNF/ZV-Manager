#!/bin/bash
# ============================================================
#   ZV-Manager - Daily Report ke Admin Telegram
#   Cron: jam 07:00
# ============================================================

source /etc/zv-manager/core/telegram.sh
tg_load || exit 0

now_ts=$(date +%s)
soon_ts=$(( now_ts + 3 * 86400 ))

# ── Hitung akun SSH ──────────────────────────────────────────
ssh_aktif=0; ssh_expired=0; ssh_expiring=0
ssh_revenue_est=0
ssh_expiring_min=999; ssh_expiring_max=0

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
        sisa=$(( (EXPIRED_TS - now_ts) / 86400 ))
        (( sisa < ssh_expiring_min )) && ssh_expiring_min=$sisa
        (( sisa > ssh_expiring_max )) && ssh_expiring_max=$sisa
    else
        ssh_aktif=$((ssh_aktif + 1))
        if [[ -n "$SERVER" ]]; then
            harga=$(grep "^TG_HARGA_HARI=" "/etc/zv-manager/servers/${SERVER}.tg.conf" 2>/dev/null \
                | cut -d= -f2 | tr -d '"' | tr -dc '0-9')
            sisa=$(( (EXPIRED_TS - now_ts) / 86400 ))
            [[ -n "$harga" && "$harga" -gt 0 ]] && \
                ssh_revenue_est=$((ssh_revenue_est + harga * sisa))
        fi
    fi
done

# Format expiring range SSH
if [[ $ssh_expiring -gt 0 ]]; then
    if [[ $ssh_expiring_min -eq $ssh_expiring_max ]]; then
        ssh_expiring_label="${ssh_expiring} akun (${ssh_expiring_min} hari)"
    else
        ssh_expiring_label="${ssh_expiring} akun (${ssh_expiring_min}-${ssh_expiring_max} hari)"
    fi
else
    ssh_expiring_label="0 akun"
fi

# ── Hitung akun VMess ────────────────────────────────────────
vmess_aktif=0; vmess_expired=0; vmess_expiring=0
vmess_revenue_est=0
vmess_expiring_min=999; vmess_expiring_max=0

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
            sisa=$(( (EXPIRED_TS - now_ts) / 86400 ))
            (( sisa < vmess_expiring_min )) && vmess_expiring_min=$sisa
            (( sisa > vmess_expiring_max )) && vmess_expiring_max=$sisa
        else
            vmess_aktif=$((vmess_aktif + 1))
            if [[ -n "$SERVER" ]]; then
                harga=$(grep "^TG_HARGA_VMESS_HARI=\|^TG_HARGA_HARI=" \
                    "/etc/zv-manager/servers/${SERVER}.tg.conf" 2>/dev/null \
                    | head -1 | cut -d= -f2 | tr -d '"' | tr -dc '0-9')
                sisa=$(( (EXPIRED_TS - now_ts) / 86400 ))
                [[ -n "$harga" && "$harga" -gt 0 ]] && \
                    vmess_revenue_est=$((vmess_revenue_est + harga * sisa))
            fi
        fi
    done
fi

# Format expiring range VMess
if [[ $vmess_expiring -gt 0 ]]; then
    if [[ $vmess_expiring_min -eq $vmess_expiring_max ]]; then
        vmess_expiring_label="${vmess_expiring} akun (${vmess_expiring_min} hari)"
    else
        vmess_expiring_label="${vmess_expiring} akun (${vmess_expiring_min}-${vmess_expiring_max} hari)"
    fi
else
    vmess_expiring_label="0 akun"
fi

# ── Revenue hari ini dari log ─────────────────────────────────
revenue_today=0
while IFS= read -r line; do
    [[ "$line" == *"$(date +"%Y-%m-%d")"* ]] || continue
    if echo "$line" | grep -qE "\] (BELI|RENEW|BW_BELI|VMESS_BELI|VMESS_BW_BELI|VMESS_RENEW):"; then
        total=$(echo "$line" | grep -oP "total=\K[0-9]+")
        [[ -n "$total" ]] && revenue_today=$((revenue_today + total))
    fi
done < "/var/log/zv-manager/install.log"

_fmt() { printf "%'d" "$1" 2>/dev/null || echo "$1"; }

total_aktif=$((ssh_aktif + vmess_aktif))
total_expiring=$((ssh_expiring + vmess_expiring))
total_rev_est=$((ssh_revenue_est + vmess_revenue_est))

msg="📊 <b>Laporan Harian ZV-Manager</b>
━━━━━━━━━━━━━━━━━━━
📅 Tanggal : $(TZ="Asia/Jakarta" date +"%d %b %Y")

🔑 <b>SSH Tunnel</b>
├ Aktif     : ${ssh_aktif} akun
├ Expiring  : ${ssh_expiring_label}
└ Expired   : ${ssh_expired} akun

⚡ <b>VMess</b>
├ Aktif     : ${vmess_aktif} akun
├ Expiring  : ${vmess_expiring_label}
└ Expired   : ${vmess_expired} akun

💰 <b>Revenue</b>
├ Hari ini  : Rp$(_fmt "$revenue_today")
└ Est. total: Rp$(_fmt "$total_rev_est")

📈 Total Aktif  : ${total_aktif} akun
⚠️ Akan Expired : ${total_expiring} akun
━━━━━━━━━━━━━━━━━━━"

[[ -z "$TG_TOKEN" || -z "$TG_ADMIN_ID" ]] && exit 0

python3 - << PYEOF
import json, urllib.request
token   = "${TG_TOKEN}"
chat_id = "${TG_ADMIN_ID}"
text    = """${msg}"""
data = json.dumps({"chat_id": chat_id, "text": text, "parse_mode": "HTML"}).encode()
req  = urllib.request.Request(
    f"https://api.telegram.org/bot{token}/sendMessage",
    data=data, headers={"Content-Type": "application/json"})
try:
    urllib.request.urlopen(req, timeout=15)
except Exception as e:
    print(f"Error: {e}")
PYEOF
