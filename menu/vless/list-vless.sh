#!/bin/bash
# ============================================================
#   ZV-Manager - List Akun VLESS
# ============================================================
source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/core/vless.sh

list_vless() {
    clear
    _sep
    _grad " LIST AKUN VLESS" 0 210 255 160 80 255
    _sep
    echo ""

    local now_ts; now_ts=$(date +%s)
    local count=0

    printf "  %-20s %-12s %-10s %s\n" "USERNAME" "EXPIRED" "STATUS" "UUID"
    echo -e "  ${BCYAN}────────────────────────────────────────────────${NC}"

    for conf in "${VLESS_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue
        unset USERNAME UUID EXPIRED_DATE EXPIRED_TS IS_TRIAL SERVER
        source "$conf"
        count=$((count + 1))

        local status_label status_color
        # Trial expired → hapus sekarang juga, jangan tampilkan
        if [[ "$IS_TRIAL" == "1" && -n "$EXPIRED_TS" && "$EXPIRED_TS" -le "$now_ts" ]]; then
            source /etc/zv-manager/utils/remote.sh 2>/dev/null
            remote_vless_agent "${SERVER:-local}" del "$USERNAME" &>/dev/null
            rm -f "$conf" "/tmp/zv-tg-state/vless_${USERNAME}.notified"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] VLESS TRIAL expired-on-list: $USERNAME" \
                >> /var/log/zv-manager/install.log 2>/dev/null
            continue
        fi
        if [[ -n "$EXPIRED_TS" && "$EXPIRED_TS" -le "$now_ts" ]]; then
            status_label="EXPIRED"
            status_color="$BRED"
        elif [[ "$IS_TRIAL" == "1" ]]; then
            status_label="TRIAL"
            status_color="$BYELLOW"
        else
            status_label="AKTIF"
            status_color="$BGREEN"
        fi

        printf "  %-20s %-12s " "${USERNAME}" "${EXPIRED_DATE}"
        echo -ne "${status_color}${status_label}${NC}"
        printf "    %s\n" "${UUID:0:18}..."
    done

    echo ""
    if [[ $count -eq 0 ]]; then
        echo -e "  ${BYELLOW}Belum ada akun VLESS.${NC}"
    else
        echo -e "  Total: ${BWHITE}${count}${NC} akun"
    fi
    echo ""
    press_any_key
}

list_vless
