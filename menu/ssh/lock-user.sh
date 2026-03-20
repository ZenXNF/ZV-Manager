#!/bin/bash
# ============================================================
#   ZV-Manager - Lock SSH User (Local + Remote)
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/utils/remote.sh

action=${1:-lock}

manage_user_lock() {
    local target
    target=$(get_target_server)
    local target_info
    target_info=$(target_display)

    clear
    local label
    [[ "$action" == "lock" ]] && label="LOCK" || label="UNLOCK"

    _sep
    _grad " ${BWHITE}${label} AKUN SSH${NC}" 255 0 127 0 210 255
    _sep
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

        if [[ "$action" == "lock" ]]; then
            passwd -l "$username" &>/dev/null
            pkill -u "$username" &>/dev/null
            print_ok "Akun '$username' berhasil di-lock"
        else
            passwd -u "$username" &>/dev/null
            print_ok "Akun '$username' berhasil di-unlock"
        fi

    # REMOTE
    else
        print_info "Mengirim perintah ${label} ke ${target_info}..."
        local result
        result=$(remote_agent "$target" "$action" "$username")

        local ok_prefix="${action^^}-OK"
        local err_prefix="${action^^}-ERR"

        if [[ "$result" == ${ok_prefix}* ]]; then
            print_ok "Akun '$username' berhasil di-${action} di ${target_info}"
        elif [[ "$result" == ${err_prefix}* ]]; then
            print_error "Gagal: ${result#${err_prefix}|}"
        elif [[ "$result" == REMOTE-ERR* ]]; then
            print_error "${result#REMOTE-ERR|}"
        else
            print_error "Response tidak dikenal: ${result}"
        fi
    fi

    press_any_key
}

manage_user_lock
