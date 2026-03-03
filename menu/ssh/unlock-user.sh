#!/bin/bash
# ============================================================
#   ZV-Manager - Unlock SSH User (Local + Remote)
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/utils/remote.sh

action=unlock

manage_user_lock() {
    local target
    target=$(get_target_server)
    local target_info
    target_info=$(target_display)

    clear
    echo -e "${BCYAN} ┌─────────────────────────────────────────────┐${NC}"
    echo -e " │              ${BWHITE}UNLOCK AKUN SSH${NC}                  │"
    echo -e "${BCYAN} └─────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BWHITE}Target :${NC} ${BGREEN}${target_info}${NC}"
    echo ""
    read -rp "  Username: " username
    echo ""

    if [[ -z "$username" ]]; then
        print_error "Username tidak boleh kosong!"
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
        passwd -u "$username" &>/dev/null
        print_ok "Akun '$username' berhasil di-unlock"

    # REMOTE
    else
        print_info "Mengirim perintah UNLOCK ke ${target_info}..."
        local result
        result=$(remote_agent "$target" "unlock" "$username")

        if [[ "$result" == UNLOCK-OK* ]]; then
            print_ok "Akun '$username' berhasil di-unlock di ${target_info}"
        elif [[ "$result" == UNLOCK-ERR* ]]; then
            print_error "Gagal: ${result#UNLOCK-ERR|}"
        elif [[ "$result" == REMOTE-ERR* ]]; then
            print_error "${result#REMOTE-ERR|}"
        else
            print_error "Response tidak dikenal: ${result}"
        fi
    fi

    press_any_key
}

manage_user_lock
