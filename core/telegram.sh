#!/bin/bash
# ============================================================
#   ZV-Manager - Telegram Helper
#   Config & send message via Bot API
# ============================================================

TG_CONF="/etc/zv-manager/telegram.conf"

# Load config
tg_load() {
    [[ -f "$TG_CONF" ]] || return 1
    unset TG_TOKEN TG_ADMIN_ID TG_BOT_NAME TG_ENABLED
    source "$TG_CONF"
    return 0
}

# Cek apakah Telegram sudah dikonfigurasi & aktif
tg_enabled() {
    tg_load || return 1
    [[ "$TG_ENABLED" == "1" && -n "$TG_TOKEN" && -n "$TG_ADMIN_ID" ]]
}

# Kirim pesan ke chat_id tertentu
# tg_send <chat_id> <text>
tg_send() {
    local chat_id="$1"
    local text="$2"
    tg_load || return 1
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -d "chat_id=${chat_id}" \
        -d "text=${text}" \
        -d "parse_mode=HTML" \
        --max-time 10 &>/dev/null
}

# Ambil info bot dari token
# Return: nama bot atau kosong kalau gagal
tg_get_bot_name() {
    local token="$1"
    local result
    result=$(curl -s --max-time 10 \
        "https://api.telegram.org/bot${token}/getMe" 2>/dev/null)
    echo "$result" | grep -o '"username":"[^"]*"' | cut -d'"' -f4
}

# Ambil nama user dari user_id
tg_get_user_name() {
    local token="$1"
    local user_id="$2"
    local result
    result=$(curl -s --max-time 10 -X POST \
        "https://api.telegram.org/bot${token}/getChat" \
        -d "chat_id=${user_id}" 2>/dev/null)
    local first
    local last
    first=$(echo "$result" | grep -o '"first_name":"[^"]*"' | cut -d'"' -f4)
    last=$(echo "$result" | grep -o '"last_name":"[^"]*"' | cut -d'"' -f4)
    local username
    username=$(echo "$result" | grep -o '"username":"[^"]*"' | cut -d'"' -f4)
    if [[ -n "$first" ]]; then
        echo "${first}${last:+ $last}${username:+ (@$username)}"
    else
        echo ""
    fi
}
