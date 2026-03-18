#!/bin/bash
source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/utils/remote.sh

SERVER_DIR="/etc/zv-manager/servers"

check_server_exists() {
    local count=0
    for conf in "${SERVER_DIR}"/*.conf; do [[ -f "$conf" ]] && count=$((count+1)); done
    if [[ $count -eq 0 ]]; then
        clear
        echo -e "${BRED}  Belum ada server! Tambah dulu di Manajemen Server.${NC}"
        echo ""
        press_any_key
        return 1
    fi
    return 0
}

_init_target() {
    [[ ! -f "/tmp/zv_target_server" ]] && set_target_server "local"
}

_ssh_active_count() {
    local target; target=$(get_target_server)
    if is_local_target; then
        ls /etc/zv-manager/accounts/ssh/*.conf 2>/dev/null | while read -r f; do
            grep -qE 'IS_TRIAL="1"|IS_TRIAL=1' "$f" || echo x
        done | wc -l
    else
        echo "?"
    fi
}

menu_ssh() {
    check_server_exists || return
    _init_target

    while true; do
        local target_info; target_info=$(target_display)
        local aktif; aktif=$(_ssh_active_count)
        clear
        _section "MANAJEMEN SSH"
        echo ""
        echo -e "  \e[38;2;0;210;255mTarget\e[0m : \e[1;97m${target_info}\e[0m   \e[38;2;0;210;255mAkun Aktif\e[0m : \e[38;2;255;200;0m${aktif}\e[0m"
        echo ""
        echo -e "  $(_grad '[1]' 0 210 255 160 80 255) Tambah Akun          $(_grad '[2]' 0 210 255 160 80 255) Hapus Akun"
        echo -e "  $(_grad '[3]' 0 210 255 160 80 255) List Akun            $(_grad '[4]' 0 210 255 160 80 255) Perpanjang Akun"
        echo -e "  $(_grad '[5]' 0 210 255 160 80 255) Lock Akun            $(_grad '[6]' 0 210 255 160 80 255) Unlock Akun"
        echo -e "  $(_grad '[7]' 0 210 255 160 80 255) Edit Akun"
        echo ""
        echo -e "  \e[38;2;255;200;0m[s]\e[0m Ganti Target         \e[38;2;255;200;0m[d]\e[0m Saldo Telegram"
        echo -e "  \e[38;2;255;80;80m[0/7]\e[0m Kembali"
        echo ""
        read -rp "  Pilihan [0-7/s/d]: " choice
        case $choice in
            1) bash /etc/zv-manager/menu/ssh/add-user.sh ;;
            2) bash /etc/zv-manager/menu/ssh/del-user.sh ;;
            3) bash /etc/zv-manager/menu/ssh/list-user.sh ;;
            4) bash /etc/zv-manager/menu/ssh/renew-user.sh ;;
            5) bash /etc/zv-manager/menu/ssh/lock-user.sh lock ;;
            6) bash /etc/zv-manager/menu/ssh/lock-user.sh unlock ;;
            7) bash /etc/zv-manager/menu/ssh/edit-user.sh ;;
            s|S) pick_target_server ;;
            d|D) bash /etc/zv-manager/menu/ssh/saldo.sh ;;
            0) break ;;
            *) echo -e "  ${BRED}Pilihan tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}
menu_ssh
