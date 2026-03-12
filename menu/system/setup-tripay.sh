#!/bin/bash
# ============================================================
#   ZV-Manager - Setup Tripay Payment Gateway
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh

TRIPAY_CONF="/etc/zv-manager/tripay.conf"

# ── Baca nilai saat ini dari tripay.conf ─────────────────────
_read_conf() {
    local key="$1"
    grep "^${key}=" "$TRIPAY_CONF" 2>/dev/null \
        | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"
}

_write_conf() {
    local key="$1" val="$2"
    if grep -q "^${key}=" "$TRIPAY_CONF" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$TRIPAY_CONF"
    else
        echo "${key}=${val}" >> "$TRIPAY_CONF"
    fi
}

_ensure_conf() {
    if [[ ! -f "$TRIPAY_CONF" ]]; then
        cat > "$TRIPAY_CONF" <<'EOF'
TRIPAY_API_KEY=
TRIPAY_PRIVATE_KEY=
TRIPAY_MERCHANT_CODE=
TRIPAY_MODE=sandbox
TRIPAY_FEE_CUSTOMER=0
TRIPAY_NOMINAL_PRESET=10000,20000,50000,100000
EOF
        chmod 600 "$TRIPAY_CONF"
    fi
}

# ── Cek apakah sudah lengkap terkonfigurasi ──────────────────
_tripay_configured() {
    local api_key; api_key=$(_read_conf "TRIPAY_API_KEY")
    local priv_key; priv_key=$(_read_conf "TRIPAY_PRIVATE_KEY")
    local merchant; merchant=$(_read_conf "TRIPAY_MERCHANT_CODE")
    [[ -n "$api_key" && -n "$priv_key" && -n "$merchant" ]]
}

# ── Tampilkan status ringkas ──────────────────────────────────
_show_status() {
    local api_key; api_key=$(_read_conf "TRIPAY_API_KEY")
    local merchant; merchant=$(_read_conf "TRIPAY_MERCHANT_CODE")
    local mode; mode=$(_read_conf "TRIPAY_MODE")
    local fee; fee=$(_read_conf "TRIPAY_FEE_CUSTOMER")
    local preset; preset=$(_read_conf "TRIPAY_NOMINAL_PRESET")

    if _tripay_configured; then
        echo -e "  ${BWHITE}Status     :${NC} ${BGREEN}Terkonfigurasi${NC}"
    else
        echo -e "  ${BWHITE}Status     :${NC} ${BRED}Belum lengkap${NC}"
    fi

    if [[ -n "$api_key" ]]; then
        echo -e "  ${BWHITE}API Key    :${NC} ${BYELLOW}${api_key:0:8}...${api_key: -4}${NC}"
    else
        echo -e "  ${BWHITE}API Key    :${NC} ${BRED}Belum diisi${NC}"
    fi

    if [[ -n "$merchant" ]]; then
        echo -e "  ${BWHITE}Merchant   :${NC} ${BYELLOW}${merchant}${NC}"
    else
        echo -e "  ${BWHITE}Merchant   :${NC} ${BRED}Belum diisi${NC}"
    fi

    local mode_label="${mode:-sandbox}"
    if [[ "$mode_label" == "production" ]]; then
        echo -e "  ${BWHITE}Mode       :${NC} ${BGREEN}Production (LIVE)${NC}"
    else
        echo -e "  ${BWHITE}Mode       :${NC} ${BYELLOW}Sandbox (Testing)${NC}"
    fi

    local fee_label
    [[ "$fee" == "1" ]] && fee_label="${BYELLOW}Ditanggung Customer${NC}" \
                        || fee_label="${BGREEN}Ditanggung Merchant${NC}"
    echo -e "  ${BWHITE}Fee QRIS   :${NC} ${fee_label}"
    echo -e "  ${BWHITE}Preset     :${NC} ${BYELLOW}${preset:-10000,20000,50000,100000}${NC}"

    # Status service
    echo ""
    if systemctl is-active --quiet zv-tripay 2>/dev/null; then
        echo -e "  ${BWHITE}Webhook    :${NC} ${BGREEN}Aktif (zv-tripay)${NC}"
    else
        echo -e "  ${BWHITE}Webhook    :${NC} ${BRED}Tidak berjalan${NC}"
    fi
}

