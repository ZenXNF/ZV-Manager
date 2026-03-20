#!/bin/bash
# ============================================================
#   ZV-Manager - Lock/Unlock Akun VMess
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/utils/remote.sh
source /etc/zv-manager/core/vmess.sh

action=${1:-lock}

manage_vmess_lock() {
    local target; target=$(get_target_server)
    local target_info; target_info=$(target_display)
    local label; [[ "$action" == "lock" ]] && label="LOCK" || label="UNLOCK"

    clear
    _sep
    _grad " ${BWHITE}${label} AKUN VMESS${NC}" 255 0 127 0 210 255
    _sep
    echo ""
    echo -e "  ${BWHITE}Target :${NC} ${BGREEN}${target_info}${NC}"
    echo ""
    read -rp "  Username: " username
    echo ""

    if [[ -z "$username" ]]; then
        print_error "Username tidak boleh kosong!"
        press_any_key; return
    fi

    if is_local_target; then
        local conf="/etc/zv-manager/accounts/vmess/${username}.conf"
        if [[ ! -f "$conf" ]]; then
            print_error "Username '${username}' tidak ditemukan!"
            press_any_key; return
        fi
        local uuid; uuid=$(grep "^UUID=" "$conf" | cut -d= -f2 | tr -d '"')
        if [[ "$action" == "lock" ]]; then
            # Disable via Xray API
            remote_vmess_agent "local" "disable" "$username" &>/dev/null
            print_ok "Akun '${username}' berhasil di-lock"
        else
            remote_vmess_agent "local" "enable" "$username" &>/dev/null
            print_ok "Akun '${username}' berhasil di-unlock"
        fi
    else
        print_info "Mengirim perintah ${label} ke ${target_info}..."
        local cmd; [[ "$action" == "lock" ]] && cmd="disable" || cmd="enable"
        local result; result=$(remote_vmess_agent "$target" "$cmd" "$username")
        local ok_key="${cmd^^}-OK"
        if [[ "$result" == ${ok_key}* ]]; then
            print_ok "Akun '${username}' berhasil di-${action} di ${target_info}"
        else
            print_error "Gagal: ${result}"
        fi
    fi

    press_any_key
}

manage_vmess_lock
