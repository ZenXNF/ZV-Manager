#!/bin/bash
# ============================================================
#   ZV-Manager - Helper Functions
# ============================================================

# --- Load config global ---
load_config() {
    local config_file="/etc/zv-manager/config.conf"
    if [[ -f "$config_file" ]]; then
        source "$config_file"
    else
        echo "Config tidak ditemukan: $config_file"
        exit 1
    fi
}

# --- Baca domain yang sudah diset ---
get_domain() {
    DOMAIN=$(cat /etc/zv-manager/domain 2>/dev/null || cat /etc/xray/domain 2>/dev/null)
    echo "$DOMAIN"
}

# --- Format tanggal expired ---
expired_date() {
    local days=$1
    date -d "$days days" +"%Y-%m-%d"
}

# --- Cek apakah user Linux sudah ada ---
user_exists() {
    id "$1" &>/dev/null
}

# --- Cek apakah service aktif ---
service_running() {
    systemctl is-active --quiet "$1"
}

# --- Restart service dan tampilkan status ---
restart_service() {
    local service=$1
    systemctl restart "$service" &>/dev/null
    if service_running "$service"; then
        print_ok "Service $service: Running"
    else
        print_error "Service $service: Gagal restart!"
    fi
}

# --- Enable dan start service ---
enable_service() {
    local service=$1
    systemctl enable "$service" &>/dev/null
    systemctl start "$service" &>/dev/null
}

# --- Press Enter to continue (mobile-friendly) ---
press_any_key() {
    echo ""
    read -rp "  Tekan Enter untuk kembali ke menu... " _dummy
    echo ""
}

# --- Konfirmasi Y/N (mobile-friendly) ---
confirm() {
    local msg=${1:-"Lanjutkan?"}
    read -rp "  $msg [y/n]: " answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

# --- Generate password random ---
random_password() {
    local length=${1:-12}
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$length"
}

# --- Cek port apakah sudah dipakai ---
port_in_use() {
    ss -tuln | grep -q ":$1 "
}
