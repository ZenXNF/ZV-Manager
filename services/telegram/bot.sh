#!/bin/bash
# ============================================================
#   ZV-Manager - Telegram Bot (Entry Point)
# ============================================================

BOT_DIR="/etc/zv-manager/services/telegram"

source /etc/zv-manager/core/telegram.sh
source /etc/zv-manager/core/bandwidth.sh

ACCOUNT_DIR="/etc/zv-manager/accounts/ssh"
TRIAL_DIR="/etc/zv-manager/accounts/trial"
SALDO_DIR="/etc/zv-manager/accounts/saldo"
SERVER_DIR="/etc/zv-manager/servers"
STATE_DIR="/tmp/zv-tg-state"
LOG="/var/log/zv-manager/telegram-bot.log"
OFFSET_FILE="/tmp/zv-tg-offset"
USERS_DIR="/etc/zv-manager/accounts/users"

mkdir -p "$TRIAL_DIR" "$STATE_DIR" "$SALDO_DIR" "$(dirname "$LOG")"

source "${BOT_DIR}/helpers.sh"
source "${BOT_DIR}/keyboards.sh"
source "${BOT_DIR}/handlers.sh"

# ============================================================
# Proses update
# ============================================================
_process_update() {
    local raw="$1" tmpf; tmpf=$(mktemp)
    python3 -c "
import sys, json
try:
    u = json.loads(sys.argv[1])
    if 'message' in u:
        m = u['message']
        lines = ['MSG',str(m['chat']['id']),m['from'].get('first_name','User'),m.get('text','')]
    elif 'callback_query' in u:
        cq = u['callback_query']
        lines = ['CB',str(cq['id']),str(cq['message']['chat']['id']),
                 str(cq['message']['message_id']),
                 cq['from'].get('first_name','User'),cq.get('data','')]
    else: sys.exit(0)
    [print(l) for l in lines]
except: pass
" "$raw" > "$tmpf" 2>/dev/null

    local kind; kind=$(sed -n '1p' "$tmpf")
    [[ -z "$kind" ]] && { rm -f "$tmpf"; return; }

    if [[ "$kind" == "MSG" ]]; then
        local chat_id fname text
        chat_id=$(sed -n '2p' "$tmpf"); fname=$(sed -n '3p' "$tmpf"); text=$(sed -n '4p' "$tmpf")
        rm -f "$tmpf"; _log "MSG $chat_id: ${text:0:40}"
        local cmd; cmd=$(echo "$text" | awk '{print $1}' | cut -d'@' -f1 | tr '[:upper:]' '[:lower:]')
        if   [[ "$cmd" == "/start"   ]]; then _handle_start   "$chat_id" "$fname"
        elif [[ "$cmd" == "/saldo"   ]]; then _handle_saldo   "$chat_id"
        elif [[ "$cmd" == "/history" ]]; then _handle_history "$chat_id"
        elif [[ "$cmd" == "/topup"   ]]; then _handle_topup   "$chat_id" "$text"
        else _handle_input "$chat_id" "$text" || _send "$chat_id" "Ketuk /start untuk membuka menu."
        fi

    elif [[ "$kind" == "CB" ]]; then
        local cb_id chat_id msg_id fname data
        cb_id=$(sed -n '2p' "$tmpf"); chat_id=$(sed -n '3p' "$tmpf")
        msg_id=$(sed -n '4p' "$tmpf"); fname=$(sed -n '5p' "$tmpf"); data=$(sed -n '6p' "$tmpf")
        rm -f "$tmpf"; _log "CB $chat_id: $data"

        case "$data" in
            home)             _cb_home           "$chat_id" "$cb_id" "$msg_id" "$fname" ;;
            m_buat)           _cb_menu_buat       "$chat_id" "$cb_id" "$msg_id" ;;
            m_akun)           _cb_akun_saya       "$chat_id" "$cb_id" "$msg_id" ;;
            m_perpanjang)     _cb_perpanjang      "$chat_id" "$cb_id" "$msg_id" ;;
            m_admin)          _cb_admin_panel      "$chat_id" "$cb_id" "$msg_id" ;;
            m_broadcast)      _cb_broadcast        "$chat_id" "$cb_id" "$msg_id" ;;
            adm_topup)        _cb_adm_topup        "$chat_id" "$cb_id" "$msg_id" ;;
            adm_kurangi)      _cb_adm_kurangi      "$chat_id" "$cb_id" "$msg_id" ;;
            adm_hapus_akun)   _cb_adm_hapus_akun   "$chat_id" "$cb_id" "$msg_id" ;;
            adm_daftar_user)  _cb_adm_daftar_user  "$chat_id" "$cb_id" "$msg_id" ;;
            adm_cek_user)     _cb_adm_cek_user     "$chat_id" "$cb_id" "$msg_id" ;;
            adm_history)      _cb_adm_history      "$chat_id" "$cb_id" "$msg_id" ;;
            m_saldo_history)  _cb_saldo_history   "$chat_id" "$cb_id" "$msg_id" ;;
            m_history)        _handle_history     "$chat_id"; _answer "$cb_id" "" ;;
            m_tambah_bw)      _cb_tambah_bw       "$chat_id" "$cb_id" "$msg_id" ;;
            bw_akun_*)        _cb_tambah_bw_akun  "$chat_id" "$cb_id" "$msg_id" "${data#bw_akun_}" ;;
            bw_beli_*)        local _bw_parts; IFS="_" read -r _ _ _bw_gb _bw_user <<< "${data}"
                              _cb_bw_beli "$chat_id" "$cb_id" "$msg_id" "$_bw_gb" "$_bw_user" ;;
            bw_konfirm_ok)    _cb_konfirm_bw      "$chat_id" "$cb_id" "$msg_id" ;;
            konfirm_renew_ok) _cb_konfirm_renew   "$chat_id" "$cb_id" "$msg_id" ;;
            renew_*)          _cb_renew_akun      "$chat_id" "$cb_id" "$msg_id" "${data#renew_}" "$fname" ;;
            m_trial)          _cb_menu_trial      "$chat_id" "$cb_id" "$msg_id" ;;
            p_buat_ssh)       _cb_proto_buat_ssh  "$chat_id" "$cb_id" "$msg_id" ;;
            p_trial_ssh)      _cb_proto_trial_ssh "$chat_id" "$cb_id" "$msg_id" ;;
            konfirm_ok)       _cb_konfirm         "$chat_id" "$cb_id" "$msg_id" ;;
            s_buat_pg_*)      _cb_proto_buat_ssh  "$chat_id" "$cb_id" "$msg_id" "${data#s_buat_pg_}" ;;
            s_trial_pg_*)     _cb_proto_trial_ssh "$chat_id" "$cb_id" "$msg_id" "${data#s_trial_pg_}" ;;
            s_buat_*)         _cb_s_buat          "$chat_id" "$cb_id" "$msg_id" "$fname" "${data#s_buat_}" ;;
            s_trial_*)        _cb_s_trial         "$chat_id" "$cb_id" "$msg_id" "${data#s_trial_}" ;;
            *)                _answer "$cb_id" "" ;;
        esac
    else
        rm -f "$tmpf"
    fi
}

