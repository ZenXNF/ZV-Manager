#!/bin/bash
# ============================================================
#   ZV-Manager - Connect ke Server
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/helpers.sh

SERVER_DIR="/etc/zv-manager/servers"

connect_server() {
    clear
    echo -e "${BCYAN} ┌─────────────────────────────────────────────┐${NC}"
    echo -e " │           ${BWHITE}CONNECT KE SERVER${NC}                  │"
    echo -e "${BCYAN} └─────────────────────────────────────────────┘${NC}"
    echo ""

    # Tampilkan daftar server
    local count=0
    declare -A server_map
    for conf in "${SERVER_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue
        source "$conf"
        count=$((count + 1))
        server_map[$count]="$conf"
        echo -e "  ${BGREEN}[${count}]${NC} ${NAME} — ${USER}@${IP}:${PORT}"
    done

    if [[ $count -eq 0 ]]; then
        print_error "Belum ada server! Tambahkan dulu via menu Tambah Server."
        press_any_key
        return
    fi

    echo ""
    read -rp "  Pilih nomor server: " choice

    local chosen_conf="${server_map[$choice]}"
    if [[ -z "$chosen_conf" || ! -f "$chosen_conf" ]]; then
        print_error "Pilihan tidak valid!"
        press_any_key
        return
    fi

    source "$chosen_conf"

    echo ""
    print_info "Menghubungkan ke ${NAME} (${USER}@${IP}:${PORT})..."
    echo -e "  ${BYELLOW}Ketik 'exit' atau 'logout' untuk kembali ke menu ini.${NC}"
    echo ""
    sleep 1

    # Cek apakah sshpass tersedia
    if ! command -v sshpass &>/dev/null; then
        print_info "Menginstall sshpass..."
        apt-get install -y sshpass &>/dev/null
    fi

    # Connect via SSH dengan password
    sshpass -p "$PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3 \
        -p "$PORT" \
        "${USER}@${IP}"

    local exit_code=$?
    echo ""
    if [[ $exit_code -eq 0 ]]; then
        print_ok "Koneksi ke '${NAME}' ditutup."
    else
        print_error "Koneksi ke '${NAME}' gagal atau terputus. (kode: ${exit_code})"
    fi

    press_any_key
}

connect_server
