#!/bin/bash
# ============================================================
#   ZV-Manager - Delete SSH User
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh

del_ssh_user() {
    clear
    echo -e "${BCYAN} ┌─────────────────────────────────────────────┐${NC}"
    echo -e " │            ${BWHITE}HAPUS AKUN SSH${NC}                    │"
    echo -e "${BCYAN} └─────────────────────────────────────────────┘${NC}"
    echo ""
    read -rp "  Username yang akan dihapus: " username
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

    if confirm "Yakin hapus user '$username'?"; then
        # Kill semua session aktif
        pkill -u "$username" &>/dev/null

        # Hapus user Linux
        userdel -r "$username" &>/dev/null 2>&1

        # Hapus file akun
        rm -f "/etc/zv-manager/accounts/ssh/${username}.conf"

        print_ok "User '$username' berhasil dihapus"
    else
        print_info "Dibatalkan"
    fi

    press_any_key
}

del_ssh_user
