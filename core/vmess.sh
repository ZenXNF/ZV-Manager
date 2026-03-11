#!/bin/bash
# ============================================================
#   ZV-Manager - VMess Account Core Helper
# ============================================================

VMESS_DIR="/etc/zv-manager/accounts/vmess"
XRAY_DIR="/usr/local/etc/xray"

# Generate UUID v4
gen_uuid() {
    python3 -c "import uuid; print(uuid.uuid4())"
}

# Generate username VMess unik
gen_vmess_username() {
    local prefix="vmess"
    local ts
    ts=$(date +%Y%m%d%H%M%S)
    local rand
    rand=$(tr -dc 'a-z0-9' < /dev/urandom | head -c 4)
    echo "${prefix}-${rand}${ts: -4}"
}

# Buat akun VMess baru
# vmess_create <username> <exp_days> [tg_uid] [is_trial]
vmess_create() {
    local username="$1"
    local exp_days="$2"
    local tg_uid="${3:-}"
    local is_trial="${4:-0}"

    mkdir -p "$VMESS_DIR"

    local uuid
    uuid=$(gen_uuid)

    local now_ts
    now_ts=$(date +%s)
    local exp_ts
    exp_ts=$((now_ts + exp_days * 86400))
    local exp_date
    exp_date=$(date -d "@${exp_ts}" +"%Y-%m-%d")
    local created
    created=$(date +"%Y-%m-%d")

    # Ambil domain dari server conf
    local domain
    domain=$(cat /etc/zv-manager/domain 2>/dev/null)

    # Ambil quota bandwidth dari server TG conf
    local bw_limit_gb=0
    local tg_conf_dir="/etc/zv-manager/servers"
    local local_ip
    local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null)
    for sc in "${tg_conf_dir}"/*.tg.conf; do
        [[ -f "$sc" ]] || continue
        local sc_ip
        sc_ip=$(grep "^IP=" "$sc" | cut -d= -f2 | tr -d '"')
        if [[ "$sc_ip" == "$local_ip" || -z "$local_ip" ]]; then
            bw_limit_gb=$(grep "^TG_BW_PER_HARI_VMESS=" "$sc" | cut -d= -f2 | tr -d '"')
            [[ -z "$bw_limit_gb" ]] && bw_limit_gb=$(grep "^TG_BW_PER_HARI=" "$sc" | cut -d= -f2 | tr -d '"')
            bw_limit_gb=$(( ${bw_limit_gb:-0} * exp_days ))
            break
        fi
    done

    cat > "${VMESS_DIR}/${username}.conf" <<EOF
USERNAME="${username}"
UUID="${uuid}"
DOMAIN="${domain}"
EXPIRED_TS="${exp_ts}"
EXPIRED_DATE="${exp_date}"
CREATED="${created}"
IS_TRIAL="${is_trial}"
TG_USER_ID="${tg_uid}"
BW_LIMIT_GB="${bw_limit_gb}"
BW_USED_BYTES="0"
BW_LAST_CHECK="0"
EOF

    # Reload xray config
    source /etc/zv-manager/services/xray/install.sh 2>/dev/null
    reload_xray

    echo "$username"
}

# Hapus akun VMess
vmess_delete() {
    local username="$1"
    rm -f "${VMESS_DIR}/${username}.conf"
    source /etc/zv-manager/services/xray/install.sh 2>/dev/null
    reload_xray
}

# Generate VMess URL
# vmess_url <uuid> <domain> <port> <tls> <network> <path_or_service>
vmess_url() {
    local uuid="$1"
    local domain="$2"
    local port="$3"
    local tls="$4"      # "tls" atau "none"
    local network="$5"  # "ws" atau "grpc"
    local path="$6"     # "/vmess" atau "vmess-grpc"
    local ps_label="${7:-VMess}"

    local json=""
    if [[ "$network" == "ws" ]]; then
        json=$(printf '{"v":"2","ps":"%s","add":"%s","port":"%s","id":"%s","aid":"0","net":"ws","type":"none","host":"%s","path":"%s","tls":"%s"}' \
            "$ps_label" "$domain" "$port" "$uuid" "$domain" "$path" "$tls")
    else
        json=$(printf '{"v":"2","ps":"%s","add":"%s","port":"%s","id":"%s","aid":"0","net":"grpc","type":"none","host":"","path":"%s","tls":"%s"}' \
            "$ps_label" "$domain" "$port" "$uuid" "$path" "$tls")
    fi

    echo "vmess://$(echo -n "$json" | base64 -w 0)"
}

# Hitung jumlah akun VMess aktif
vmess_count_active() {
    local now_ts
    now_ts=$(date +%s)
    local count=0
    for conf in "${VMESS_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue
        local exp_ts
        exp_ts=$(grep "^EXPIRED_TS=" "$conf" | cut -d= -f2 | tr -d '"')
        local is_trial
        is_trial=$(grep "^IS_TRIAL=" "$conf" | cut -d= -f2 | tr -d '"')
        [[ "$is_trial" == "1" ]] && continue
        [[ "$exp_ts" -gt "$now_ts" ]] && count=$((count + 1))
    done
    echo "$count"
}

# Cek apakah xray sudah terinstall
xray_installed() {
    [[ -f "/usr/local/bin/xray" && -f "/etc/systemd/system/zv-xray.service" ]]
}
