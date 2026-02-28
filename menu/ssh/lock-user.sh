#!/bin/bash
# ============================================================
#   ZV-Manager - Lock / Unlock SSH User
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh

action=${1:-lock}

manage_user_lock() {
    clear
    local label
    [[ "$action" == "lock" ]] && label="LOCK" || label="UNLOCK"

    echo -e "${BCYAN} ┌─────────────────────────────────────────────┐${NC}"
    echo -e " │              ${BWHITE}${label} AKUN SSH${NC}                   │"
    echo -e "${BCYAN} └─────────────────────────────────────────────┘${NC}"
    echo ""
    read -rp "  Username: " username
    echo ""

    if [[ -z "$username" ]]; then
        print_error "Username tidak boleh kosong!"
        press_any_key
        return
    fi

    if ! user_exists "$username"; then
        print_error "Username '$username' tidak ditemukan!"
        press_any_key
        return
    fi

    if [[ "$action" == "lock" ]]; then
        passwd -l "$username" &>/dev/null
        pkill -u "$username" &>/dev/null
        print_ok "Akun '$username' berhasil di-lock"
    else
        passwd -u "$username" &>/dev/null
        print_ok "Akun '$username' berhasil di-unlock"
    fi

    press_any_key
}

manage_user_lock
