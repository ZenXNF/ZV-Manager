#!/bin/bash
source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/helpers.sh
ZIVPN_ACCT_DIR="/etc/zv-manager/accounts/zivpn"
list_zivpn() {
    clear; _sep; _grad " LIST AKUN ZIVPN UDP" 0 210 255 160 80 255; _sep; echo ""
    local now_ts; now_ts=$(date +%s); local count=0
    printf "  %-20s %-12s %-10s %s\n" "USERNAME" "EXPIRED" "STATUS" "SERVER"
    echo -e "  ${BCYAN}────────────────────────────────────────────────${NC}"
    for conf in "${ZIVPN_ACCT_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue
        unset USERNAME PASSWORD EXPIRED_DATE EXPIRED_TS IS_TRIAL SERVER
        source "$conf"
        # Trial expired → hapus langsung
        if [[ "$IS_TRIAL" == "1" && -n "$EXPIRED_TS" && "$EXPIRED_TS" -le "$now_ts" ]]; then
            source /etc/zv-manager/utils/remote.sh 2>/dev/null
            remote_zivpn_agent "${SERVER:-local}" del "$USERNAME" &>/dev/null
            rm -f "$conf"; continue
        fi
        count=$((count+1))
        local sl sc
        if [[ -n "$EXPIRED_TS" && "$EXPIRED_TS" -le "$now_ts" ]]; then sl="EXPIRED"; sc="$BRED"
        elif [[ "$IS_TRIAL" == "1" ]]; then sl="TRIAL"; sc="$BYELLOW"
        else sl="AKTIF"; sc="$BGREEN"; fi
        printf "  %-20s %-12s " "${USERNAME}" "${EXPIRED_DATE}"
        echo -ne "${sc}${sl}${NC}"; printf "    %s\n" "${SERVER:-local}"
    done
    echo ""
    [[ $count -eq 0 ]] && echo -e "  ${BYELLOW}Belum ada akun ZiVPN.${NC}" || echo -e "  Total: ${BWHITE}${count}${NC} akun"
    echo ""; press_any_key
}
list_zivpn