# ── Menu utama ────────────────────────────────────────────────
setup_tripay_menu() {
    _ensure_conf
    while true; do
        clear
        echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
        echo -e " │         ${BWHITE}SETUP TRIPAY PAYMENT GATEWAY${NC}          │"
        echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
        echo ""
        _show_status
        echo ""
        echo -e "${BCYAN}  ──────────────────────────────────────────────${NC}"
        echo ""
        echo -e "  ${BGREEN}[1]${NC} API Key"
        echo -e "  ${BGREEN}[2]${NC} Private Key"
        echo -e "  ${BGREEN}[3]${NC} Merchant Code"
        echo -e "  ${BGREEN}[4]${NC} Mode (Sandbox / Production)"
        echo -e "  ${BGREEN}[5]${NC} Fee QRIS (Merchant / Customer)"
        echo -e "  ${BGREEN}[6]${NC} Preset Nominal Top Up"
        echo -e "  ${BGREEN}[7]${NC} Install / Restart Webhook Service"
        echo ""
        echo -e "  ${BRED}[0]${NC} Kembali"
        echo ""
        read -rp "  Pilihan: " choice

        case "$choice" in
            1) _setup_api_key      ;;
            2) _setup_private_key  ;;
            3) _setup_merchant     ;;
            4) _setup_mode         ;;
            5) _setup_fee          ;;
            6) _setup_preset       ;;
            7) _install_service    ;;
            0) break               ;;
            *) echo -e "  ${BRED}Pilihan tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}

# ── [1] API Key ───────────────────────────────────────────────
_setup_api_key() {
    clear
    echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
    echo -e " │                ${BWHITE}API KEY${NC}                         │"
    echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BYELLOW}Cara dapat API Key:${NC}"
    echo -e "  ${BWHITE}1.${NC} Login ke https://tripay.co.id"
    echo -e "  ${BWHITE}2.${NC} Menu Merchant → pilih merchant kamu"
    echo -e "  ${BWHITE}3.${NC} Tab ${BWHITE}API${NC} → copy ${BWHITE}API Key${NC}"
    echo ""
    local cur; cur=$(_read_conf "TRIPAY_API_KEY")
    [[ -n "$cur" ]] && echo -e "  ${BWHITE}Saat ini :${NC} ${BYELLOW}${cur:0:8}...${cur: -4}${NC}" && echo ""
    read -rp "  API Key baru (Enter = skip): " val
    if [[ -n "$val" ]]; then
        _write_conf "TRIPAY_API_KEY" "$val"
        print_ok "API Key disimpan!"
    else
        print_info "Tidak ada perubahan."
    fi
    press_any_key
}

# ── [2] Private Key ───────────────────────────────────────────
_setup_private_key() {
    clear
    echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
    echo -e " │              ${BWHITE}PRIVATE KEY${NC}                      │"
    echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BYELLOW}Cara dapat Private Key:${NC}"
    echo -e "  ${BWHITE}1.${NC} Login ke https://tripay.co.id"
    echo -e "  ${BWHITE}2.${NC} Menu Merchant → pilih merchant kamu"
    echo -e "  ${BWHITE}3.${NC} Tab ${BWHITE}API${NC} → copy ${BWHITE}Private Key${NC}"
    echo ""
    echo -e "  ${BRED}⚠  Jangan pernah share private key ini!${NC}"
    echo ""
    local cur; cur=$(_read_conf "TRIPAY_PRIVATE_KEY")
    [[ -n "$cur" ]] && echo -e "  ${BWHITE}Saat ini :${NC} ${BYELLOW}${cur:0:4}...${cur: -4}${NC}" && echo ""
    read -rp "  Private Key baru (Enter = skip): " val
    if [[ -n "$val" ]]; then
        _write_conf "TRIPAY_PRIVATE_KEY" "$val"
        print_ok "Private Key disimpan!"
    else
        print_info "Tidak ada perubahan."
    fi
    press_any_key
}

