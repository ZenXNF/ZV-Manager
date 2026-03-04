#!/bin/bash
# ============================================================
#   ZV-Manager - Manajemen Saldo User Telegram
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/helpers.sh

SALDO_DIR="/etc/zv-manager/accounts/saldo"
mkdir -p "$SALDO_DIR"

_get_saldo() {
    local f="${SALDO_DIR}/${1}.conf"
    [[ -f "$f" ]] && grep "^SALDO=" "$f" | cut -d= -f2 || echo "0"
}

_set_saldo() {
    echo "SALDO=${2}" > "${SALDO_DIR}/${1}.conf"
}

saldo_menu() {
    while true; do
        clear
        echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
        echo -e " │          ${BWHITE}MANAJEMEN SALDO TELEGRAM${NC}              │"
        echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "  ${BGREEN}[1]${NC} Lihat Saldo User"
        echo -e "  ${BGREEN}[2]${NC} Set / Tambah Saldo"
        echo -e "  ${BGREEN}[3]${NC} Reset Saldo ke 0"
        echo -e "  ${BGREEN}[4]${NC} List Semua Saldo"
        echo ""
        echo -e "  ${BRED}[0]${NC} Kembali"
        echo ""
        read -rp "  Pilihan: " ch

        case "$ch" in
            1)
                echo ""
                read -rp "  Telegram User ID: " uid
                [[ -z "$uid" ]] && continue
                local s; s=$(_get_saldo "$uid")
                echo -e ""
                echo -e "  ${BWHITE}User ID :${NC} ${BYELLOW}${uid}${NC}"
                echo -e "  ${BWHITE}Saldo   :${NC} ${BGREEN}Rp${s}${NC}"
                echo ""
                press_any_key
                ;;
            2)
                echo ""
                read -rp "  Telegram User ID: " uid
                [[ -z "$uid" ]] && continue
                local cur; cur=$(_get_saldo "$uid")
                echo -e "  ${BWHITE}Saldo sekarang: Rp${cur}${NC}"
                echo ""
                echo -e "  ${BYELLOW}[1] Set saldo ke nominal tertentu${NC}"
                echo -e "  ${BYELLOW}[2] Tambah ke saldo sekarang${NC}"
                echo ""
                read -rp "  Pilih: " mode
                read -rp "  Nominal (Rp): " amount
                [[ ! "$amount" =~ ^[0-9]+$ ]] && { echo -e "  ${BRED}Nominal tidak valid!${NC}"; sleep 1; continue; }
                if [[ "$mode" == "2" ]]; then
                    amount=$(( cur + amount ))
                fi
                _set_saldo "$uid" "$amount"
                echo -e ""
                echo -e "  ${BGREEN}Saldo user ${uid} diset ke Rp${amount}${NC}"
                echo ""
                press_any_key
                ;;
            3)
                echo ""
                read -rp "  Telegram User ID: " uid
                [[ -z "$uid" ]] && continue
                if confirm "Reset saldo ${uid} ke 0?"; then
                    _set_saldo "$uid" "0"
                    echo -e "  ${BGREEN}Saldo direset!${NC}"
                fi
                echo ""
                press_any_key
                ;;
            4)
                clear
                echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
                echo -e " │              ${BWHITE}DAFTAR SALDO${NC}                    │"
                echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
                echo ""
                printf "  ${BWHITE}%-20s %-15s${NC}\n" "User ID" "Saldo"
                echo -e "  ${BCYAN}────────────────────────────────────${NC}"
                local found=0
                for f in "$SALDO_DIR"/*.conf; do
                    [[ -f "$f" ]] || continue
                    local fuid; fuid=$(basename "$f" .conf)
                    local s; s=$(grep "^SALDO=" "$f" | cut -d= -f2)
                    printf "  %-20s ${BGREEN}Rp%-15s${NC}\n" "$fuid" "$s"
                    found=1
                done
                [[ $found -eq 0 ]] && echo -e "  ${BYELLOW}Belum ada data saldo.${NC}"
                echo ""
                press_any_key
                ;;
            0) break ;;
            *) echo -e "  ${BRED}Tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}

saldo_menu
