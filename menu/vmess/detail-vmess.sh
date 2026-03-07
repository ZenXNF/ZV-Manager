#!/bin/bash
# ============================================================
#   ZV-Manager - Detail Akun VMess
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/core/vmess.sh

detail_vmess() {
    clear
    echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
    echo -e " │           ${BWHITE}DETAIL AKUN VMESS${NC}                │"
    echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
    echo ""

    local count=0
    local usernames=()
    for conf in "${VMESS_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue
        unset USERNAME EXPIRED_DATE IS_TRIAL
        source "$conf"
        count=$((count + 1))
        usernames+=("$USERNAME")
        echo -e "  ${BGREEN}[${count}]${NC} ${USERNAME} — exp: ${EXPIRED_DATE}"
    done

    if [[ $count -eq 0 ]]; then
        print_error "Belum ada akun VMess."
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
    local conf="${VMESS_DIR}/${selected}.conf"

    unset USERNAME UUID DOMAIN EXPIRED_DATE EXPIRED_TS IS_TRIAL CREATED
    source "$conf"

    local now_ts
    now_ts=$(date +%s)
    local sisa=$(( (EXPIRED_TS - now_ts) / 86400 ))
    [[ $sisa -lt 0 ]] && sisa=0

    local url_ws_tls
    url_ws_tls=$(vmess_url "$UUID" "$DOMAIN" "443" "tls" "ws" "/vmess" "${USERNAME}-TLS")
    local url_ws_http
    url_ws_http=$(vmess_url "$UUID" "$DOMAIN" "80" "none" "ws" "/vmess" "${USERNAME}-HTTP")
    local url_grpc
    url_grpc=$(vmess_url "$UUID" "$DOMAIN" "443" "tls" "grpc" "vmess-grpc" "${USERNAME}-gRPC")

    clear
    echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
    echo -e " │         ${BWHITE}INFO AKUN — ${USERNAME}${NC}"
    echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BWHITE}Username  :${NC} ${BYELLOW}${USERNAME}${NC}"
    echo -e "  ${BWHITE}UUID      :${NC} ${BYELLOW}${UUID}${NC}"
    echo -e "  ${BWHITE}Domain    :${NC} ${BYELLOW}${DOMAIN}${NC}"
    echo -e "  ${BWHITE}Dibuat    :${NC} ${CREATED}"
    echo -e "  ${BWHITE}Expired   :${NC} ${BYELLOW}${EXPIRED_DATE}${NC} (sisa ${sisa} hari)"
    echo -e "  ${BWHITE}Port TLS  :${NC} 443 · ${BWHITE}HTTP:${NC} 80 · ${BWHITE}gRPC:${NC} 443 (TLS)"
    echo -e "  ${BWHITE}Path WS   :${NC} /vmess · ${BWHITE}gRPC:${NC} vmess-grpc"
    echo ""
    echo -e "  ${BCYAN}── VMess TLS ──${NC}"
    echo "  $url_ws_tls"
    echo ""
    echo -e "  ${BCYAN}── VMess HTTP ──${NC}"
    echo "  $url_ws_http"
    echo ""
    echo -e "  ${BCYAN}── VMess gRPC ──${NC}"
    echo "  $url_grpc"
    echo ""
    press_any_key
}

detail_vmess
