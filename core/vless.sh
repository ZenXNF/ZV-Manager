#!/bin/bash
# ============================================================
#   ZV-Manager - VLESS Account Core Helper
# ============================================================

VLESS_DIR="/etc/zv-manager/accounts/vless"
XRAY_DIR="/usr/local/etc/xray"

# Generate UUID v4
gen_uuid() {
    python3 -c "import uuid; print(uuid.uuid4())"
}

# Generate username VLESS unik
gen_vless_username() {
    local prefix="vless"
    local ts; ts=$(date +%Y%m%d%H%M%S)
    local rand; rand=$(tr -dc 'a-z0-9' < /dev/urandom | head -c 4)
    echo "${prefix}-${rand}${ts: -4}"
}

# Generate VLESS URL
# vless_url <uuid> <domain> <port> <security> <network> <path_or_service> <label>
vless_url() {
    local uuid="$1"
    local domain="$2"
    local port="$3"
    local security="$4"   # "tls" atau "none"
    local network="$5"    # "ws" atau "grpc"
    local path="$6"       # "/vless" atau "vless-grpc"
    local label="${7:-VLESS}"

    if [[ "$network" == "ws" ]]; then
        echo "vless://${uuid}@${domain}:${port}?encryption=none&security=${security}&type=ws&host=${domain}&path=${path}#${label}"
    else
        echo "vless://${uuid}@${domain}:${port}?encryption=none&security=${security}&type=grpc&serviceName=${path}#${label}"
    fi
}

# Hitung jumlah akun VLESS aktif
vless_count_active() {
    local now_ts; now_ts=$(date +%s)
    local count=0
    for conf in "${VLESS_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue
        local exp_ts; exp_ts=$(grep "^EXPIRED_TS=" "$conf" | cut -d= -f2 | tr -d '"')
        local is_trial; is_trial=$(grep "^IS_TRIAL=" "$conf" | cut -d= -f2 | tr -d '"')
        [[ "$is_trial" == "1" ]] && continue
        [[ "$exp_ts" -gt "$now_ts" ]] && count=$((count + 1))
    done
    echo "$count"
}

# Cek apakah xray sudah terinstall
xray_installed() {
    [[ -f "/usr/local/bin/xray" && -f "/etc/systemd/system/zv-xray.service" ]]
}
