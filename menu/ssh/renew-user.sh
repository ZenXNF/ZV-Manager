#!/bin/bash
# ============================================================
#   ZV-Manager - Renew SSH User (Local + Remote)
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/utils/remote.sh

renew_ssh_user() {
    local target
    target=$(get_target_server)
    local target_info
    target_info=$(target_display)

    clear
    echo -e "${BCYAN} ┌─────────────────────────────────────────────┐${NC}"
    echo -e " │          ${BWHITE}PERPANJANG AKUN SSH${NC}                  │"
    echo -e "${BCYAN} └─────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BWHITE}Target :${NC} ${BGREEN}${target_info}${NC}"
    echo ""
    read -rp "  Username   : " username
    read -rp "  Tambah hari: " days
    echo ""

    if [[ -z "$username" || -z "$days" ]]; then
        print_error "Input tidak boleh kosong!"
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

        local new_exp
        new_exp=$(expired_date "$days")
        chage -E "$new_exp" "$username" &>/dev/null

        local conf_file="/etc/zv-manager/accounts/ssh/${username}.conf"
        if [[ -f "$conf_file" ]]; then
            local new_exp_ts; new_exp_ts=$(date -d "$new_exp" +%s 2>/dev/null || echo "")
            sed -i "s/^EXPIRED=.*/EXPIRED=${new_exp}/" "$conf_file"
            [[ -n "$new_exp_ts" ]] && sed -i "s/^EXPIRED_TS=.*/EXPIRED_TS=${new_exp_ts}/" "$conf_file"
        fi

        print_ok "Akun '$username' diperpanjang hingga: $new_exp"

    # REMOTE
    else
        print_info "Memperpanjang akun di ${target_info}..."
        local result
        result=$(remote_agent "$target" "renew" "$username" "$days")

        if [[ "$result" == RENEW-OK* ]]; then
            IFS='|' read -r _ r_user r_exp <<< "$result"
            print_ok "Akun '$r_user' diperpanjang hingga: $r_exp"
        elif [[ "$result" == RENEW-ERR* ]]; then
            print_error "Gagal: ${result#RENEW-ERR|}"
        elif [[ "$result" == REMOTE-ERR* ]]; then
            print_error "${result#REMOTE-ERR|}"
        else
            print_error "Response tidak dikenal: ${result}"
        fi
    fi

    press_any_key
}

renew_ssh_user
