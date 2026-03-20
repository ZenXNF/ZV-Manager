#!/bin/bash
# ============================================================
#   ZV-Manager - Edit Akun VLESS
# ============================================================
source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/utils/remote.sh
source /etc/zv-manager/core/vless.sh

edit_vless() {
    clear
    _sep
    _grad " EDIT AKUN VLESS" 0 210 255 160 80 255
    _sep
    echo ""

    local count=0
    local usernames=() servers=()
    for conf in "${VLESS_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue
        unset USERNAME EXPIRED_DATE IS_TRIAL SERVER
        source "$conf"
        count=$((count + 1))
        usernames+=("$USERNAME")
        servers+=("${SERVER:-local}")
        local trial_tag=""; [[ "$IS_TRIAL" == "1" ]] && trial_tag=" ${BYELLOW}[trial]${NC}"
        echo -e "  ${BGREEN}[${count}]${NC} ${USERNAME} — exp: ${EXPIRED_DATE} [${SERVER:-local}]${trial_tag}"
    done

    if [[ $count -eq 0 ]]; then
        print_error "Belum ada akun VLESS."
        press_any_key; return
    fi

    echo ""
    echo -e "  ${BRED}[0]${NC} Kembali"
    echo ""
    read -rp "  Pilih nomor akun: " choice
    [[ "$choice" == "0" ]] && return
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 || "$choice" -gt $count ]]; then
        print_error "Pilihan tidak valid!"; press_any_key; return
    fi

    local selected="${usernames[$((choice-1))]}"
    local sname="${servers[$((choice-1))]}"
    local conf="${VLESS_DIR}/${selected}.conf"
    unset USERNAME UUID DOMAIN EXPIRED_DATE EXPIRED_TS IS_TRIAL BW_LIMIT_GB
    source "$conf"

    clear
    _sep
    _grad " EDIT: ${selected}" 0 210 255 160 80 255
    _sep
    echo ""
    echo -e "  ${BWHITE}Server  :${NC} ${sname}"
    echo -e "  ${BWHITE}Expired :${NC} ${EXPIRED_DATE}"
    echo -e "  ${BWHITE}BW Limit:${NC} ${BW_LIMIT_GB:-0} GB"
    echo ""
    echo -e "  $(_grad '[1]' 0 210 255 160 80 255) Perpanjang (renew)"
    echo -e "  $(_grad '[2]' 0 210 255 160 80 255) Aktifkan akun"
    echo -e "  $(_grad '[3]' 0 210 255 160 80 255) Nonaktifkan akun"
    echo -e "  ${BRED}[0]${NC} Kembali"
    echo ""
    read -rp "  Pilih: " action

    case "$action" in
        1)
            read -rp "  Tambah berapa hari: " add_days
            if ! [[ "$add_days" =~ ^[0-9]+$ ]] || [[ "$add_days" -lt 1 ]]; then
                print_error "Hari tidak valid!"; press_any_key; return
            fi
            local result; result=$(remote_vless_agent "$sname" renew "$selected" "$add_days")
            if echo "$result" | grep -q "^RENEW-OK"; then
                local new_exp; new_exp=$(echo "$result" | cut -d'|' -f3)
                sed -i "s/^EXPIRED_DATE=.*/EXPIRED_DATE=\"${new_exp}\"/" "$conf"
                local new_ts; new_ts=$(date -d "$new_exp" +%s)
                sed -i "s/^EXPIRED_TS=.*/EXPIRED_TS=\"${new_ts}\"/" "$conf"
                print_ok "Akun diperpanjang hingga ${new_exp}!"
            else
                print_error "Gagal: ${result}"
            fi
            ;;
        2)
            local result; result=$(remote_vless_agent "$sname" enable "$selected")
            if echo "$result" | grep -q "^ENABLE-OK"; then
                [[ -f "${conf%.conf}.disabled" ]] && mv "${conf%.conf}.disabled" "$conf"
                print_ok "Akun ${selected} diaktifkan!"
            else
                print_error "Gagal: ${result}"
            fi
            ;;
        3)
            local result; result=$(remote_vless_agent "$sname" disable "$selected")
            if echo "$result" | grep -q "^DISABLE-OK"; then
                mv "$conf" "${conf%.conf}.disabled"
                print_ok "Akun ${selected} dinonaktifkan!"
            else
                print_error "Gagal: ${result}"
            fi
            ;;
        0) return ;;
        *) print_error "Pilihan tidak valid!" ;;
    esac

    press_any_key
}

edit_vless