# ============================================================
# Main loop
# ============================================================
main() {
    tg_load || { _log "ERROR: config tidak ditemukan!"; exit 1; }
    _log "=== Bot started ==="
    local offset=0
    [[ -f "$OFFSET_FILE" ]] && offset=$(cat "$OFFSET_FILE")
    while true; do
        local response
        response=$(curl -s --max-time 35 \
            "https://api.telegram.org/bot${TG_TOKEN}/getUpdates?offset=${offset}&timeout=30&allowed_updates=%5B%22message%22%2C%22callback_query%22%5D" \
            2>/dev/null)
        [[ -z "$response" || "$response" == *'"ok":false'* ]] && { sleep 5; continue; }

        while IFS=$'\t' read -r uid line; do
            [[ -z "$uid" || -z "$line" ]] && continue
            offset=$(( uid + 1 ))
            echo "$offset" > "$OFFSET_FILE"
            while [[ $(jobs -r | wc -l) -ge 8 ]]; do sleep 0.05; done
            _process_update "$line" &
        done < <(echo "$response" | python3 -c "
import sys, json
try:
    for u in json.load(sys.stdin).get('result', []):
        print(str(u.get('update_id','')) + '\t' + json.dumps(u))
except: pass
" 2>/dev/null)

        wait
        sleep 0.2
    done
}

main