# ── [3] Merchant Code ─────────────────────────────────────────
_setup_merchant() {
    clear
    echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
    echo -e " │            ${BWHITE}MERCHANT CODE${NC}                     │"
    echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BYELLOW}Cara dapat Merchant Code:${NC}"
    echo -e "  ${BWHITE}1.${NC} Login ke https://tripay.co.id"
    echo -e "  ${BWHITE}2.${NC} Menu Merchant → lihat kolom ${BWHITE}Kode Merchant${NC}"
    echo -e "  ${BWHITE}   Contoh: ${BYELLOW}T12345${NC}"
    echo ""
    local cur; cur=$(_read_conf "TRIPAY_MERCHANT_CODE")
    [[ -n "$cur" ]] && echo -e "  ${BWHITE}Saat ini :${NC} ${BYELLOW}${cur}${NC}" && echo ""
    read -rp "  Merchant Code baru (Enter = skip): " val
    if [[ -n "$val" ]]; then
        _write_conf "TRIPAY_MERCHANT_CODE" "$val"
        print_ok "Merchant Code disimpan!"
    else
        print_info "Tidak ada perubahan."
    fi
    press_any_key
}

# ── [4] Mode ──────────────────────────────────────────────────
_setup_mode() {
    clear
    echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
    echo -e " │                ${BWHITE}MODE${NC}                            │"
    echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
    echo ""
    local cur; cur=$(_read_conf "TRIPAY_MODE")
    echo -e "  ${BWHITE}Saat ini :${NC} ${BYELLOW}${cur:-sandbox}${NC}"
    echo ""
    echo -e "  ${BGREEN}[1]${NC} Sandbox  ${BYELLOW}(testing, transaksi tidak nyata)${NC}"
    echo -e "  ${BGREEN}[2]${NC} Production ${BGREEN}(live, uang sungguhan)${NC}"
    echo ""
    echo -e "  ${BRED}[0]${NC} Batal"
    echo ""
    read -rp "  Pilihan: " mode_choice
    case "$mode_choice" in
        1)
            _write_conf "TRIPAY_MODE" "sandbox"
            print_ok "Mode → Sandbox"
            ;;
        2)
            echo ""
            print_warning "Mode Production menggunakan uang sungguhan!"
            if confirm "Yakin ganti ke Production?"; then
                _write_conf "TRIPAY_MODE" "production"
                print_ok "Mode → Production"
            else
                print_info "Dibatalkan."
            fi
            ;;
        0) return ;;
        *) print_error "Pilihan tidak valid!" ;;
    esac
    press_any_key
}

# ── [5] Fee ───────────────────────────────────────────────────
_setup_fee() {
    clear
    echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
    echo -e " │             ${BWHITE}FEE QRIS${NC}                         │"
    echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  Fee QRIS Tripay: ${BYELLOW}Rp750 + 0.7%${NC} per transaksi"
    echo ""
    local cur; cur=$(_read_conf "TRIPAY_FEE_CUSTOMER")
    if [[ "$cur" == "1" ]]; then
        echo -e "  ${BWHITE}Saat ini :${NC} ${BYELLOW}Ditanggung Customer${NC}"
    else
        echo -e "  ${BWHITE}Saat ini :${NC} ${BGREEN}Ditanggung Merchant (kamu)${NC}"
    fi
    echo ""
    echo -e "  ${BGREEN}[1]${NC} Merchant  ${BGREEN}(kamu yang tanggung, user bayar pas nominal)${NC}"
    echo -e "  ${BGREEN}[2]${NC} Customer  ${BYELLOW}(fee ditambahkan ke total bayar user)${NC}"
    echo ""
    echo -e "  ${BRED}[0]${NC} Batal"
    echo ""
    read -rp "  Pilihan: " fee_choice
    case "$fee_choice" in
        1)
            _write_conf "TRIPAY_FEE_CUSTOMER" "0"
            print_ok "Fee → Ditanggung Merchant"
            ;;
        2)
            _write_conf "TRIPAY_FEE_CUSTOMER" "1"
            print_ok "Fee → Ditanggung Customer"
            ;;
        0) return ;;
        *) print_error "Pilihan tidak valid!" ;;
    esac
    press_any_key
}

