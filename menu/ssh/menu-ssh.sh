#!/bin/bash
# ============================================================
#   ZV-Manager - SSH Sub-Menu
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/utils/remote.sh

SERVER_DIR="/etc/zv-manager/servers"

check_server_exists() {
    local count=0
    for conf in "${SERVER_DIR}"/*.conf; do
        [[ -f "$conf" ]] && count=$((count + 1))
    done

    if [[ $count -eq 0 ]]; then
        clear
        echo -e "${BRED} ┌──────────────────────────────────────────────┐${NC}"
        echo -e "${BRED} │            BELUM ADA SERVER!                  │${NC}"
        echo -e "${BRED} └──────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "  ${BYELLOW}Tambahkan server dulu sebelum bisa buat akun.${NC}"
        echo -e "  Menu Utama → ${BGREEN}[2] Manajemen Server${NC} → ${BGREEN}[1] Tambah Server${NC}"
        echo ""
        press_any_key
        return 1
    fi
    return 0
}

# Pastikan target default sudah di-set (pertama kali)
_init_target() {
    if [[ ! -f "/tmp/zv_target_server" ]]; then
        set_target_server "local"
    fi
}

menu_ssh() {
    check_server_exists || return
    _init_target

    while true; do
        local target_info
        target_info=$(target_display)

        clear
        echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
        echo -e " │            ${BWHITE}MENU MANAJEMEN SSH${NC}                │"
        echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "  ${BWHITE}Target Server :${NC} ${BGREEN}${target_info}${NC}"
        echo ""
        echo -e "${BCYAN}  ──────────────────────────────────────────────${NC}"
        echo ""
        echo -e "  ${BGREEN}[1]${NC} Tambah Akun SSH"
        echo -e "  ${BGREEN}[2]${NC} Hapus Akun SSH"
        echo -e "  ${BGREEN}[3]${NC} List Akun SSH"
        echo -e "  ${BGREEN}[4]${NC} Perpanjang Akun SSH"
        echo -e "  ${BGREEN}[5]${NC} Lock Akun SSH"
        echo -e "  ${BGREEN}[6]${NC} Unlock Akun SSH"
        echo -e "  ${BGREEN}[7]${NC} Monitor Online"
        echo -e "  ${BGREEN}[8]${NC} Edit Akun SSH"
        echo ""
        echo -e "  ${BYELLOW}[s]${NC} Ganti Target Server"
        echo -e "  ${BRED}[0]${NC} Kembali ke Menu Utama"
        echo ""
        read -rp "  Pilihan: " choice

        case $choice in
            1) bash /etc/zv-manager/menu/ssh/add-user.sh ;;
            2) bash /etc/zv-manager/menu/ssh/del-user.sh ;;
            3) bash /etc/zv-manager/menu/ssh/list-user.sh ;;
            4) bash /etc/zv-manager/menu/ssh/renew-user.sh ;;
            5) bash /etc/zv-manager/menu/ssh/lock-user.sh ;;
            6) bash /etc/zv-manager/menu/ssh/unlock-user.sh ;;
            7) bash /etc/zv-manager/menu/ssh/monitor-online.sh ;;
            8) bash /etc/zv-manager/menu/ssh/edit-user.sh ;;
            s|S)
                pick_target_server
                ;;
            0) break ;;
            *) echo -e "  ${BRED}Pilihan tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}

menu_ssh
