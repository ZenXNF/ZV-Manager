#!/bin/bash
# ============================================================
#   ZV-Manager - Hapus Akun VLESS
# ============================================================
source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/utils/remote.sh
source /etc/zv-manager/core/vless.sh

del_vless() {
    clear
    _sep
    _grad " HAPUS AKUN VLESS" 0 210 255 160 80 255
    _sep
    echo ""

    local count=0
    local usernames=()
    local servers=()

    for conf in "${VLESS_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue
        unset USERNAME EXPIRED_DATE IS_TRIAL SERVER
        source "$conf"
        count=$((count + 1))
        usernames+=("$USERNAME")
        servers+=("${SERVER:-local}")
        local trial_tag=""
        [[ "$IS_TRIAL" == "1" ]] && trial_tag=" ${BYELLOW}[trial]${NC}"
        echo -e "  ${BGREEN}[${count}]${NC} ${USERNAME} — exp: ${EXPIRED_DATE} [${SERVER:-local}]${trial_tag}"
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
    local sname="${servers[$((choice-1))]}"
    echo ""
    read -rp "  Yakin hapus akun '${selected}'? [y/N]: " confirm
    [[ "${confirm,,}" != "y" ]] && return

    # Hapus dari Xray via agent
    local result
    result=$(remote_vless_agent "$sname" del "$selected")
    if echo "$result" | grep -q "^DEL-OK"; then
        print_ok "Akun dihapus dari Xray ($sname)."
    else
        print_warning "Agent: ${result}"
    fi

    # Hapus conf lokal di brain
    rm -f "${VLESS_DIR}/${selected}.conf"
    # Rebuild config
    zv-vless-agent rebuild-config &>/dev/null || true
    print_ok "Akun '${selected}' berhasil dihapus!"
    press_any_key
}

del_vless
