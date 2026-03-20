#!/bin/bash
# ============================================================
#   ZV-Manager - Manajemen Saldo User Telegram
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/helpers.sh

SALDO_DIR="/etc/zv-manager/accounts/saldo"
mkdir -p "$SALDO_DIR"

_get_saldo() {
    local f="${SALDO_DIR}/${1}.saldo" val="0"
    [[ -f "$f" ]] && val=$(< "$f")
    val="${val#SALDO=}"; val="${val//[[:space:]]/}"
    [[ "$val" =~ ^[0-9]+$ ]] || val="0"
    echo "$val"
}
_set_saldo() { echo "${2}" > "${SALDO_DIR}/${1}.saldo"; }

# Pure bash format angka: 100000 → 100.000
_fmt() {
    local n="${1//[^0-9]/}" result="" len i
    [[ -z "$n" || "$n" == "0" ]] && { echo "0"; return; }
    n=$(( 10#$n )); len=${#n}
    for (( i=0; i<len; i++ )); do
        [[ $i -gt 0 && $(( (len-i) % 3 )) -eq 0 ]] && result+="."
        result+="${n:$i:1}"
    done
    echo "$result"
}

saldo_menu() {
    while true; do
        clear
        _sep
        _grad " MANAJEMEN SALDO TELEGRAM" 255 0 127 0 210 255
        _sep
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
                echo ""
                echo -e "  ${BWHITE}User ID :${NC} ${BYELLOW}${uid}${NC}"
                echo -e "  ${BWHITE}Saldo   :${NC} ${BGREEN}Rp$(_fmt "$s")${NC}"
                echo ""
                press_any_key
                ;;
            2)
                echo ""
                read -rp "  Telegram User ID: " uid
                [[ -z "$uid" ]] && continue
                local cur; cur=$(_get_saldo "$uid")
                echo -e "  ${BWHITE}Saldo sekarang: Rp$(_fmt "$cur")${NC}"
                echo ""
                echo -e "  ${BYELLOW}[1] Set saldo ke nominal tertentu${NC}"
                echo -e "  ${BYELLOW}[2] Tambah ke saldo sekarang${NC}"
                echo ""
                read -rp "  Pilih: " mode
                read -rp "  Nominal (Rp): " amount
                [[ ! "$amount" =~ ^[0-9]+$ ]] && { echo -e "  ${BRED}Nominal tidak valid!${NC}"; sleep 1; continue; }
                [[ "$mode" == "2" ]] && amount=$(( cur + amount ))
                _set_saldo "$uid" "$amount"
                echo ""
                echo -e "  ${BGREEN}Saldo user ${uid} diset ke Rp$(_fmt "$amount")${NC}"
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
                _sep
                _grad " DAFTAR SALDO" 255 0 127 0 210 255
                _sep
                echo ""
                printf "  ${BWHITE}%-20s %-15s${NC}\n" "User ID" "Saldo"
                echo -e "  ${BCYAN}────────────────────────────────────${NC}"
                local found=0
                for f in "$SALDO_DIR"/*.saldo; do
                    [[ -f "$f" ]] || continue
                    local fuid; fuid=$(basename "$f" .saldo)
                    local s; s=$(< "$f"); s="${s#SALDO=}"; s="${s//[[:space:]]/}"
                    [[ "$s" =~ ^[0-9]+$ ]] || s="0"
                    printf "  %-20s ${BGREEN}Rp%-15s${NC}\n" "$fuid" "$(_fmt "$s")"
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
