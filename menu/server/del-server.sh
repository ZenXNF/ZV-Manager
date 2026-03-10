#!/bin/bash
# ============================================================
#   ZV-Manager - Hapus Server
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh

SERVER_DIR="/etc/zv-manager/servers"

del_server() {
    clear
    echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
    echo -e " │              ${BWHITE}HAPUS SERVER${NC}                    │"
    echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
    echo ""

    local _ipvps; _ipvps=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null | tr -d "[:space:]")
    local count=0
    for conf in "${SERVER_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue
        [[ "$conf" == *.tg.conf ]] && continue
        unset NAME IP DOMAIN PORT
        source "$conf"
        count=$((count + 1))
        local _disp_ip="${IP:-${_ipvps}}"
        local _disp_port="${PORT:-22}"
        echo -e "  ${BGREEN}[${count}]${NC} ${NAME} — ${_disp_ip}:${_disp_port}"
    done

    if [[ $count -eq 0 ]]; then
        print_error "Belum ada server yang ditambahkan!"
        press_any_key; return
    fi

    echo ""
    read -rp "  Nama server yang akan dihapus: " sname
    echo ""

    if [[ -z "$sname" ]]; then
        print_error "Nama server tidak boleh kosong!"
        press_any_key; return
    fi

    local conf_file="${SERVER_DIR}/${sname}.conf"
    local tg_conf_file="${SERVER_DIR}/${sname}.tg.conf"

    if [[ ! -f "$conf_file" ]]; then
        print_error "Server '${sname}' tidak ditemukan!"
        press_any_key; return
    fi

    echo -e "  ${BYELLOW}⚠  Yakin ingin menghapus server '${sname}'?${NC}"
    read -rp "  Konfirmasi (y/N): " confirm
    echo ""
    [[ "${confirm,,}" != "y" ]] && { echo -e "  ${BYELLOW}Dibatalkan.${NC}"; press_any_key; return; }

    rm -f "$conf_file" "$tg_conf_file"
    print_ok "Server '${sname}' berhasil dihapus."
    press_any_key
}

del_server
