#!/bin/bash
source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/helpers.sh
ZIVPN_ACCT_DIR="/etc/zv-manager/accounts/zivpn"
detail_zivpn() {
    clear; _sep; _grad " DETAIL AKUN ZIVPN" 0 210 255 160 80 255; _sep; echo ""
    local confs=()
    for conf in "${ZIVPN_ACCT_DIR}"/*.conf; do [[ -f "$conf" ]] && confs+=("$conf"); done
    [[ ${#confs[@]} -eq 0 ]] && { print_error "Belum ada akun ZiVPN."; press_any_key; return; }
    local i=1
    for conf in "${confs[@]}"; do
        local u; u=$(grep "^USERNAME=" "$conf" | cut -d= -f2 | tr -d '"')
        echo -e "  ${BGREEN}[${i}]${NC} ${BWHITE}${u}${NC}"; i=$((i+1))
    done
    echo ""; echo -e "  ${BRED}[0]${NC} Kembali"; echo ""
    read -rp "  Pilih akun: " choice
    [[ "$choice" == "0" ]] && return
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 || "$choice" -gt ${#confs[@]} ]]; then
        print_error "Pilihan tidak valid!"; press_any_key; return
    fi
    unset USERNAME PASSWORD EXPIRED_DATE EXPIRED_TS SERVER DOMAIN
    source "${confs[$((choice-1))]}"
    clear; _sep; _grad " DETAIL ZIVPN: ${USERNAME}" 0 210 255 160 80 255; _sep; echo ""
    echo -e "  ${BWHITE}Username  :${NC} ${BYELLOW}${USERNAME}${NC}"
    echo -e "  ${BWHITE}ZiVPN PW  :${NC} ${BYELLOW}${PASSWORD}${NC}"
    echo -e "  ${BWHITE}Host      :${NC} ${BYELLOW}${DOMAIN}${NC}"
    echo -e "  ${BWHITE}Port UDP  :${NC} ${BYELLOW}5667${NC}"
    echo -e "  ${BWHITE}Obfs      :${NC} ${BYELLOW}zivpn${NC}"
    echo -e "  ${BWHITE}Server    :${NC} ${BYELLOW}${SERVER:-local}${NC}"
    echo -e "  ${BWHITE}Expired   :${NC} ${BYELLOW}${EXPIRED_DATE}${NC}"
    echo ""; press_any_key
}
detail_zivpn
