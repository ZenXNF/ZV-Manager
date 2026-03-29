#!/bin/bash
source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/helpers.sh
menu_zivpn() {
    while true; do
        clear; _sep; _grad " MENU ZIVPN UDP" 0 210 255 160 80 255; _sep; echo ""
        local n=0
        for f in /etc/zv-manager/accounts/zivpn/*.conf; do [[ -f "$f" ]] && n=$((n+1)); done
        echo -e "  ${BWHITE}Total Akun ZiVPN :${NC} ${BGREEN}${n}${NC}"; echo ""
        echo -e "  $(_grad '[1]' 0 210 255 160 80 255) Buat Akun ZiVPN"
        echo -e "  $(_grad '[2]' 0 210 255 160 80 255) List Akun ZiVPN"
        echo -e "  $(_grad '[3]' 0 210 255 160 80 255) Detail Akun ZiVPN"
        echo -e "  $(_grad '[4]' 0 210 255 160 80 255) Renew Akun ZiVPN"
        echo -e "  $(_grad '[5]' 0 210 255 160 80 255) Hapus Akun ZiVPN"
        echo ""; echo -e "  ${BRED}[0]${NC} Kembali"; echo ""
        read -rp "  Pilihan [0-5]: " choice
        case "$choice" in
            1) bash /etc/zv-manager/menu/zivpn/add-zivpn.sh ;;
            2) bash /etc/zv-manager/menu/zivpn/list-zivpn.sh ;;
            3) bash /etc/zv-manager/menu/zivpn/detail-zivpn.sh ;;
            4) bash /etc/zv-manager/menu/zivpn/renew-zivpn.sh ;;
            5) bash /etc/zv-manager/menu/zivpn/del-zivpn.sh ;;
            0) return ;;
            *) echo -e "  ${BRED}Pilihan tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}
menu_zivpn
