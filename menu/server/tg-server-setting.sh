#!/bin/bash
# ============================================================
#   ZV-Manager - Telegram Setting Per Server
#   Atur harga, quota, limit IP, max akun untuk bot Telegram
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh

SERVER_DIR="/etc/zv-manager/servers"

_load_servers() {
    local list=()
    for conf in "$SERVER_DIR"/*.conf; do
        [[ -f "$conf" ]] || continue
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
    TG_QUOTA="Unlimited"
    TG_LIMIT_IP="2"
    TG_MAX_AKUN="500"
    [[ -f "$f" ]] && source "$f"
}

_save_tg() {
    local name="$1"
    cat > "${SERVER_DIR}/${name}.tg.conf" <<EOF
TG_SERVER_LABEL="${TG_SERVER_LABEL}"
TG_HARGA_HARI="${TG_HARGA_HARI}"
TG_HARGA_BULAN="${TG_HARGA_BULAN}"
TG_QUOTA="${TG_QUOTA}"
TG_LIMIT_IP="${TG_LIMIT_IP}"
TG_MAX_AKUN="${TG_MAX_AKUN}"
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
        echo -e "  ${BWHITE}Harga / hari   :${NC} ${BYELLOW}Rp${TG_HARGA_HARI}${NC}"
        echo -e "  ${BWHITE}Harga / 30 hari:${NC} ${BYELLOW}Rp${TG_HARGA_BULAN}${NC}"
        echo -e "  ${BWHITE}Quota          :${NC} ${BYELLOW}${TG_QUOTA}${NC}"
        echo -e "  ${BWHITE}Limit IP/akun  :${NC} ${BYELLOW}${TG_LIMIT_IP} IP${NC}"
        echo -e "  ${BWHITE}Maks Akun      :${NC} ${BYELLOW}${TG_MAX_AKUN}${NC}"
        echo ""
        echo -e "${BCYAN}  ──────────────────────────────────────────────${NC}"
        echo ""
        echo -e "  ${BGREEN}[1]${NC} Ubah Label (nama di bot)"
        echo -e "  ${BGREEN}[2]${NC} Ubah Harga / hari"
        echo -e "  ${BGREEN}[3]${NC} Ubah Harga / 30 hari"
        echo -e "  ${BGREEN}[4]${NC} Ubah Quota"
        echo -e "  ${BGREEN}[5]${NC} Ubah Limit IP per akun"
        echo -e "  ${BGREEN}[6]${NC} Ubah Maksimal Akun"
        echo -e "  ${BYELLOW}[s]${NC} Simpan"
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
                [[ "$v" =~ ^[0-9]+$ ]] && TG_HARGA_HARI="$v"
                ;;
            3)
                read -rp "  Harga/30 hari (angka) [${TG_HARGA_BULAN}]: " v
                [[ "$v" =~ ^[0-9]+$ ]] && TG_HARGA_BULAN="$v"
                ;;
            4)
                read -rp "  Quota (contoh: 90GB / Unlimited) [${TG_QUOTA}]: " v
                [[ -n "$v" ]] && TG_QUOTA="$v"
                ;;
            5)
                read -rp "  Limit IP per akun (angka) [${TG_LIMIT_IP}]: " v
                [[ "$v" =~ ^[0-9]+$ ]] && TG_LIMIT_IP="$v"
                ;;
            6)
                read -rp "  Maks akun (angka) [${TG_MAX_AKUN}]: " v
                [[ "$v" =~ ^[0-9]+$ ]] && TG_MAX_AKUN="$v"
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
            echo -e "  ${BGREEN}[${i}]${NC} ${NAME} ${BYELLOW}(${label})${NC}"
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
