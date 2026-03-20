#!/bin/bash
# ============================================================
#   ZV-Manager - List Akun VMess
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/core/vmess.sh

list_vmess() {
    clear
    _sep
    _grad " LIST AKUN VMESS" 255 0 127 0 210 255
    _sep
    echo ""

    local now_ts
    now_ts=$(date +%s)
    local count=0

    printf "  %-20s %-12s %-12s %s\n" "USERNAME" "EXPIRED" "STATUS" "UUID"
    echo -e "  ${BCYAN}────────────────────────────────────────────────${NC}"

    for conf in "${VMESS_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue
        unset USERNAME UUID EXPIRED_DATE EXPIRED_TS IS_TRIAL
        source "$conf"
        count=$((count + 1))

        local status_label status_color
        if [[ "$IS_TRIAL" == "1" ]]; then
            status_label="TRIAL"
            status_color="$BYELLOW"
        elif [[ "$EXPIRED_TS" -gt "$now_ts" ]]; then
            status_label="AKTIF"
            status_color="$BGREEN"
        else
            status_label="EXPIRED"
            status_color="$BRED"
        fi

        printf "  %-20s %-12s " "${USERNAME}" "${EXPIRED_DATE}"
        echo -ne "${status_color}${status_label}${NC}"
        printf "    %s\n" "${UUID:0:18}..."
    done

    echo ""
    if [[ $count -eq 0 ]]; then
        echo -e "  ${BYELLOW}Belum ada akun VMess.${NC}"
    else
        echo -e "  Total: ${BWHITE}${count}${NC} akun"
    fi
    echo ""
    press_any_key
}

list_vmess
