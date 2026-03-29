#!/bin/bash
source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/utils/remote.sh
ZIVPN_ACCT_DIR="/etc/zv-manager/accounts/zivpn"
del_zivpn() {
    clear; _sep; _grad " HAPUS AKUN ZIVPN" 0 210 255 160 80 255; _sep; echo ""
    local confs=()
    for conf in "${ZIVPN_ACCT_DIR}"/*.conf; do [[ -f "$conf" ]] && confs+=("$conf"); done
    [[ ${#confs[@]} -eq 0 ]] && { print_error "Belum ada akun ZiVPN."; press_any_key; return; }
    local i=1
    for conf in "${confs[@]}"; do
        unset USERNAME EXPIRED_DATE SERVER; source "$conf"
        echo -e "  ${BGREEN}[${i}]${NC} ${BWHITE}${USERNAME}${NC} — ${SERVER:-local} — exp: ${EXPIRED_DATE}"; i=$((i+1))
    done
    echo ""; echo -e "  ${BRED}[0]${NC} Kembali"; echo ""
    read -rp "  Pilih akun yang akan dihapus: " choice
    [[ "$choice" == "0" ]] && return
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 || "$choice" -gt ${#confs[@]} ]]; then
        print_error "Pilihan tidak valid!"; press_any_key; return
    fi
    unset USERNAME SERVER; source "${confs[$((choice-1))]}"
    echo ""; read -rp "  Yakin hapus akun '${USERNAME}'? [y/n]: " confirm
    [[ "${confirm,,}" != "y" ]] && return
    print_info "Menghapus akun ${USERNAME}..."
    local result; result=$(remote_zivpn_agent "${SERVER:-local}" del "$USERNAME")
    if echo "$result" | grep -q "^DEL-OK"; then
        rm -f "${confs[$((choice-1))]}"; print_ok "Akun '${USERNAME}' berhasil dihapus!"
    else print_error "Gagal hapus: ${result}"; fi
    press_any_key
}
del_zivpn