# ── [6] Preset Nominal ────────────────────────────────────────
_setup_preset() {
    clear
    echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
    echo -e " │          ${BWHITE}PRESET NOMINAL TOP UP${NC}               │"
    echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
    echo ""
    local cur; cur=$(_read_conf "TRIPAY_NOMINAL_PRESET")
    echo -e "  ${BWHITE}Saat ini :${NC} ${BYELLOW}${cur:-10000,20000,50000,100000}${NC}"
    echo ""
    echo -e "  Isi nominal yang muncul di tombol bot (pisah koma)."
    echo -e "  ${BYELLOW}Minimal per nominal: Rp10.000${NC}"
    echo -e "  ${BWHITE}Contoh:${NC} 10000,25000,50000,100000,200000"
    echo ""
    read -rp "  Preset baru (Enter = skip): " val
    if [[ -n "$val" ]]; then
        # Validasi: semua angka, pisah koma
        local clean
        clean=$(echo "$val" | tr -d ' ')
        local valid=1
        IFS=',' read -ra items <<< "$clean"
        for item in "${items[@]}"; do
            if [[ ! "$item" =~ ^[0-9]+$ ]] || (( item < 10000 )); then
                print_error "Nominal '${item}' tidak valid (harus angka ≥ 10000)"
                valid=0
                break
            fi
        done
        if (( valid )); then
            _write_conf "TRIPAY_NOMINAL_PRESET" "$clean"
            print_ok "Preset disimpan: ${clean}"
        fi
    else
        print_info "Tidak ada perubahan."
    fi
    press_any_key
}

# ── [7] Install / Restart Webhook ────────────────────────────
_install_service() {
    clear
    echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
    echo -e " │          ${BWHITE}INSTALL WEBHOOK SERVICE${NC}              │"
    echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
    echo ""

    if ! _tripay_configured; then
        print_error "Konfigurasi belum lengkap!"
        echo -e "  ${BYELLOW}Isi API Key, Private Key, dan Merchant Code dulu.${NC}"
        press_any_key
        return
    fi

    local install_script="/etc/zv-manager/services/tripay/install.sh"
    if [[ ! -f "$install_script" ]]; then
        print_error "File install.sh tidak ditemukan di services/tripay/"
        press_any_key
        return
    fi

    if systemctl is-active --quiet zv-tripay 2>/dev/null; then
        print_info "Service sudah berjalan, restart..."
        systemctl restart zv-tripay
        sleep 2
        if systemctl is-active --quiet zv-tripay; then
            print_ok "Service zv-tripay berhasil direstart!"
        else
            print_error "Restart gagal! Cek: journalctl -u zv-tripay -n 20"
        fi
    else
        print_info "Menjalankan install.sh..."
        bash "$install_script"
    fi

    echo ""
    local domain
    domain=$(cat /etc/zv-manager/domain 2>/dev/null | tr -d '[:space:]')
    echo -e "  ${BWHITE}Callback URL untuk dashboard Tripay:${NC}"
    echo -e "  ${BGREEN}https://${domain}/tripay/callback${NC}"
    echo ""
    press_any_key
}

setup_tripay_menu
