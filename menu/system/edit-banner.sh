#!/bin/bash
# ============================================================
#   ZV-Manager - Edit Server Banner
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/core/banner.sh

BANNER_CONF="/etc/zv-manager/banner.conf"

# Pastikan banner.conf ada
_init_banner_conf

_load_conf() {
    unset BANNER_TITLE BANNER_SUBTITLE BANNER_WARN BANNER_THEME
    unset BANNER_RULE_1 BANNER_RULE_2 BANNER_RULE_3 BANNER_RULE_4 BANNER_RULE_5
    source "$BANNER_CONF"
}

_save_conf() {
    cat > "$BANNER_CONF" <<EOF
BANNER_TITLE="${BANNER_TITLE}"
BANNER_SUBTITLE="${BANNER_SUBTITLE}"
BANNER_RULE_1="${BANNER_RULE_1}"
BANNER_RULE_2="${BANNER_RULE_2}"
BANNER_RULE_3="${BANNER_RULE_3}"
BANNER_RULE_4="${BANNER_RULE_4}"
BANNER_RULE_5="${BANNER_RULE_5}"
BANNER_WARN="${BANNER_WARN}"
BANNER_THEME="${BANNER_THEME}"
EOF
}

_apply_banner() {
    generate_banner
    systemctl reload ssh &>/dev/null || systemctl restart ssh &>/dev/null
    print_ok "Banner diterapkan! Berlaku untuk koneksi SSH berikutnya."
    sleep 1
}

# ---- Preview di terminal ----
_preview_banner() {
    _load_conf
    clear
    echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
    echo -e " │              ${BWHITE}PREVIEW BANNER${NC}                  │"
    echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BYELLOW}(Preview di terminal, warna mungkin berbeda di NetMod)${NC}"
    echo ""

    # Tampilkan preview pakai warna terminal
    _get_theme_colors "${BANNER_THEME:-magenta}"

    local rules=()
    for r in "$BANNER_RULE_1" "$BANNER_RULE_2" "$BANNER_RULE_3" "$BANNER_RULE_4" "$BANNER_RULE_5"; do
        [[ -n "$r" ]] && rules+=("$r")
    done

    # Konversi hex → ANSI terdekat untuk preview
    echo -e "  ${BPURPLE}▬▬▬ஜ۩۞۩ஜ▬▬▬${NC}"
    echo -e "  ${BYELLOW}--- ${BANNER_TITLE} ---${NC}"
    echo -e "  ${BPURPLE}▬▬▬ஜ۩۞۩ஜ▬▬▬${NC}"
    echo -e "  ${BWHITE}${BANNER_SUBTITLE}${NC}"
    for rule in "${rules[@]}"; do
        echo -e "  ${BCYAN}✗  ${rule}${NC}"
    done
    [[ -n "$BANNER_WARN" ]] && echo -e "  ${BRED}✔  ${BANNER_WARN}${NC}"
    echo -e "  ${BPURPLE}▬▬▬ஜ۩۞۩ஜ▬▬▬${NC}"
    echo ""
    echo -e "  ${BYELLOW}Tema: ${BANNER_THEME}${NC}"
    echo ""
    press_any_key
}

# ---- Edit judul ----
_edit_title() {
    _load_conf
    clear
    echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
    echo -e " │              ${BWHITE}EDIT JUDUL BANNER${NC}               │"
    echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BWHITE}Judul sekarang :${NC} ${BYELLOW}${BANNER_TITLE}${NC}"
    echo ""
    read -rp "  Judul baru (Enter = skip): " new_val
    [[ -z "$new_val" ]] && return

    BANNER_TITLE="$new_val"
    _save_conf
    print_ok "Judul diubah!"
    sleep 1
}

# ---- Edit subtitle ----
_edit_subtitle() {
    _load_conf
    clear
    echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
    echo -e " │            ${BWHITE}EDIT SUBTITLE BANNER${NC}               │"
    echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BWHITE}Subtitle sekarang :${NC} ${BYELLOW}${BANNER_SUBTITLE}${NC}"
    echo ""
    read -rp "  Subtitle baru (Enter = skip): " new_val
    [[ -z "$new_val" ]] && return

    BANNER_SUBTITLE="$new_val"
    _save_conf
    print_ok "Subtitle diubah!"
    sleep 1
}

