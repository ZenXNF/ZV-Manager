#!/bin/bash
# ============================================================
#   ZV-Manager - Telegram Bot Installer (Python/aiogram)
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh

install_telegram_bot() {
    print_section "Install Telegram Bot (Python)"

    # python3 + pip
    if ! command -v python3 &>/dev/null; then
        print_info "Menginstall python3..."
        apt-get install -y python3 python3-pip &>/dev/null
    fi
    if ! command -v pip3 &>/dev/null; then
        apt-get install -y python3-pip &>/dev/null
    fi

    # Install aiogram
    print_info "Menginstall aiogram..."
    pip3 install -q "aiogram>=3.6.0" --break-system-packages 2>/dev/null || pip3 install -q "aiogram>=3.6.0" 2>/dev/null

    # Verifikasi
    if ! python3 -c "import aiogram" &>/dev/null; then
        print_error "Gagal install aiogram!"
        return 1
    fi

    # Deploy semua modul bot ke /opt/zv-telegram/
    BOT_DIR="/opt/zv-telegram"
    mkdir -p "${BOT_DIR}/handlers"
    cp /etc/zv-manager/services/telegram/bot.py        "${BOT_DIR}/"
    cp /etc/zv-manager/services/telegram/config.py     "${BOT_DIR}/"
    cp /etc/zv-manager/services/telegram/utils.py      "${BOT_DIR}/"
    cp /etc/zv-manager/services/telegram/storage.py    "${BOT_DIR}/"
    cp /etc/zv-manager/services/telegram/keyboards.py  "${BOT_DIR}/"
    cp /etc/zv-manager/services/telegram/texts.py      "${BOT_DIR}/"
    cp /etc/zv-manager/services/telegram/middleware.py "${BOT_DIR}/"
    cp /etc/zv-manager/services/telegram/handlers/__init__.py  "${BOT_DIR}/handlers/"
    cp /etc/zv-manager/services/telegram/handlers/user.py      "${BOT_DIR}/handlers/"
    cp /etc/zv-manager/services/telegram/handlers/admin.py     "${BOT_DIR}/handlers/"
    cp /etc/zv-manager/services/telegram/handlers/messages.py  "${BOT_DIR}/handlers/"
    chmod +x "${BOT_DIR}/bot.py"

    # Hapus file lama kalau ada
    rm -f /usr/local/bin/zv-telegram-bot /usr/local/bin/zv-telegram-bot.py

    # Systemd service
    cat > /etc/systemd/system/zv-telegram.service <<'SVCEOF'
[Unit]
Description=ZV-Manager Telegram Bot (Python)
After=network.target
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
Type=simple
WorkingDirectory=/opt/zv-telegram
ExecStart=/usr/bin/python3 -u /opt/zv-telegram/bot.py
Restart=always
RestartSec=10s
# Batasi memori maksimal 120MB di VPS 512MB/1GB
MemoryMax=120M
MemorySwapMax=0
# Batasi CPU agar tidak monopoli di 1-core VPS
CPUQuota=60%
StandardOutput=append:/var/log/zv-manager/telegram-bot.log
StandardError=append:/var/log/zv-manager/telegram-bot.log

[Install]
WantedBy=multi-user.target
SVCEOF

    systemctl daemon-reload
    systemctl enable zv-telegram &>/dev/null
    systemctl restart zv-telegram &>/dev/null

    sleep 2
    if systemctl is-active --quiet zv-telegram; then
        print_success "Telegram Bot (Python)"
    else
        print_error "Bot gagal start! Cek: systemctl status zv-telegram"
        print_error "Log: tail -20 /var/log/zv-manager/telegram-bot.log"
    fi
}
