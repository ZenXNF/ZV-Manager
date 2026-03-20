#!/bin/bash
# ============================================================
#   ZV-Manager - Perpanjang Akun VLESS
# ============================================================
source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/utils/remote.sh
source /etc/zv-manager/core/vless.sh

renew_vless() {
    local target; target=$(get_target_server)
    local target_info; target_info=$(target_display)

    clear
    _sep
    _grad " PERPANJANG AKUN VLESS" 0 210 255 160 80 255
    _sep
    echo ""
    echo -e "  ${BWHITE}Target :${NC} ${BGREEN}${target_info}${NC}"
    echo ""
    read -rp "  Username   : " username
    read -rp "  Tambah hari: " days
    echo ""

    if [[ -z "$username" || -z "$days" ]]; then
        print_error "Input tidak boleh kosong!"
        press_any_key; return
    fi

    if is_local_target; then
        local conf="/etc/zv-manager/accounts/vless/${username}.conf"
        if [[ ! -f "$conf" ]]; then
            print_error "Username '${username}' tidak ditemukan!"
            press_any_key; return
        fi
        local cur_exp; cur_exp=$(grep "^EXPIRED_TS=" "$conf" | cut -d= -f2 | tr -d '"' | tr -d '[:space:]')
        local now_ts; now_ts=$(date +%s)
        [[ -z "$cur_exp" || "$cur_exp" -lt "$now_ts" ]] && cur_exp=$now_ts
        local new_exp_ts=$(( cur_exp + days * 86400 ))
        local new_exp_date; new_exp_date=$(date -d "@${new_exp_ts}" +"%Y-%m-%d")
        local new_exp_display; new_exp_display=$(TZ="Asia/Jakarta" date -d "@${new_exp_ts}" +"%d %b %Y %H:%M WIB")
        sed -i "s/^EXPIRED_TS=.*/EXPIRED_TS=${new_exp_ts}/" "$conf"
        sed -i "s/^EXPIRED_DATE=.*/EXPIRED_DATE=${new_exp_date}/" "$conf"
        print_ok "Akun '${username}' diperpanjang hingga: ${new_exp_display}"
    else
        print_info "Memperpanjang VLESS di ${target_info}..."
        local result; result=$(remote_vless_agent "$target" renew "$username" "$days")
        if [[ "$result" == RENEW-OK* ]]; then
            IFS='|' read -r _ r_user r_exp <<< "$result"
            print_ok "Akun '${r_user}' diperpanjang hingga: ${r_exp}"
        elif [[ "$result" == RENEW-ERR* ]]; then
            print_error "Gagal: ${result#RENEW-ERR|}"
        else
            print_error "Response tidak dikenal: ${result}"
        fi
    fi

    press_any_key
}

renew_vless
