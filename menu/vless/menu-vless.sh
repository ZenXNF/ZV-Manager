#!/bin/bash
source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/utils/remote.sh
source /etc/zv-manager/core/vless.sh

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

menu_vless() {
    check_server_exists || return

    while true; do
        clear
        _sep
        _grad " MANAJEMEN VLESS" 0 210 255 160 80 255
        _sep
        echo ""
        if ! xray_installed; then
            echo -e "  ${BRED}⚠  Xray-core belum terinstall!${NC}"
            echo ""
        else
            local aktif; aktif=$(vless_count_active)
            echo -e "  \e[38;2;0;210;255mXray\e[0m : \e[1;32mAktif\e[0m   \e[38;2;0;210;255mAkun Aktif\e[0m : \e[38;2;255;200;0m${aktif}\e[0m"
            echo ""
        fi
        echo -e "  $(_grad '[1]' 0 210 255 160 80 255) Tambah Akun          $(_grad '[2]' 0 210 255 160 80 255) Hapus Akun"
        echo -e "  $(_grad '[3]' 0 210 255 160 80 255) List Akun            $(_grad '[4]' 0 210 255 160 80 255) Perpanjang Akun"
        echo -e "  $(_grad '[5]' 0 210 255 160 80 255) Edit Akun            $(_grad '[6]' 0 210 255 160 80 255) Detail Akun"
        echo -e "  $(_grad '[7]' 0 210 255 160 80 255) Lock Akun            $(_grad '[8]' 0 210 255 160 80 255) Unlock Akun"
        echo ""
        echo -e "  \e[38;2;255;80;80m[0]\e[0m Kembali"
        echo ""
        read -rp "  Pilihan [0-8]: " choice
        case $choice in
            1) bash /etc/zv-manager/menu/vless/add-vless.sh    ;;
            2) bash /etc/zv-manager/menu/vless/del-vless.sh    ;;
            3) bash /etc/zv-manager/menu/vless/list-vless.sh   ;;
            4) bash /etc/zv-manager/menu/vless/renew-vless.sh  ;;
            5) bash /etc/zv-manager/menu/vless/edit-vless.sh   ;;
            6) bash /etc/zv-manager/menu/vless/detail-vless.sh ;;
            7) bash /etc/zv-manager/menu/vless/lock-vless.sh lock   ;;
            8) bash /etc/zv-manager/menu/vless/lock-vless.sh unlock ;;
            0) break ;;
            *) echo -e "  ${BRED}Pilihan tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}
menu_vless
