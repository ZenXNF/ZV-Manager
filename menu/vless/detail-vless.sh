#!/bin/bash
# ============================================================
#   ZV-Manager - Detail Akun VLESS
# ============================================================
source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/core/vless.sh

detail_vless() {
    clear
    _sep
    _grad " DETAIL AKUN VLESS" 0 210 255 160 80 255
    _sep
    echo ""

    local count=0
    local usernames=()
    for conf in "${VLESS_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue
        unset USERNAME EXPIRED_DATE IS_TRIAL
        source "$conf"
        count=$((count + 1))
        usernames+=("$USERNAME")
        echo -e "  ${BGREEN}[${count}]${NC} ${USERNAME} — exp: ${EXPIRED_DATE}"
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
        print_error "Pilihan tidak valid!"
        press_any_key; return
    fi

    local selected="${usernames[$((choice-1))]}"
    local conf="${VLESS_DIR}/${selected}.conf"

    unset USERNAME UUID DOMAIN EXPIRED_DATE EXPIRED_TS IS_TRIAL CREATED SERVER
    source "$conf"

    local now_ts; now_ts=$(date +%s)
    local sisa=$(( (EXPIRED_TS - now_ts) / 86400 ))
    [[ $sisa -lt 0 ]] && sisa=0

    local url_ws_tls; url_ws_tls=$(vless_url "$UUID" "$DOMAIN" "443" "tls" "ws" "/vless" "${USERNAME}-TLS")
    local url_ws_http; url_ws_http=$(vless_url "$UUID" "$DOMAIN" "80" "none" "ws" "/vless" "${USERNAME}-HTTP")
    local url_grpc; url_grpc=$(vless_url "$UUID" "$DOMAIN" "8443" "tls" "grpc" "vless-grpc" "${USERNAME}-gRPC")

    clear
    _sep
    _grad " DETAIL: ${selected}" 0 210 255 160 80 255
    _sep
    echo ""
    echo -e "  ${BWHITE}Username  :${NC} ${BYELLOW}${USERNAME}${NC}"
    echo -e "  ${BWHITE}UUID      :${NC} ${BYELLOW}${UUID}${NC}"
    echo -e "  ${BWHITE}Domain    :${NC} ${BYELLOW}${DOMAIN}${NC}"
    echo -e "  ${BWHITE}Server    :${NC} ${SERVER:-local}"
    echo -e "  ${BWHITE}Dibuat    :${NC} ${CREATED}"
    echo -e "  ${BWHITE}Expired   :${NC} ${BYELLOW}${EXPIRED_DATE}${NC} (sisa ${sisa} hari)"
    echo -e "  ${BWHITE}Port TLS  :${NC} 443 · ${BWHITE}HTTP:${NC} 80 · ${BWHITE}gRPC:${NC} 8443"
    echo -e "  ${BWHITE}Path WS   :${NC} /vless · ${BWHITE}gRPC:${NC} vless-grpc"
    echo ""
    echo -e "  ${BCYAN}── VLESS TLS (WS) ──${NC}"
    echo "  $url_ws_tls"
    echo ""
    echo -e "  ${BCYAN}── VLESS HTTP (WS) ──${NC}"
    echo "  $url_ws_http"
    echo ""
    echo -e "  ${BCYAN}── VLESS gRPC ──${NC}"
    echo "  $url_grpc"
    echo ""
    press_any_key
}

detail_vless
