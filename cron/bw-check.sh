#!/bin/bash
# ============================================================
#   ZV-Manager - Bandwidth Check (IP-based)
#   Cron: setiap 5 menit
#   1. Deteksi IP aktif per user via auth.log + ss
#   2. Update iptables rules
#   3. Akumulasi bytes ke conf
#   4. Block jika quota habis, warn jika 80%
# ============================================================
ACCOUNT_DIR="/etc/zv-manager/accounts/ssh"
BW_SESSION_DIR="/tmp/zv-bw"
TG_CONF="/etc/zv-manager/telegram.conf"

source /etc/zv-manager/core/bandwidth.sh

mkdir -p "$BW_SESSION_DIR"

# Load Telegram config
TOKEN=$(grep "^TG_TOKEN=" "$TG_CONF" 2>/dev/null | cut -d= -f2 | tr -d '"'"'"' ')
ADMIN=$(grep "^TG_ADMIN_ID=" "$TG_CONF" 2>/dev/null | cut -d= -f2 | tr -d '"'"'"' ')

_tg_send() {
    local chat="$1" text="$2"
    [[ -z "$TOKEN" || -z "$chat" ]] && return
    curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
        -d "chat_id=${chat}&text=${text}&parse_mode=HTML" > /dev/null 2>&1
}

# Ambil semua client IP yang sedang konek ke SSH port
estab_ips=$(ss -tn state established 2>/dev/null | \
    awk '$4 ~ /:22$|:500$|:40000$|:109$|:143$/ {print $5}' | \
    cut -d: -f1 | grep -v '^$' | sort -u)

for conf_file in "$ACCOUNT_DIR"/*.conf; do
    [[ -f "$conf_file" ]] || continue

    user=$(grep "^USERNAME=" "$conf_file" | cut -d= -f2 | tr -d '[:space:]')
    quota=$(grep "^BW_QUOTA_BYTES=" "$conf_file" | cut -d= -f2 | tr -d '[:space:]')
    tg_uid=$(grep "^TG_USER_ID=" "$conf_file" | cut -d= -f2 | tr -d '[:space:]')

    [[ -z "$user" || "${quota:-0}" == "0" ]] && continue

    # ── Update IP rules untuk user yang sedang konek ─────────
    if [[ -n "$estab_ips" ]]; then
        user_ips=$(grep "Accepted.*for ${user} from" /var/log/auth.log 2>/dev/null | \
            grep -oP 'from \K[\d.]+' | sort -u | \
            while IFS= read -r ip; do
                echo "$estab_ips" | grep -qx "$ip" && echo "$ip"
            done)

        if [[ -n "$user_ips" ]]; then
            # Simpan IP aktif ke session file
            echo "$user_ips" > "${BW_SESSION_DIR}/${user}.ips"
            # Tambah iptables rule untuk tiap IP
            while IFS= read -r ip; do
                _bw_add_ip_rule "$user" "$ip"
            done <<< "$user_ips"
        fi
    fi

    # ── Akumulasi bytes ───────────────────────────────────────
    _bw_accumulate "$user"

    # ── Cek quota ─────────────────────────────────────────────
    _bw_is_blocked "$user" && continue  # sudah diblock, skip

    used=$(_bw_get_used "$user")
    used=${used:-0}
    quota=${quota:-0}

    # Block jika quota habis (>= 100%)
    if (( used >= quota )); then
        _bw_block "$user"
        used_fmt=$(_bw_fmt "$used")
        quota_fmt=$(_bw_fmt "$quota")
        _tg_send "$tg_uid" "🚫 <b>Kuota Habis!</b>%0A━━━━━━━━━━━━━━━━━━━%0A👤 Username : <code>${user}</code>%0A📶 Terpakai : ${used_fmt} / ${quota_fmt}%0A━━━━━━━━━━━━━━━━━━━%0ASilahkan tambah kuota melalui bot."
        _bw_log "QUOTA_EXCEEDED: $user used=${used} quota=${quota}"
        continue
    fi

    # Warn jika >= 80%
    pct=$(( used * 100 / quota ))
    warn_file="${BW_SESSION_DIR}/${user}.warned"

    if (( pct >= 80 )); then
        if [[ ! -f "$warn_file" ]]; then
            touch "$warn_file"
            sisa=$(( quota - used ))
            sisa_fmt=$(_bw_fmt "$sisa")
            used_fmt=$(_bw_fmt "$used")
            quota_fmt=$(_bw_fmt "$quota")
            _tg_send "$tg_uid" "⚠️ <b>Kuota Hampir Habis!</b>%0A━━━━━━━━━━━━━━━━━━━%0A👤 Username : <code>${user}</code>%0A📶 Terpakai : ${used_fmt} / ${quota_fmt}%0A📊 Persentase: ${pct}%%25%0A💾 Sisa      : ${sisa_fmt}%0A━━━━━━━━━━━━━━━━━━━%0ASilahkan tambah kuota sebelum habis!"
            _bw_log "WARN_80: $user pct=${pct}% used=${used}"
        fi
    else
        # Reset warning flag jika sudah turun di bawah 80% (setelah tambah kuota)
        rm -f "$warn_file" 2>/dev/null
    fi
done
