#!/bin/bash
# ============================================================
#   ZV-Manager - Edit Server Banner
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/core/banner.sh

BANNER_CONF="/etc/zv-manager/banner.conf"

_init_banner_conf

_load_conf() {
    unset BANNER_WELCOME BANNER_SUBTITLE BANNER_WARN BANNER_THEME BANNER_WA BANNER_TG
    unset BANNER_RULE_1 BANNER_RULE_2 BANNER_RULE_3 BANNER_RULE_4 BANNER_RULE_5
    source "$BANNER_CONF"
}

_save_conf() {
    cat > "$BANNER_CONF" <<EOF
BANNER_WELCOME="${BANNER_WELCOME}"
BANNER_SUBTITLE="${BANNER_SUBTITLE}"
BANNER_RULE_1="${BANNER_RULE_1}"
BANNER_RULE_2="${BANNER_RULE_2}"
BANNER_RULE_3="${BANNER_RULE_3}"
BANNER_RULE_4="${BANNER_RULE_4}"
BANNER_RULE_5="${BANNER_RULE_5}"
BANNER_WARN="${BANNER_WARN}"
BANNER_WA="${BANNER_WA}"
BANNER_TG="${BANNER_TG}"
BANNER_THEME="${BANNER_THEME}"
EOF
}

_apply_banner() {
    generate_banner
    systemctl reload ssh &>/dev/null || systemctl restart ssh &>/dev/null
    print_ok "Banner diterapkan! Berlaku untuk koneksi SSH berikutnya."
    sleep 1
}

_preview_banner() {
    _load_conf
    clear
    _sep
    _grad " PREVIEW BANNER" 255 0 127 0 210 255
    _sep
    echo ""
    echo -e "  ${BYELLOW}(Preview terminal — warna mungkin beda di HTTP Custom)${NC}"
    echo ""

    local rules=()
    for r in "$BANNER_RULE_1" "$BANNER_RULE_2" "$BANNER_RULE_3" "$BANNER_RULE_4" "$BANNER_RULE_5"; do
        [[ -n "$r" ]] && rules+=("$r")
    done

    echo -e "            ${BYELLOW}${BANNER_WELCOME}${NC}"
    echo -e "          ${BPURPLE}▬▬▬ஜ۩۞۩ஜ▬▬▬${NC}"
    echo -e "            ${BWHITE}${BANNER_SUBTITLE}${NC}"
    for rule in "${rules[@]}"; do
        echo -e "            ${BCYAN}✗  ${rule}${NC}"
    done
    [[ -n "$BANNER_WARN" ]] && echo -e "            ${BRED}✔  ${BANNER_WARN}${NC}"
    echo -e "          ${BPURPLE}▬▬▬ஜ۩۞۩ஜ▬▬▬${NC}"
    [[ -n "$BANNER_WA" ]] && echo -e "            ${BGREEN}📱 WA: ${BANNER_WA}${NC}"
    [[ -n "$BANNER_TG" ]] && echo -e "            ${BGREEN}✈️  TG: t.me/${BANNER_TG}${NC}"
    echo ""
    echo -e "  ${BYELLOW}Tema: ${BANNER_THEME}${NC}"
    echo ""
    press_any_key
}

_edit_welcome() {
    _load_conf
    clear
    _sep
    _grad " EDIT TEKS WELCOME" 255 0 127 0 210 255
    _sep
    echo ""
    echo -e "  ${BWHITE}Sekarang :${NC} ${BYELLOW}${BANNER_WELCOME}${NC}"
    echo ""
    read -rp "  Teks baru (Enter = skip): " new_val
    [[ -z "$new_val" ]] && return
    BANNER_WELCOME="$new_val"
    _save_conf
    print_ok "Teks welcome diubah!"
    sleep 1
}

_edit_subtitle() {
    _load_conf
    clear
    _sep
    _grad " EDIT HEADER TERMS & CONDITIONS" 255 0 127 0 210 255
    _sep
    echo ""
    echo -e "  ${BWHITE}Sekarang :${NC} ${BYELLOW}${BANNER_SUBTITLE}${NC}"
    echo ""
    read -rp "  Teks baru (Enter = skip): " new_val
    [[ -z "$new_val" ]] && return
    BANNER_SUBTITLE="$new_val"
    _save_conf
    print_ok "Header T&C diubah!"
    sleep 1
}