# ---- Edit rules ----
_edit_rules() {
    _load_conf
    while true; do
        clear
        echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
        echo -e " │              ${BWHITE}EDIT RULES BANNER${NC}               │"
        echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "  ${BWHITE}Rules sekarang:${NC}"
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
        echo -e "  ${BYELLOW}Pilih [1-5] untuk edit rule${NC}"
        echo -e "  ${BRED}[0]${NC} Kembali"
        echo ""
        read -rp "  Pilihan: " choice

        [[ "$choice" == "0" ]] && break
        [[ ! "$choice" =~ ^[1-5]$ ]] && continue

        local current
        eval "current=\$BANNER_RULE_${choice}"
        echo ""
        echo -e "  ${BWHITE}Rule $choice sekarang :${NC} ${BYELLOW}${current}${NC}"
        echo -e "  ${BYELLOW}(Kosongkan untuk hapus rule ini)${NC}"
        echo ""
        read -rp "  Isi baru: " new_val

        eval "BANNER_RULE_${choice}=\"${new_val}\""
        _save_conf
        print_ok "Rule $choice diubah!"
        sleep 1
    done
}

# ---- Edit warning/punishment ----
_edit_warn() {
    _load_conf
    clear
    echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
    echo -e " │           ${BWHITE}EDIT PERINGATAN BANNER${NC}              │"
    echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BWHITE}Peringatan sekarang :${NC} ${BYELLOW}${BANNER_WARN}${NC}"
    echo ""
    read -rp "  Peringatan baru (Enter = skip): " new_val
    [[ -z "$new_val" ]] && return

    BANNER_WARN="$new_val"
    _save_conf
    print_ok "Peringatan diubah!"
    sleep 1
}

# ---- Ganti tema ----
_edit_theme() {
    _load_conf
    clear
    echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
    echo -e " │              ${BWHITE}GANTI TEMA WARNA${NC}                │"
    echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
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

# ---- Reset ke default ----
_reset_default() {
    if confirm "Reset banner ke tampilan default?"; then
        rm -f "$BANNER_CONF"
        _init_banner_conf
        print_ok "Banner direset ke default!"
        sleep 1
    fi
}

# ---- Main menu ----
edit_banner_menu() {
    while true; do
        _load_conf
        clear
        echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
        echo -e " │            ${BWHITE}EDIT SERVER BANNER${NC}                │"
        echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "  ${BWHITE}Judul    :${NC} ${BYELLOW}${BANNER_TITLE}${NC}"
        echo -e "  ${BWHITE}Subtitle :${NC} ${BYELLOW}${BANNER_SUBTITLE}${NC}"
        echo -e "  ${BWHITE}Tema     :${NC} ${BYELLOW}${BANNER_THEME}${NC}"
        echo ""
        echo -e "${BCYAN}  ──────────────────────────────────────────────${NC}"
        echo ""
        echo -e "  ${BGREEN}[1]${NC} Edit Judul"
        echo -e "  ${BGREEN}[2]${NC} Edit Subtitle"
        echo -e "  ${BGREEN}[3]${NC} Edit Rules"
        echo -e "  ${BGREEN}[4]${NC} Edit Peringatan"
        echo -e "  ${BGREEN}[5]${NC} Ganti Tema Warna"
        echo -e "  ${BGREEN}[6]${NC} Preview Banner"
        echo -e "  ${BYELLOW}[a]${NC} Apply ke Server"
        echo -e "  ${BWHITE}[r]${NC} Reset Default"
        echo ""
        echo -e "  ${BRED}[0]${NC} Kembali"
        echo ""
        read -rp "  Pilihan: " choice

        case "$choice" in
            1) _edit_title    ;;
            2) _edit_subtitle ;;
            3) _edit_rules    ;;
            4) _edit_warn     ;;
            5) _edit_theme    ;;
            6) _preview_banner ;;
            a|A) _apply_banner ;;
            r|R) _reset_default ;;
            0) break ;;
            *) echo -e "  ${BRED}Pilihan tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}

edit_banner_menu
