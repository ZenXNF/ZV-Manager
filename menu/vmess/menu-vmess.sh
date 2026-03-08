#!/bin/bash
# ============================================================
#   ZV-Manager - Menu VMess
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/core/vmess.sh

menu_vmess() {
    while true; do
        clear
        echo -e "${BCYAN}  ┌──────────────────────────────────────────────┐${NC}"
        echo -e "  │              ${BWHITE}MANAJEMEN VMESS${NC}                 │"
        echo -e "${BCYAN}  └──────────────────────────────────────────────┘${NC}"
        echo ""

        if ! xray_installed; then
            echo -e "  ${BRED}⚠  Xray-core belum terinstall!${NC}"
            echo -e "  ${BYELLOW}Pilih [5] untuk install terlebih dahulu.${NC}"
            echo ""
        else
            local aktif
            aktif=$(vmess_count_active)
            echo -e "  ${BWHITE}Status Xray :${NC} ${BGREEN}Aktif${NC}   ${BWHITE}Akun Aktif :${NC} ${BYELLOW}${aktif}${NC}"
            echo ""
        fi

        echo -e "  ${BGREEN}[1]${NC} Buat Akun          ${BGREEN}[2]${NC} List Akun"
        echo -e "  ${BGREEN}[3]${NC} Hapus Akun         ${BGREEN}[4]${NC} Detail Akun"
        echo -e "  ${BGREEN}[5]${NC} Edit Akun          ${BGREEN}[6]${NC} Restart Xray"
        echo ""
        echo -e "  ${BRED}[0]${NC} Kembali"
        echo ""
        read -rp "  Pilihan: " choice

        case $choice in
            1) bash /etc/zv-manager/menu/vmess/add-vmess.sh ;;
            2) bash /etc/zv-manager/menu/vmess/list-vmess.sh ;;
            3) bash /etc/zv-manager/menu/vmess/del-vmess.sh ;;
            4) bash /etc/zv-manager/menu/vmess/detail-vmess.sh ;;
            5) bash /etc/zv-manager/menu/vmess/edit-vmess.sh ;;
            6)
                systemctl restart zv-xray &>/dev/null
                echo -e "  ${BGREEN}✔${NC} Xray di-restart."
                sleep 1
                ;;
            0) break ;;
            *) echo -e "  ${BRED}Pilihan tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}

menu_vmess