_edit_rules() {
    _load_conf
    while true; do
        clear
        _sep
        _grad " EDIT RULES LARANGAN" 255 0 127 0 210 255
        _sep
        echo ""
        local i=1
        for r in "$BANNER_RULE_1" "$BANNER_RULE_2" "$BANNER_RULE_3" "$BANNER_RULE_4" "$BANNER_RULE_5"; do
            if [[ -n "$r" ]]; then
                echo -e "  ${BGREEN}[$i]${NC} ${BCYAN}✗${NC}  $r"
            else
                echo -e "  ${BGREEN}[$i]${NC} ${BYELLOW}(kosong)${NC}"
            fi
            i=$((i+1))
        done
        echo ""
        echo -e "  ${BYELLOW}[1-5]${NC} Edit rule   ${BRED}[0]${NC} Kembali"
        echo ""
        read -rp "  Pilihan: " choice

        [[ "$choice" == "0" ]] && break
        [[ ! "$choice" =~ ^[1-5]$ ]] && continue

        local current
        eval "current=\$BANNER_RULE_${choice}"
        echo ""
        echo -e "  ${BWHITE}Rule $choice :${NC} ${BYELLOW}${current:-kosong}${NC}"
        echo -e "  ${BYELLOW}(Kosongkan untuk hapus rule ini)${NC}"
        echo ""
        read -rp "  Isi baru: " new_val
        eval "BANNER_RULE_${choice}=\"${new_val}\""
        _save_conf
        print_ok "Rule $choice diubah!"
        sleep 1
    done
}

_edit_warn() {
    _load_conf
    clear
    _sep
    _grad " EDIT PERINGATAN (PUNISHMENT)" 255 0 127 0 210 255
    _sep
    echo ""
    echo -e "  ${BWHITE}Sekarang :${NC} ${BYELLOW}${BANNER_WARN}${NC}"
    echo ""
    read -rp "  Peringatan baru (Enter = skip): " new_val
    [[ -z "$new_val" ]] && return
    BANNER_WARN="$new_val"
    _save_conf
    print_ok "Peringatan diubah!"
    sleep 1
}

_edit_promo() {
    _load_conf
    while true; do
        clear
        _sep
        _grad " EDIT KONTAK PROMOSI" 255 0 127 0 210 255
        _sep
        echo ""
        if [[ -n "$BANNER_WA" ]]; then
            echo -e "  ${BWHITE}WhatsApp :${NC} ${BGREEN}📱 WA: ${BANNER_WA}${NC}"
        else
            echo -e "  ${BWHITE}WhatsApp :${NC} ${BYELLOW}(tidak ditampilkan)${NC}"
        fi
        if [[ -n "$BANNER_TG" ]]; then
            echo -e "  ${BWHITE}Telegram :${NC} ${BGREEN}✈️  TG: t.me/${BANNER_TG}${NC}"
        else
            echo -e "  ${BWHITE}Telegram :${NC} ${BYELLOW}(tidak ditampilkan)${NC}"
        fi
        echo ""
        echo -e "  ${BGREEN}[1]${NC} Edit WhatsApp"
        echo -e "  ${BGREEN}[2]${NC} Edit Telegram"
        echo -e "  ${BRED}[0]${NC} Kembali"
        echo ""
        read -rp "  Pilihan: " choice

        case "$choice" in
            1)
                echo ""
                echo -e "  ${BYELLOW}Masukkan nomor WA (contoh: 6281234567890)${NC}"
                echo -e "  ${BYELLOW}Kosongkan + Enter untuk hapus${NC}"
                echo ""
                read -rp "  Nomor WA: " new_val
                BANNER_WA="$new_val"
                _save_conf
                print_ok "WhatsApp diubah!"
                sleep 1
                ;;
            2)
                echo ""
                echo -e "  ${BYELLOW}Masukkan username Telegram (tanpa t.me/)${NC}"
                echo -e "  ${BYELLOW}Contoh: zenxnf → akan tampil sebagai t.me/zenxnf${NC}"
                echo -e "  ${BYELLOW}Kosongkan + Enter untuk hapus${NC}"
                echo ""
                read -rp "  Username TG: " new_val
                # Strip t.me/ kalau user iseng masukin lengkap
                new_val="${new_val#t.me/}"
                new_val="${new_val#https://t.me/}"
                BANNER_TG="$new_val"
                _save_conf
                print_ok "Telegram diubah!"
                sleep 1
                ;;
            0) break ;;
            *) ;;
        esac
    done
}

