#!/bin/bash
# ============================================================
#   ZV-Manager - Telegram Setting Per Server
#   Pisah SSH / VMess setting dengan daftar server masing-masing
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh

SERVER_DIR="/etc/zv-manager/servers"

# Baca tg.conf ke variabel TG_*
_load_tg() {
    local name="$1"
    local f="${SERVER_DIR}/${name}.tg.conf"
    TG_SERVER_LABEL="$name"
    TG_SERVER_TYPE="both"
    TG_HARGA_HARI="0"; TG_HARGA_BULAN="0"
    TG_LIMIT_IP="2"; TG_MAX_AKUN="500"; TG_BW_PER_HARI="5"
    TG_HARGA_VMESS_HARI="0"; TG_HARGA_VMESS_BULAN="0"
    TG_LIMIT_IP_VMESS="2"; TG_MAX_AKUN_VMESS="500"; TG_BW_PER_HARI_VMESS="5"
    TG_BW_TOTAL="Unlimited"; TG_BW_HARGA_PCT="40"
    [[ -f "$f" ]] && source "$f"
    # Fallback: jika field VMess belum ada di file lama, ikut SSH
    [[ "$TG_LIMIT_IP_VMESS" == "2" && "$TG_LIMIT_IP" != "2" ]] && TG_LIMIT_IP_VMESS="$TG_LIMIT_IP"
    [[ "$TG_MAX_AKUN_VMESS" == "500" && "$TG_MAX_AKUN" != "500" ]] && TG_MAX_AKUN_VMESS="$TG_MAX_AKUN"
    [[ "$TG_BW_PER_HARI_VMESS" == "5" && "$TG_BW_PER_HARI" != "5" ]] && TG_BW_PER_HARI_VMESS="$TG_BW_PER_HARI"
}

_save_tg() {
    local name="$1"
    cat > "${SERVER_DIR}/${name}.tg.conf" <<EOF
TG_SERVER_LABEL="${TG_SERVER_LABEL}"
TG_SERVER_TYPE="${TG_SERVER_TYPE}"
TG_HARGA_HARI="${TG_HARGA_HARI}"
TG_HARGA_BULAN="${TG_HARGA_BULAN}"
TG_LIMIT_IP="${TG_LIMIT_IP}"
TG_MAX_AKUN="${TG_MAX_AKUN}"
TG_BW_PER_HARI="${TG_BW_PER_HARI}"
TG_HARGA_VMESS_HARI="${TG_HARGA_VMESS_HARI}"
TG_HARGA_VMESS_BULAN="${TG_HARGA_VMESS_BULAN}"
TG_LIMIT_IP_VMESS="${TG_LIMIT_IP_VMESS}"
TG_MAX_AKUN_VMESS="${TG_MAX_AKUN_VMESS}"
TG_BW_PER_HARI_VMESS="${TG_BW_PER_HARI_VMESS}"
TG_BW_TOTAL="${TG_BW_TOTAL:-Unlimited}"
TG_BW_HARGA_PCT="${TG_BW_HARGA_PCT}"
EOF
    print_ok "Setting disimpan!"
    sleep 1
}

