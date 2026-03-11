#!/bin/bash
# ============================================================
#   ZV-Manager - Connect ke Server
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh

SERVER_DIR="/etc/zv-manager/servers"

connect_server() {
    clear
    echo -e "${BCYAN} ┌─────────────────────────────────────────────┐${NC}"
    echo -e " │           ${BWHITE}CONNECT KE SERVER${NC}                  │"
    echo -e "${BCYAN} └─────────────────────────────────────────────┘${NC}"
    echo ""

    local _ipvps; _ipvps=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null | tr -d "[:space:]")
    local count=0
    local server_confs=()
    for conf in "${SERVER_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue
        [[ "$conf" == *.tg.conf ]] && continue
        unset NAME IP DOMAIN PORT USER
        source "$conf"
        count=$((count + 1))
        server_confs+=("$conf")
        local _dip="${IP:-${_ipvps}}"
        local _dport="${PORT:-22}"
        local disp_domain="${DOMAIN:-${_dip}}"
        echo -e "  ${BGREEN}[${count}]${NC} ${BWHITE}${NAME}${NC} — ${USER:-root}@${disp_domain}:${_dport}"
    done

    if [[ $count -eq 0 ]]; then
        print_error "Belum ada server! Tambahkan dulu via menu Tambah Server."
        press_any_key
        return
    fi

    echo ""
    read -rp "  Pilih nomor server: " choice

    local chosen_conf="${server_confs[$((choice-1))]}"
    if [[ -z "$chosen_conf" || ! -f "$chosen_conf" ]]; then
        print_error "Pilihan tidak valid!"
        press_any_key
        return
    fi

    source /etc/zv-manager/utils/remote.sh 2>/dev/null
    _load_server_conf "$chosen_conf"
    local disp_domain="${DOMAIN:-$IP}"

    # Deteksi apakah server yang dipilih adalah VPS ini sendiri
    local local_ip
    local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null || curl -s --max-time 5 ipv4.icanhazip.com 2>/dev/null)

    local is_self=false
    if [[ "$IP" == "$local_ip" ]]; then
        is_self=true
    fi

    echo ""
    print_info "Menghubungkan ke ${NAME} (${USER}@${disp_domain}:${PORT})..."

    if [[ "$is_self" == true ]]; then
        echo -e "  ${BYELLOW}⚠ Ini adalah VPS lokal — membuka shell langsung (bukan SSH).${NC}"
        echo -e "  ${BYELLOW}  Ketik 'exit' atau 'menu' untuk kembali.${NC}"
        echo ""
        sleep 1
        # Buka bash shell langsung — hindari loop menu dari .profile
        bash --login -i
    else
        echo -e "  ${BYELLOW}Ketik 'exit' untuk kembali ke menu.${NC}"
        echo ""
        sleep 1

        if ! command -v sshpass &>/dev/null; then
            apt-get install -y sshpass &>/dev/null
        fi

        sshpass -p "$PASS" ssh \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=10 \
            -o ServerAliveInterval=30 \
            -o ServerAliveCountMax=3 \
            -p "$PORT" \
            "${USER}@${IP}"
    fi

    local exit_code=$?
    echo ""
    if [[ $exit_code -eq 0 ]]; then
        print_ok "Sesi ke '${NAME}' ditutup."
    else
        print_error "Koneksi ke '${NAME}' gagal atau terputus. (kode: ${exit_code})"
    fi

    press_any_key
}

connect_server
