#!/bin/bash
# ============================================================
#   ZV-Manager - Buat Akun VMess
# ============================================================
source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/utils/remote.sh
source /etc/zv-manager/core/vmess.sh

add_vmess() {
    clear
    _sep
    _grad " BUAT AKUN VMESS" 255 0 127 0 210 255
    _sep
    echo ""

    if ! xray_installed; then
        print_error "Xray-core belum diinstall! Pasang dulu via System → Install Xray."
        press_any_key; return
    fi

    # Pilih server (hanya vmess/both)
    local server_dir="/etc/zv-manager/servers"
    local local_ip; local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null)
    local count=0
    local snames=() sips=()

    for conf in "${server_dir}"/*.conf; do
        [[ -f "$conf" ]] || continue
        [[ "$conf" == *.tg.conf ]] && continue
        unset NAME IP SERVER_TYPE
        source "$conf"
        local tg_type; tg_type=$(grep "^TG_SERVER_TYPE=" "${server_dir}/${NAME}.tg.conf" 2>/dev/null | cut -d= -f2 | tr -d '"')
        tg_type="${tg_type:-both}"
        [[ "$tg_type" == "ssh" ]] && continue
        count=$((count + 1))
        snames+=("$NAME")
        sips+=("$IP")
        local mark=""; [[ "$IP" == "$local_ip" ]] && mark=" ${BYELLOW}[lokal]${NC}"
        echo -e "  ${BGREEN}[${count}]${NC} ${BWHITE}${NAME}${NC} — ${IP}${mark}"
    done

    if [[ $count -eq 0 ]]; then
        print_error "Belum ada server VMess. Tambah server dulu."
        press_any_key; return
    fi

    echo ""
    echo -e "  ${BRED}[0]${NC} Kembali"
    echo ""
    read -rp "  Pilih server: " schoice
    [[ "$schoice" == "0" ]] && return
    if ! [[ "$schoice" =~ ^[0-9]+$ ]] || [[ "$schoice" -lt 1 || "$schoice" -gt $count ]]; then
        print_error "Pilihan tidak valid!"; press_any_key; return
    fi

    local sname="${snames[$((schoice-1))]}"
    local sip="${sips[$((schoice-1))]}"
    local domain; domain=$(cat /etc/zv-manager/domain 2>/dev/null)

    echo ""
    echo -e "  ${BWHITE}Server    :${NC} ${BYELLOW}${sname}${NC}"
    echo -e "  ${BWHITE}Domain    :${NC} ${BYELLOW}${domain}${NC}"
    echo ""

    # Input username
    local username
    read -rp "  Username [kosongkan = auto]: " username
    if [[ -z "$username" ]]; then
        username=$(gen_vmess_username)
    else
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
        print_error "Durasi tidak valid!"; press_any_key; return
    fi

    echo ""
    print_info "Membuat akun VMess di server ${sname}..."

    local uuid; uuid=$(gen_uuid)
    local now_ts; now_ts=$(date +%s)
    local exp_ts=$(( now_ts + exp_days * 86400 ))
    local exp_date; exp_date=$(date -d "@${exp_ts}" +"%Y-%m-%d")

    # Simpan conf di brain
    mkdir -p "$VMESS_DIR"
    cat > "${VMESS_DIR}/${username}.conf" << CONFEOF
USERNAME="${username}"
UUID="${uuid}"
DOMAIN="${domain}"
EXPIRED_TS="${exp_ts}"
EXPIRED_DATE="${exp_date}"
CREATED="$(date +"%Y-%m-%d")"
IS_TRIAL="0"
TG_USER_ID="0"
SERVER="${sname}"
BW_LIMIT_GB="0"
BW_USED_BYTES="0"
BW_LAST_CHECK="0"
CONFEOF

    # Kirim ke Xray via agent
    local result; result=$(remote_vmess_agent "$sname" add "$username" "$uuid" "$exp_days" "0" "0")
    if echo "$result" | grep -q "^ADD-OK\|^ADD-ERR.*sudah ada"; then
        print_ok "Akun VMess berhasil dibuat!"
    else
        print_warning "Agent: ${result}"
        rm -f "${VMESS_DIR}/${username}.conf"
        press_any_key; return
    fi

    # Tampilkan info
    local url_ws_tls; url_ws_tls=$(vmess_url "$uuid" "$domain" "443" "tls" "ws" "/vmess" "${username}-TLS")
    local url_ws_http; url_ws_http=$(vmess_url "$uuid" "$domain" "80" "none" "ws" "/vmess" "${username}-HTTP")
    local url_grpc; url_grpc=$(vmess_url "$uuid" "$domain" "443" "tls" "grpc" "vmess-grpc" "${username}-gRPC")

    clear
    _sep
    _grad " AKUN VMESS BERHASIL DIBUAT" 255 0 127 0 210 255
    _sep
    echo ""
    echo -e "  ${BWHITE}Username  :${NC} ${BYELLOW}${username}${NC}"
    echo -e "  ${BWHITE}UUID      :${NC} ${BYELLOW}${uuid}${NC}"
    echo -e "  ${BWHITE}Domain    :${NC} ${BYELLOW}${domain}${NC}"
    echo -e "  ${BWHITE}Server    :${NC} ${BYELLOW}${sname}${NC}"
    echo -e "  ${BWHITE}Expired   :${NC} ${BYELLOW}${exp_date}${NC} (${exp_days} hari)"
    echo ""
    echo -e "  ${BCYAN}── VMess TLS (WS) ──${NC}"
    echo -e "  ${BYELLOW}${url_ws_tls}${NC}"
    echo ""
    echo -e "  ${BCYAN}── VMess HTTP (WS) ──${NC}"
    echo -e "  ${BYELLOW}${url_ws_http}${NC}"
    echo ""
    echo -e "  ${BCYAN}── VMess gRPC ──${NC}"
    echo -e "  ${BYELLOW}${url_grpc}${NC}"
    echo ""
    press_any_key
}

add_vmess