# Ambil daftar server berdasarkan tipe (ssh/vmess)
_get_servers_by_type() {
    local stype="$1"
    local list=()
    for conf in "$SERVER_DIR"/*.conf; do
        [[ -f "$conf" && "$conf" != *.tg.conf ]] || continue
        unset NAME SERVER_TYPE TG_SERVER_TYPE
        source "$conf"
        # Baca tipe dari tg.conf juga
        local tgf="${SERVER_DIR}/${NAME}.tg.conf"
        local t="${SERVER_TYPE:-both}"
        [[ -f "$tgf" ]] && {
            local tgt; tgt=$(grep "^TG_SERVER_TYPE=" "$tgf" | cut -d= -f2 | tr -d '"')
            [[ -n "$tgt" ]] && t="$tgt"
        }
        [[ "$t" == "$stype" || "$t" == "both" ]] && [[ -n "$NAME" ]] && list+=("$NAME")
    done
    echo "${list[@]}"
}

# ── Edit SSH Setting ──────────────────────────────────────────
_edit_ssh() {
    local name="$1"
    _load_tg "$name"

    while true; do
        clear
        _sep
        _grad " MENU" 255 0 127 0 210 255
        _sep
        echo ""
        echo -e "  ${BWHITE}Label di Bot   :${NC} ${BYELLOW}${TG_SERVER_LABEL}${NC}"
        echo -e "  ${BWHITE}Harga SSH/hari :${NC} ${BYELLOW}Rp${TG_HARGA_HARI}${NC}"
        echo -e "  ${BWHITE}Harga / 30 hari:${NC} ${BYELLOW}Rp${TG_HARGA_BULAN}${NC} ${BCYAN}(otomatis × 30)${NC}"
        echo -e "  ${BWHITE}Bandwidth      :${NC} ${BYELLOW}${TG_BW_TOTAL:-Unlimited}${NC}"
        echo -e "  ${BWHITE}Limit IP/akun  :${NC} ${BYELLOW}${TG_LIMIT_IP} IP${NC}"
        echo -e "  ${BWHITE}Maks Akun SSH  :${NC} ${BYELLOW}${TG_MAX_AKUN}${NC}"
        echo -e "  ${BWHITE}BW / hari      :${NC} ${BYELLOW}${TG_BW_PER_HARI} GB${NC}"
        echo -e "  ${BWHITE}Harga BW / GB  :${NC} ${BYELLOW}${TG_BW_HARGA_PCT}% dari harga/hari${NC}"
        echo ""
        echo -e "${BCYAN}  ──────────────────────────────────────────────${NC}"
        echo ""
        echo -e "  ${BGREEN}[1]${NC} Ubah Label"
        echo -e "  ${BGREEN}[2]${NC} Ubah Harga / hari ${BCYAN}(harga 30hr otomatis × 30)${NC}"
        echo -e "  ${BGREEN}[3]${NC} Ubah Harga / 30 hari manual"
        echo -e "  ${BGREEN}[4]${NC} Ubah Bandwidth"
        echo -e "  ${BGREEN}[5]${NC} Ubah Limit IP per akun"
        echo -e "  ${BGREEN}[6]${NC} Ubah Maksimal Akun"
        echo -e "  ${BGREEN}[7]${NC} Ubah Bandwidth / hari GB"
        echo -e "  ${BGREEN}[8]${NC} Ubah Persentase Harga BW ${BCYAN}default: 40%${NC}"
        echo -e "  ${BYELLOW}[s]${NC} Simpan"
        echo ""
        echo -e "  ${BRED}[0]${NC} Kembali"
        echo ""
        read -rp "  Pilihan: " ch
        case "$ch" in
            1) read -rp "  Label baru [${TG_SERVER_LABEL}]: " v; [[ -n "$v" ]] && TG_SERVER_LABEL="$v" ;;
            2) read -rp "  Harga/hari [${TG_HARGA_HARI}]: " v
               if [[ "$v" =~ ^[0-9]+$ ]]; then
                   TG_HARGA_HARI="$v"; TG_HARGA_BULAN=$(( v * 30 ))
                   echo -e "  ${BCYAN}Harga 30 hari: Rp${TG_HARGA_BULAN}${NC}"
               fi ;;
            3) read -rp "  Harga/30 hari [${TG_HARGA_BULAN}]: " v; [[ "$v" =~ ^[0-9]+$ ]] && TG_HARGA_BULAN="$v" ;;
            4) read -rp "  Bandwidth [${TG_BW_TOTAL:-Unlimited}]: " v; [[ -n "$v" ]] && TG_BW_TOTAL="$v" ;;
            5) read -rp "  Limit IP [${TG_LIMIT_IP}]: " v; [[ "$v" =~ ^[0-9]+$ ]] && TG_LIMIT_IP="$v" ;;
            6) read -rp "  Maks akun [${TG_MAX_AKUN}]: " v; [[ "$v" =~ ^[0-9]+$ ]] && TG_MAX_AKUN="$v" ;;
            7) read -rp "  BW/hari GB [${TG_BW_PER_HARI}]: " v; [[ "$v" =~ ^[0-9]+$ ]] && TG_BW_PER_HARI="$v" ;;
            8) read -rp "  Persentase BW (1-100) [${TG_BW_HARGA_PCT}]: " v
               [[ "$v" =~ ^[0-9]+$ ]] && (( v >= 1 && v <= 100 )) && TG_BW_HARGA_PCT="$v" ;;
            s|S) _save_tg "$name" ;;
            0) break ;;
            *) echo -e "  ${BRED}Tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}

# ── Edit VMess Setting ────────────────────────────────────────
_edit_vmess() {
    local name="$1"
    _load_tg "$name"

    while true; do
        clear
        _sep
        _grad " MENU" 255 0 127 0 210 255
        _sep
        echo ""
        echo -e "  ${BWHITE}Label di Bot      :${NC} ${BYELLOW}${TG_SERVER_LABEL}${NC}"
        echo -e "  ${BWHITE}Harga VMess/hari  :${NC} ${BYELLOW}Rp${TG_HARGA_VMESS_HARI}${NC}"
        echo -e "  ${BWHITE}Harga VMess/30hr  :${NC} ${BYELLOW}Rp${TG_HARGA_VMESS_BULAN}${NC} ${BCYAN}(otomatis × 30)${NC}"
        echo -e "  ${BWHITE}Bandwidth         :${NC} ${BYELLOW}${TG_BW_TOTAL:-Unlimited}${NC}"
        echo -e "  ${BWHITE}Limit IP/akun     :${NC} ${BYELLOW}${TG_LIMIT_IP_VMESS} IP${NC}"
        echo -e "  ${BWHITE}Maks Akun VMess   :${NC} ${BYELLOW}${TG_MAX_AKUN_VMESS}${NC}"
        echo -e "  ${BWHITE}BW / hari         :${NC} ${BYELLOW}${TG_BW_PER_HARI_VMESS} GB${NC}"
        echo ""
        echo -e "${BCYAN}  ──────────────────────────────────────────────${NC}"
        echo ""
        echo -e "  ${BGREEN}[1]${NC} Ubah Label"
        echo -e "  ${BGREEN}[2]${NC} Ubah Harga VMess / hari ${BCYAN}(harga 30hr otomatis × 30)${NC}"
        echo -e "  ${BGREEN}[3]${NC} Ubah Harga VMess / 30 hari manual"
        echo -e "  ${BGREEN}[4]${NC} Ubah Bandwidth"
        echo -e "  ${BGREEN}[5]${NC} Ubah Limit IP per akun"
        echo -e "  ${BGREEN}[6]${NC} Ubah Maksimal Akun"
        echo -e "  ${BGREEN}[7]${NC} Ubah Bandwidth / hari GB"
        echo -e "  ${BYELLOW}[s]${NC} Simpan"
        echo ""
        echo -e "  ${BRED}[0]${NC} Kembali"
        echo ""
        read -rp "  Pilihan: " ch
        case "$ch" in
            1) read -rp "  Label baru [${TG_SERVER_LABEL}]: " v; [[ -n "$v" ]] && TG_SERVER_LABEL="$v" ;;
            2) read -rp "  Harga VMess/hari [${TG_HARGA_VMESS_HARI}]: " v
               if [[ "$v" =~ ^[0-9]+$ ]]; then
                   TG_HARGA_VMESS_HARI="$v"; TG_HARGA_VMESS_BULAN=$(( v * 30 ))
                   echo -e "  ${BCYAN}Harga VMess 30 hari: Rp${TG_HARGA_VMESS_BULAN}${NC}"
               fi ;;
            3) read -rp "  Harga VMess/30 hari [${TG_HARGA_VMESS_BULAN}]: " v; [[ "$v" =~ ^[0-9]+$ ]] && TG_HARGA_VMESS_BULAN="$v" ;;
            4) read -rp "  Bandwidth [${TG_BW_TOTAL:-Unlimited}]: " v; [[ -n "$v" ]] && TG_BW_TOTAL="$v" ;;
            5) read -rp "  Limit IP VMess [${TG_LIMIT_IP_VMESS}]: " v; [[ "$v" =~ ^[0-9]+$ ]] && TG_LIMIT_IP_VMESS="$v" ;;
            6) read -rp "  Maks akun VMess [${TG_MAX_AKUN_VMESS}]: " v; [[ "$v" =~ ^[0-9]+$ ]] && TG_MAX_AKUN_VMESS="$v" ;;
            7) read -rp "  BW/hari GB VMess [${TG_BW_PER_HARI_VMESS}]: " v; [[ "$v" =~ ^[0-9]+$ ]] && TG_BW_PER_HARI_VMESS="$v" ;;
            s|S) _save_tg "$name" ;;
            0) break ;;
            *) echo -e "  ${BRED}Tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}

# ── List server untuk tipe tertentu ──────────────────────────
_pick_server() {
    local stype="$1"
    local label="$2"
    local edit_fn="$3"

    while true; do
        clear
        _sep
        _grad " MENU" 255 0 127 0 210 255
        _sep
        echo ""

        local servers=()
        local i=1
        for conf in "$SERVER_DIR"/*.conf; do
            [[ -f "$conf" && "$conf" != *.tg.conf ]] || continue
            unset NAME SERVER_TYPE
            source "$conf"
            [[ -z "$NAME" ]] && continue
            # Cek tipe
            local tgf="${SERVER_DIR}/${NAME}.tg.conf"
            local t="${SERVER_TYPE:-both}"
            [[ -f "$tgf" ]] && {
                local tgt; tgt=$(grep "^TG_SERVER_TYPE=" "$tgf" | cut -d= -f2 | tr -d '"')
                [[ -n "$tgt" ]] && t="$tgt"
            }
            [[ "$t" != "$stype" && "$t" != "both" ]] && continue
            # Ambil label
            local slabel="$NAME"
            [[ -f "$tgf" ]] && { local sl; sl=$(grep "^TG_SERVER_LABEL=" "$tgf" | cut -d= -f2 | tr -d '"'); [[ -n "$sl" ]] && slabel="$sl"; }
            servers+=("$NAME")
            echo -e "  ${BGREEN}[${i}]${NC} ${NAME} ${BYELLOW}(${slabel})${NC}"
            i=$(( i + 1 ))
        done

        if [[ ${#servers[@]} -eq 0 ]]; then
            echo -e "  ${BYELLOW}Tidak ada server dengan tipe ${label}.${NC}"
            echo ""
            press_any_key
            return
        fi

        echo ""
        echo -e "  ${BRED}[0]${NC} Kembali"
        echo ""
        read -rp "  Pilih server: " ch
        [[ "$ch" == "0" ]] && break
        if [[ "$ch" =~ ^[0-9]+$ ]] && (( ch >= 1 && ch <= ${#servers[@]} )); then
            $edit_fn "${servers[$((ch-1))]}"
        else
            echo -e "  ${BRED}Tidak valid!${NC}"; sleep 1
        fi
    done
}

# ── Menu Utama Telegram Setting ───────────────────────────────
tg_server_setting_menu() {
    while true; do
        clear
        _sep
        _grad " TELEGRAM SETTING SERVER" 255 0 127 0 210 255
        _sep
        echo ""
        echo -e "  Pilih kategori setting:"
        echo ""
        echo -e "  ${BGREEN}[1]${NC} 🔑 SSH Setting    — harga, limit, BW untuk SSH"
        echo -e "  ${BGREEN}[2]${NC} ⚡ VMess Setting  — harga, limit, BW untuk VMess"
        echo ""
        echo -e "  ${BRED}[0]${NC} Kembali"
        echo ""
        read -rp "  Pilihan: " ch
        case "$ch" in
            1) _pick_server "ssh"   "SSH"   "_edit_ssh"   ;;
            2) _pick_server "vmess" "VMess" "_edit_vmess" ;;
            0) break ;;
            *) echo -e "  ${BRED}Tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}

tg_server_setting_menu