_edit_theme() {
    _load_conf
    clear
    _sep
    _grad " GANTI TEMA WARNA" 255 0 127 0 210 255
    _sep
    echo ""
    echo -e "  ${BWHITE}Tema sekarang :${NC} ${BYELLOW}${BANNER_THEME}${NC}"
    echo ""
    echo -e "  ${BPURPLE}[1]${NC} Magenta ${BPURPLE}(garis pink, judul kuning)${NC}"
    echo -e "  ${BCYAN}[2]${NC} Cyan    ${BCYAN}(garis cyan, rules hijau)${NC}"
    echo -e "  ${BYELLOW}[3]${NC} Orange  ${BYELLOW}(garis orange, rules cyan)${NC}"
    echo -e "  ${BGREEN}[4]${NC} Green   ${BGREEN}(garis hijau, judul kuning)${NC}"
    echo ""
    echo -e "  ${BRED}[0]${NC} Batal"
    echo ""
    read -rp "  Pilihan: " choice

    case "$choice" in
        1) BANNER_THEME="magenta" ;;
        2) BANNER_THEME="cyan"    ;;
        3) BANNER_THEME="orange"  ;;
        4) BANNER_THEME="green"   ;;
        0) return ;;
        *) print_error "Pilihan tidak valid!"; sleep 1; return ;;
    esac

    _save_conf
    print_ok "Tema diubah ke: ${BANNER_THEME}"
    sleep 1
}

_reset_default() {
    if confirm "Reset banner ke tampilan default?"; then
        rm -f "$BANNER_CONF"
        _init_banner_conf
        print_ok "Banner direset ke default!"
        sleep 1
    fi
}

edit_banner_menu() {
    while true; do
        _load_conf
        clear
        _sep
        _grad " EDIT SERVER BANNER" 255 0 127 0 210 255
        _sep
        echo ""
        echo -e "  ${BWHITE}Welcome  :${NC} ${BYELLOW}${BANNER_WELCOME}${NC}"
        echo -e "  ${BWHITE}T&C      :${NC} ${BYELLOW}${BANNER_SUBTITLE}${NC}"
        echo -e "  ${BWHITE}WA       :${NC} ${BGREEN}${BANNER_WA:-(tidak diset)}${NC}"
        echo -e "  ${BWHITE}Telegram :${NC} ${BGREEN}${BANNER_TG:-(tidak diset)}${NC}"
        echo -e "  ${BWHITE}Tema     :${NC} ${BYELLOW}${BANNER_THEME}${NC}"
        echo ""
        echo -e "${BCYAN}  ──────────────────────────────────────────────${NC}"
        echo ""
        echo -e "  ${BGREEN}[1]${NC} Edit Teks Welcome"
        echo -e "  ${BGREEN}[2]${NC} Edit Header Terms & Conditions"
        echo -e "  ${BGREEN}[3]${NC} Edit Rules Larangan"
        echo -e "  ${BGREEN}[4]${NC} Edit Peringatan"
        echo -e "  ${BGREEN}[5]${NC} Edit Kontak Promosi (WA / Telegram)"
        echo -e "  ${BGREEN}[6]${NC} Ganti Tema Warna"
        echo -e "  ${BGREEN}[7]${NC} Preview Banner"
        echo -e "  ${BYELLOW}[a]${NC} Apply ke Server"
        echo -e "  ${BWHITE}[r]${NC} Reset Default"
        echo ""
        echo -e "  ${BRED}[0]${NC} Kembali"
        echo ""
        read -rp "  Pilihan: " choice

        case "$choice" in
            1) _edit_welcome  ;;
            2) _edit_subtitle ;;
            3) _edit_rules    ;;
            4) _edit_warn     ;;
            5) _edit_promo    ;;
            6) _edit_theme    ;;
            7) _preview_banner ;;
            a|A) _apply_banner ;;
            r|R) _reset_default ;;
            0) break ;;
            *) echo -e "  ${BRED}Pilihan tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}

edit_banner_menu
