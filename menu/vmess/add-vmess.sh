#!/bin/bash
# ============================================================
#   ZV-Manager - Buat Akun VMess
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/core/vmess.sh

add_vmess() {
    clear
    echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
    echo -e " │           ${BWHITE}BUAT AKUN VMESS${NC}                  │"
    echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
    echo ""

    if ! xray_installed; then
        print_error "Xray-core belum diinstall! Pasang dulu via System → Install Xray."
        press_any_key; return
    fi

    local domain
    domain=$(cat /etc/zv-manager/domain 2>/dev/null)
    echo -e "  ${BWHITE}Domain    :${NC} ${BYELLOW}${domain}${NC}"
    echo ""

    # Input username
    local username
    read -rp "  Username [kosongkan = auto]: " username
    if [[ -z "$username" ]]; then
        username=$(gen_vmess_username)
    else
        # Sanitasi: hanya huruf, angka, strip
        username=$(echo "$username" | tr -dc 'a-zA-Z0-9-_')
    fi

    if [[ -f "${VMESS_DIR}/${username}.conf" ]]; then
        print_error "Username '${username}' sudah digunakan!"
        press_any_key; return
    fi

    # Input durasi
    local exp_days
    read -rp "  Durasi (hari) [default: 30]: " exp_days
    exp_days="${exp_days:-30}"
    if ! [[ "$exp_days" =~ ^[0-9]+$ ]] || [[ "$exp_days" -lt 1 ]]; then
        print_error "Durasi tidak valid!"
        press_any_key; return
    fi

    echo ""
    print_info "Membuat akun VMess..."
    vmess_create "$username" "$exp_days"

    # Tampilkan info akun
    local uuid
    uuid=$(grep "^UUID=" "${VMESS_DIR}/${username}.conf" | cut -d= -f2 | tr -d '"')
    local exp_date
    exp_date=$(grep "^EXPIRED_DATE=" "${VMESS_DIR}/${username}.conf" | cut -d= -f2 | tr -d '"')

    local url_ws_tls
    url_ws_tls=$(vmess_url "$uuid" "$domain" "443" "tls" "ws" "/vmess" "${username}-TLS")
    local url_ws_http
    url_ws_http=$(vmess_url "$uuid" "$domain" "80" "none" "ws" "/vmess" "${username}-HTTP")
    local url_grpc
    url_grpc=$(vmess_url "$uuid" "$domain" "8443" "tls" "grpc" "vmess-grpc" "${username}-gRPC")

    clear
    echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
    echo -e " │         ${BWHITE}AKUN VMESS BERHASIL DIBUAT${NC}          │"
    echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BWHITE}Username  :${NC} ${BYELLOW}${username}${NC}"
    echo -e "  ${BWHITE}UUID      :${NC} ${BYELLOW}${uuid}${NC}"
    echo -e "  ${BWHITE}Domain    :${NC} ${BYELLOW}${domain}${NC}"
    echo -e "  ${BWHITE}Expired   :${NC} ${BYELLOW}${exp_date}${NC} (${exp_days} hari)"
    echo ""
    echo -e "  ${BWHITE}Port TLS  :${NC} 443    ${BWHITE}Port HTTP :${NC} 80    ${BWHITE}gRPC :${NC} 8443"
    echo -e "  ${BWHITE}Path WS   :${NC} /vmess ${BWHITE}Path gRPC:${NC} vmess-grpc"
    echo ""
    echo -e "  ${BCYAN}── URL VMess TLS ──${NC}"
    echo -e "  ${BYELLOW}${url_ws_tls}${NC}"
    echo ""
    echo -e "  ${BCYAN}── URL VMess HTTP ──${NC}"
    echo -e "  ${BYELLOW}${url_ws_http}${NC}"
    echo ""
    echo -e "  ${BCYAN}── URL VMess gRPC ──${NC}"
    echo -e "  ${BYELLOW}${url_grpc}${NC}"
    echo ""
    press_any_key
}

add_vmess
