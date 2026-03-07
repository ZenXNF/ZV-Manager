#!/bin/bash
# ============================================================
#   ZV-Manager - Telegram Setting Per Server
#   Atur harga, bandwidth, limit IP, max akun untuk bot Telegram
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh

SERVER_DIR="/etc/zv-manager/servers"

_load_servers() {
    local list=()
    for conf in "$SERVER_DIR"/*.conf; do
        [[ -f "$conf" ]] || continue
        [[ "$conf" == *.tg.conf ]] && continue
        unset NAME; source "$conf"
        [[ -n "$NAME" ]] && list+=("$NAME")
    done
    echo "${list[@]}"
}

_load_tg() {
    local name="$1"
    local f="${SERVER_DIR}/${name}.tg.conf"
    TG_SERVER_LABEL="$name"
    TG_HARGA_HARI="0"
    TG_HARGA_BULAN="0"
    TG_BW_TOTAL="Unlimited"
    TG_LIMIT_IP="2"
    TG_MAX_AKUN="500"
    TG_BW_PER_HARI="5"
    TG_BW_HARGA_PCT="40"
    TG_HARGA_VMESS_HARI="0"
    [[ -f "$f" ]] && source "$f"
}

_save_tg() {
    local name="$1"
    cat > "${SERVER_DIR}/${name}.tg.conf" <<EOF
TG_SERVER_LABEL="${TG_SERVER_LABEL}"
TG_HARGA_HARI="${TG_HARGA_HARI}"
TG_HARGA_BULAN="${TG_HARGA_BULAN}"
TG_BW_TOTAL="${TG_BW_TOTAL:-Unlimited}"
TG_LIMIT_IP="${TG_LIMIT_IP}"
TG_MAX_AKUN="${TG_MAX_AKUN}"
TG_BW_PER_HARI="${TG_BW_PER_HARI}"
TG_BW_HARGA_PCT="${TG_BW_HARGA_PCT}"
TG_HARGA_VMESS_HARI="${TG_HARGA_VMESS_HARI}"
EOF
    print_ok "Setting disimpan!"
    sleep 1
}

_edit_server_tg() {
    local name="$1"
    _load_tg "$name"

    while true; do
        clear
        echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
        echo -e " │       ${BWHITE}TELEGRAM SETTING — ${name}${NC}"
        echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "  ${BWHITE}Label di Bot   :${NC} ${BYELLOW}${TG_SERVER_LABEL}${NC}"
        echo -e "  ${BWHITE}Harga SSH/hari :${NC} ${BYELLOW}Rp${TG_HARGA_HARI}${NC}
        echo -e "  ${BWHITE}Harga VMess/hr :${NC} ${BYELLOW}Rp${TG_HARGA_VMESS_HARI}${NC} ${BCYAN}(0 = ikut SSH)${NC}""
        echo -e "  ${BWHITE}Harga / 30 hari:${NC} ${BYELLOW}Rp${TG_HARGA_BULAN}${NC} ${BCYAN}otomatis × 30${NC}"
        echo -e "  ${BWHITE}Bandwidth      :${NC} ${BYELLOW}${TG_BW_TOTAL:-Unlimited}${NC}"
        echo -e "  ${BWHITE}Limit IP/akun  :${NC} ${BYELLOW}${TG_LIMIT_IP} IP${NC}"
        echo -e "  ${BWHITE}Maks Akun      :${NC} ${BYELLOW}${TG_MAX_AKUN}${NC}"
        echo -e "  ${BWHITE}BW / hari      :${NC} ${BYELLOW}${TG_BW_PER_HARI} GB${NC}"
        echo -e "  ${BWHITE}Harga BW / GB  :${NC} ${BYELLOW}${TG_BW_HARGA_PCT}% dari harga/hari${NC}"
        echo ""
        echo -e "${BCYAN}  ──────────────────────────────────────────────${NC}"
        echo ""
        echo -e "  ${BGREEN}[1]${NC} Ubah Label — nama di bot"
        echo -e "  ${BGREEN}[2]${NC} Ubah Harga / hari ${BCYAN}harga/30hr otomatis × 30${NC}"
        echo -e "  ${BGREEN}[3]${NC} Ubah Harga / 30 hari manual"
        echo -e "  ${BGREEN}[4]${NC} Ubah Bandwidth"
        echo -e "  ${BGREEN}[5]${NC} Ubah Limit IP per akun"
        echo -e "  ${BGREEN}[6]${NC} Ubah Maksimal Akun"
        echo -e "  ${BGREEN}[7]${NC} Ubah Bandwidth / hari GB"
        echo -e "  ${BGREEN}[8]${NC} Ubah Persentase Harga BW ${BCYAN}default: 40%${NC}"
        echo -e "  ${BGREEN}[9]${NC} Ubah Harga VMess / hari ${BCYAN}(0 = ikut harga SSH)${NC}
        echo -e "  ${BYELLOW}[s]${NC} Simpan""
        echo ""
        echo -e "  ${BRED}[0]${NC} Kembali"
        echo ""
        read -rp "  Pilihan: " ch

        case "$ch" in
            1)
                read -rp "  Label baru [${TG_SERVER_LABEL}]: " v
                [[ -n "$v" ]] && TG_SERVER_LABEL="$v"
                ;;
            2)
                read -rp "  Harga/hari (angka, contoh 150) [${TG_HARGA_HARI}]: " v
                if [[ "$v" =~ ^[0-9]+$ ]]; then
                    TG_HARGA_HARI="$v"
                    TG_HARGA_BULAN=$(( v * 30 ))
                    echo -e "  ${BCYAN}Harga 30 hari otomatis: Rp${TG_HARGA_BULAN}${NC}"
                fi
                ;;

            4)
                read -rp "  Bandwidth (contoh: 90GB / Unlimited) [${TG_BW_TOTAL:-Unlimited}]: " v
                [[ -n "$v" ]] && TG_BW_TOTAL="$v"
                ;;
            5)
                read -rp "  Limit IP per akun (angka) [${TG_LIMIT_IP}]: " v
                [[ "$v" =~ ^[0-9]+$ ]] && TG_LIMIT_IP="$v"
                ;;
            6)
                read -rp "  Maks akun (angka) [${TG_MAX_AKUN}]: " v
                [[ "$v" =~ ^[0-9]+$ ]] && TG_MAX_AKUN="$v"
                ;;
            7)
                read -rp "  Bandwidth/hari GB (contoh: 5) [${TG_BW_PER_HARI}]: " v
                [[ "$v" =~ ^[0-9]+$ ]] && TG_BW_PER_HARI="$v"
                ;;
            8)
                echo -e "  ${BCYAN}Contoh: 40 artinya harga/GB = 40% dari harga/hari${NC}"
                read -rp "  Persentase harga BW (1-100) [${TG_BW_HARGA_PCT}]: " v
                if [[ "$v" =~ ^[0-9]+$ ]] && (( v >= 1 && v <= 100 )); then
                    TG_BW_HARGA_PCT="$v"
                fi
                ;;
            9)
                read -rp "  Harga VMess/hari (0=ikut SSH) [${TG_HARGA_VMESS_HARI}]: " v
                [[ "$v" =~ ^[0-9]+$ ]] && TG_HARGA_VMESS_HARI="$v"
                ;;
            s|S) _save_tg "$name" ;;
            0) break ;;
            *) echo -e "  ${BRED}Tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}

tg_server_setting_menu() {
    while true; do
        clear
        echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
        echo -e " │       ${BWHITE}TELEGRAM SETTING SERVER${NC}                │"
        echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
        echo ""

        local servers=()
        local i=1
        for conf in "$SERVER_DIR"/*.conf; do
            [[ -f "$conf" ]] || continue
            # skip .tg.conf
            [[ "$conf" == *.tg.conf ]] && continue
            unset NAME IP
            source "$conf"
            [[ -z "$NAME" ]] && continue
            servers+=("$NAME")
            local tgf="${SERVER_DIR}/${NAME}.tg.conf"
            local label="$NAME"
            [[ -f "$tgf" ]] && { source "$tgf"; label="${TG_SERVER_LABEL}"; }
            echo -e "  ${BGREEN}[${i}]${NC} ${NAME} ${BYELLOW}${label}${NC}"
            i=$((i+1))
        done

        if [[ ${#servers[@]} -eq 0 ]]; then
            echo -e "  ${BYELLOW}Belum ada server yang ditambahkan.${NC}"
            echo ""
            press_any_key
            return
        fi

        echo ""
        echo -e "  ${BRED}[0]${NC} Kembali"
        echo ""
        read -rp "  Pilih server: " ch

        [[ "$ch" == "0" ]] && break
        if [[ "$ch" =~ ^[0-9]+$ ]] && [[ "$ch" -ge 1 ]] && [[ "$ch" -le ${#servers[@]} ]]; then
            _edit_server_tg "${servers[$((ch-1))]}"
        else
            echo -e "  ${BRED}Tidak valid!${NC}"; sleep 1
        fi
    done
}

tg_server_setting_menu
