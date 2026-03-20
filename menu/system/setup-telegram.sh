#!/bin/bash
# ============================================================
#   ZV-Manager - Setup Telegram Bot
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/core/telegram.sh

TG_CONF="/etc/zv-manager/telegram.conf"

setup_telegram_menu() {
    while true; do
        clear
        _sep
        _grad " SETUP TELEGRAM BOT" 255 0 127 0 210 255
        _sep
        echo ""

        # Tampilkan status saat ini
        _svc_active=false
        _aiogram_ok=false
        systemctl is-active --quiet zv-telegram 2>/dev/null && _svc_active=true
        pip3 show aiogram &>/dev/null 2>&1 && _aiogram_ok=true

        if tg_enabled; then
            tg_load
            if [[ "$_svc_active" == true ]]; then
                echo -e "  ${BWHITE}Status   :${NC} ${BGREEN}Aktif ●${NC}"
            else
                echo -e "  ${BWHITE}Status   :${NC} ${BRED}Tidak Berjalan ●${NC}"
            fi
            echo -e "  ${BWHITE}Bot      :${NC} ${BYELLOW}@${TG_BOT_NAME}${NC}"
            echo -e "  ${BWHITE}Admin ID :${NC} ${BYELLOW}${TG_ADMIN_ID}${NC}"
            [[ "$_aiogram_ok" == false ]] && \
                echo -e "  ${BWHITE}Library  :${NC} ${BRED}aiogram belum terinstall${NC}"
        else
            echo -e "  ${BWHITE}Status   :${NC} ${BRED}Belum dikonfigurasi${NC}"
        fi

        echo ""
        echo -e "${BCYAN}  ──────────────────────────────────────────────${NC}"
        echo ""
        echo -e "  ${BGREEN}[1]${NC} Setup / Ubah Bot Token"
        echo -e "  ${BGREEN}[2]${NC} Start Bot"
        echo -e "  ${BGREEN}[3]${NC} Stop Bot"
        echo -e "  ${BGREEN}[4]${NC} Status Bot"
        echo ""
        echo -e "  ${BRED}[0]${NC} Kembali"
        echo ""
        read -rp "  Pilihan: " choice

        case "$choice" in
            1) _wizard_setup ;;
            2) _start_bot    ;;
            3) _stop_bot     ;;
            4) _status_bot   ;;
            0) break ;;
            *) echo -e "  ${BRED}Pilihan tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}

_wizard_setup() {
    clear
    _sep
    _grad " SETUP TELEGRAM BOT" 255 0 127 0 210 255
    _sep
    echo ""
    echo -e "  ${BYELLOW}Cara dapat Bot Token:${NC}"
    echo -e "  ${BWHITE}1.${NC} Buka @BotFather di Telegram"
    echo -e "  ${BWHITE}2.${NC} Kirim /newbot → ikuti instruksi"
    echo -e "  ${BWHITE}3.${NC} Copy token yang diberikan"
    echo ""

    # ── Step 1: Token ──────────────────────────────────────
    read -rp "  Bot Token: " input_token
    echo ""

    if [[ -z "$input_token" ]]; then
        print_error "Token tidak boleh kosong!"
        press_any_key
        return
    fi

    print_info "Memverifikasi token..."
    local bot_name
    bot_name=$(tg_get_bot_name "$input_token")

    if [[ -z "$bot_name" ]]; then
        print_error "Token tidak valid atau tidak bisa terhubung ke Telegram!"
        press_any_key
        return
    fi

    echo ""
    echo -e "  ${BWHITE}Nama bot :${NC} ${BGREEN}@${bot_name}${NC}"
    echo ""

    if ! confirm "Bot ini yang benar?"; then
        print_info "Dibatalkan."
        press_any_key
        return
    fi

    # ── Step 2: Admin User ID ──────────────────────────────
    echo ""
    echo -e "  ${BYELLOW}Cara dapat User ID kamu:${NC}"
    echo -e "  ${BWHITE}→${NC} Buka @userinfobot di Telegram → kirim pesan apapun"
    echo ""
    read -rp "  User ID kamu (Admin): " input_userid
    echo ""

    if [[ -z "$input_userid" || ! "$input_userid" =~ ^[0-9]+$ ]]; then
        print_error "User ID tidak valid! Harus berupa angka."
        press_any_key
        return
    fi

    print_info "Memverifikasi User ID..."
    local user_name
    user_name=$(tg_get_user_name "$input_token" "$input_userid")

    if [[ -n "$user_name" ]]; then
        echo ""
        echo -e "  ${BWHITE}Nama     :${NC} ${BGREEN}${user_name}${NC}"
        echo ""
        if ! confirm "User ini yang benar?"; then
            print_info "Dibatalkan."
            press_any_key
            return
        fi
    else
        echo ""
        print_warning "Nama tidak bisa diambil (normal untuk akun private)."
        echo -e "  ${BYELLOW}User ID ${input_userid} akan disimpan sebagai admin.${NC}"
        echo ""
        if ! confirm "Lanjut?"; then
            print_info "Dibatalkan."
            press_any_key
            return
        fi
    fi

    # ── Simpan config ──────────────────────────────────────
    cat > "$TG_CONF" <<EOF
TG_TOKEN="${input_token}"
TG_ADMIN_ID="${input_userid}"
TG_BOT_NAME="${bot_name}"
TG_ENABLED="1"
EOF
    chmod 600 "$TG_CONF"

    echo ""
    print_ok "Konfigurasi Telegram disimpan!"
    echo ""

    # ── Install & start bot ────────────────────────────────
    if confirm "Start bot sekarang?"; then
        source /etc/zv-manager/services/telegram/install.sh
        install_telegram_bot
    fi

    press_any_key
}

