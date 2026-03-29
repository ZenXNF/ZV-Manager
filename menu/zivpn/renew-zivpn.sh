#!/bin/bash
source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/utils/remote.sh
ZIVPN_ACCT_DIR="/etc/zv-manager/accounts/zivpn"
renew_zivpn() {
    clear; _sep; _grad " RENEW AKUN ZIVPN" 0 210 255 160 80 255; _sep; echo ""
    local confs=()
    for conf in "${ZIVPN_ACCT_DIR}"/*.conf; do [[ -f "$conf" ]] && confs+=("$conf"); done
    [[ ${#confs[@]} -eq 0 ]] && { print_error "Belum ada akun ZiVPN."; press_any_key; return; }
    local i=1
    for conf in "${confs[@]}"; do
        unset USERNAME EXPIRED_DATE; source "$conf"
        echo -e "  ${BGREEN}[${i}]${NC} ${BWHITE}${USERNAME}${NC} — exp: ${EXPIRED_DATE}"; i=$((i+1))
    done
    echo ""; echo -e "  ${BRED}[0]${NC} Kembali"; echo ""
    read -rp "  Pilih akun: " choice
    [[ "$choice" == "0" ]] && return
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 || "$choice" -gt ${#confs[@]} ]]; then
        print_error "Pilihan tidak valid!"; press_any_key; return
    fi
    unset USERNAME SERVER EXPIRED_DATE; source "${confs[$((choice-1))]}"
    read -rp "  Durasi baru (hari) [default: 30]: " new_days
    new_days="${new_days:-30}"
    [[ ! "$new_days" =~ ^[0-9]+$ || "$new_days" -lt 1 ]] && { print_error "Durasi tidak valid!"; press_any_key; return; }
    print_info "Renew akun ${USERNAME}..."
    local result; result=$(remote_zivpn_agent "${SERVER:-local}" renew "$USERNAME" "$new_days")
    if echo "$result" | grep -q "^RENEW-OK"; then
        local new_exp; new_exp=$(echo "$result" | cut -d'|' -f3)
        local new_ts; new_ts=$(date -d "$new_exp" +%s 2>/dev/null || echo "0")
        sed -i "s/^EXPIRED=.*/EXPIRED=\"${new_exp}\"/" "${confs[$((choice-1))]}"
        sed -i "s/^EXPIRED_TS=.*/EXPIRED_TS=\"${new_ts}\"/" "${confs[$((choice-1))]}"
        sed -i "s/^EXPIRED_DATE=.*/EXPIRED_DATE=\"${new_exp}\"/" "${confs[$((choice-1))]}"
        print_ok "Renew berhasil! Expired baru: ${new_exp}"
    else print_error "Renew gagal: ${result}"; fi
    press_any_key
}
renew_zivpn
