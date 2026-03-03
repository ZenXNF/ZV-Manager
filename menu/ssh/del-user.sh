#!/bin/bash
# ============================================================
#   ZV-Manager - Delete SSH User (Local + Remote)
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/utils/remote.sh

del_ssh_user() {
    local target
    target=$(get_target_server)
    local target_info
    target_info=$(target_display)

    clear
    echo -e "${BCYAN} ┌─────────────────────────────────────────────┐${NC}"
    echo -e " │            ${BWHITE}HAPUS AKUN SSH${NC}                    │"
    echo -e "${BCYAN} └─────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BWHITE}Target :${NC} ${BGREEN}${target_info}${NC}"
    echo ""
    read -rp "  Username yang akan dihapus: " username
    echo ""

    if [[ -z "$username" ]]; then
        print_error "Username tidak boleh kosong!"
        press_any_key
        return
    fi

    if ! confirm "Yakin hapus user '$username' dari ${target_info}?"; then
        print_info "Dibatalkan"
        press_any_key
        return
    fi

    # LOCAL
    if is_local_target; then
        if ! user_exists "$username"; then
            print_error "Username '$username' tidak ditemukan!"
            press_any_key
            return
        fi

        pkill -u "$username" &>/dev/null
        userdel -r "$username" &>/dev/null 2>&1
        rm -f "/etc/zv-manager/accounts/ssh/${username}.conf"
        print_ok "User '$username' berhasil dihapus"

    # REMOTE
    else
        print_info "Menghapus akun di ${target_info}..."
        local result
        result=$(remote_agent "$target" "del" "$username")

        if [[ "$result" == DEL-OK* ]]; then
            print_ok "User '$username' berhasil dihapus dari ${target_info}"
        elif [[ "$result" == DEL-ERR* ]]; then
            print_error "Gagal: ${result#DEL-ERR|}"
        elif [[ "$result" == REMOTE-ERR* ]]; then
            print_error "${result#REMOTE-ERR|}"
        else
            print_error "Response tidak dikenal: ${result}"
        fi
    fi

    press_any_key
}

del_ssh_user