_start_bot() {
    if ! tg_enabled; then
        print_error "Bot belum dikonfigurasi! Pilih [1] Setup dulu."
        press_any_key
        return
    fi

    # Deploy file bot ke /opt/zv-telegram
    echo -e "  ${BYELLOW}>>>${NC} Menyiapkan file bot..."
    local BOT_DIR="/opt/zv-telegram"
    mkdir -p "$BOT_DIR"
    cp -r /etc/zv-manager/services/telegram/. "$BOT_DIR/"
    find "$BOT_DIR" -name "*.py" -exec chmod +x {} \;

    # Install aiogram jika belum ada
    if ! pip3 show aiogram &>/dev/null 2>&1; then
        echo -e "  ${BYELLOW}>>>${NC} Menginstall library aiogram..."
        pip3 install -q "aiogram==3.*" --break-system-packages 2>/dev/null || \
        pip3 install -q "aiogram==3.*" 2>/dev/null
    fi

    # Buat/update systemd service
    python3 -c "
svc = '[Unit]\nDescription=ZV-Manager Telegram Bot (Python)\nAfter=network.target\nStartLimitIntervalSec=60\nStartLimitBurst=5\n\n[Service]\nType=simple\nWorkingDirectory=/opt/zv-telegram\nExecStart=/usr/bin/python3 -u /opt/zv-telegram/bot.py\nRestart=always\nRestartSec=10s\nMemoryMax=120M\nMemorySwapMax=0\nCPUQuota=60%\nStandardOutput=append:/var/log/zv-manager/telegram-bot.log\nStandardError=append:/var/log/zv-manager/telegram-bot.log\n\n[Install]\nWantedBy=multi-user.target\n'
open('/etc/systemd/system/zv-telegram.service','w').write(svc)
" 2>/dev/null

    systemctl daemon-reload &>/dev/null
    systemctl enable zv-telegram &>/dev/null
    systemctl restart zv-telegram &>/dev/null
    sleep 2

    if systemctl is-active --quiet zv-telegram; then
        print_ok "Bot berhasil distart!"
    else
        print_error "Bot gagal start! Cek: systemctl status zv-telegram"
    fi
    press_any_key
}

_stop_bot() {
    systemctl stop zv-telegram &>/dev/null
    print_ok "Bot dihentikan."
    press_any_key
}

_status_bot() {
    clear
    _sep
    _grad " STATUS BOT" 255 0 127 0 210 255
    _sep
    echo ""
    systemctl status zv-telegram --no-pager -l 2>/dev/null || \
        echo -e "  ${BYELLOW}Service zv-telegram belum diinstall.${NC}"
    echo ""
    press_any_key
}

setup_telegram_menu
