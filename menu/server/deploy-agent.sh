#!/bin/bash
# ============================================================
#   ZV-Manager - Deploy Agent ke Remote Server
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/utils/remote.sh

SERVER_DIR="/etc/zv-manager/servers"

deploy_agent_menu() {
    clear
    _sep
    _grad " DEPLOY AGENT KE REMOTE SERVER" 255 0 127 0 210 255
    _sep
    echo ""
    echo -e "  ${BYELLOW}zv-agent memungkinkan manajemen akun SSH dari jarak jauh.${NC}"
    echo -e "  ${BYELLOW}Install sekali, lalu kelola remote VPS langsung dari sini.${NC}"
    echo ""

    # Kumpulkan server remote (non-lokal)
    local local_ip
    local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null)

    local count=0
    local snames=()
    for conf in "${SERVER_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue
        [[ "$conf" == *.tg.conf ]] && continue
        unset NAME IP PORT USER
        source "$conf"
        [[ "$IP" == "$local_ip" ]] && continue
        count=$((count + 1))
        snames+=("$NAME")
        local _dip="${IP:-${local_ip}}"
        local _dport="${PORT:-22}"
        echo -e "  ${BGREEN}[${count}]${NC} ${BWHITE}${NAME}${NC} — ${USER:-root}@${_dip}:${_dport}"
    done

    if [[ $count -eq 0 ]]; then
        print_error "Tidak ada server remote! Tambahkan server dulu via menu Tambah Server."
        press_any_key
        return
    fi

    echo ""
    echo -e "  ${BRED}[0]${NC} Kembali"
    echo ""
    read -rp "  Pilih server untuk deploy agent: " choice

    [[ "$choice" == "0" ]] && return

    local chosen="${snames[$((choice-1))]}"
    if [[ -z "$chosen" ]]; then
        print_error "Pilihan tidak valid!"
        press_any_key
        return
    fi

    # Baca info server
    unset NAME IP PORT USER PASS
    source "${SERVER_DIR}/${chosen}.conf"

    echo ""
    print_info "Mengupload zv-agent ke ${NAME} (${IP}:${PORT})..."
    echo ""

    local result
    result=$(deploy_agent "$chosen")

    if [[ "$result" == "DEPLOY-OK" ]]; then
        print_ok "zv-agent berhasil diinstall di ${NAME}!"
        echo ""
        echo -e "  ${BWHITE}Server ${NAME} siap digunakan sebagai remote target.${NC}"
        echo -e "  ${BYELLOW}Pilih server ini di Menu SSH saat membuat/mengelola akun.${NC}"
    else
        local reason="${result#DEPLOY-ERR|}"
        print_error "Deploy gagal: ${reason}"
    fi

    press_any_key
}

deploy_agent_menu
