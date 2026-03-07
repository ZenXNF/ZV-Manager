#!/bin/bash
# ============================================================
#   ZV-Manager - Hapus Akun VMess
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/core/vmess.sh

del_vmess() {
    clear
    echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
    echo -e " │           ${BWHITE}HAPUS AKUN VMESS${NC}                 │"
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
        local trial_tag=""
        [[ "$IS_TRIAL" == "1" ]] && trial_tag=" ${BYELLOW}[trial]${NC}"
        echo -e "  ${BGREEN}[${count}]${NC} ${USERNAME} — exp: ${EXPIRED_DATE}${trial_tag}"
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
    echo ""
    read -rp "  Yakin hapus akun '${selected}'? [y/N]: " confirm
    [[ "${confirm,,}" != "y" ]] && return

    vmess_delete "$selected"
    print_ok "Akun '${selected}' berhasil dihapus!"
    press_any_key
}

del_vmess
