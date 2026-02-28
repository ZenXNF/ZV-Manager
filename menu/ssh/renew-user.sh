#!/bin/bash
# ============================================================
#   ZV-Manager - Renew SSH User
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh

renew_ssh_user() {
    clear
    echo -e "${BCYAN} ┌─────────────────────────────────────────────┐${NC}"
    echo -e " │          ${BWHITE}PERPANJANG AKUN SSH${NC}                  │"
    echo -e "${BCYAN} └─────────────────────────────────────────────┘${NC}"
    echo ""
    read -rp "  Username   : " username
    read -rp "  Tambah hari: " days
    echo ""

    if [[ -z "$username" || -z "$days" ]]; then
        print_error "Input tidak boleh kosong!"
        press_any_key
        return
    fi

    if ! user_exists "$username"; then
        print_error "Username '$username' tidak ditemukan!"
        press_any_key
        return
    fi

    # Hitung expired baru dari hari ini
    local new_exp
    new_exp=$(expired_date "$days")

    # Update expired di sistem
    chage -E "$new_exp" "$username" &>/dev/null

    # Update file conf
    local conf_file="/etc/zv-manager/accounts/ssh/${username}.conf"
    if [[ -f "$conf_file" ]]; then
        sed -i "s/^EXPIRED=.*/EXPIRED=${new_exp}/" "$conf_file"
    fi

    print_ok "Akun '$username' diperpanjang hingga: $new_exp"
    press_any_key
}

renew_ssh_user
