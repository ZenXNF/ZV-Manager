#!/bin/bash
# ============================================================
#   ZV-Manager - Broadcast Pesan ke User Telegram
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/core/telegram.sh

ACCOUNT_DIR="/etc/zv-manager/accounts/ssh"
SALDO_DIR="/etc/zv-manager/accounts/saldo"
USERS_DIR="/etc/zv-manager/accounts/users"

# Pure bash format angka
_fmt() {
    local n="${1//[^0-9]/}" result="" len i
    [[ -z "$n" || "$n" == "0" ]] && { echo "0"; return; }
    n=$(( 10#$n )); len=${#n}
    for (( i=0; i<len; i++ )); do
        [[ $i -gt 0 && $(( (len-i) % 3 )) -eq 0 ]] && result+="."
        result+="${n:$i:1}"
    done
    echo "$result"
}

# Escape teks untuk JSON string — pure bash, no python3
_json_str() {
    local s="$1"
    s="${s//\\/\\\\}"   # backslash dulu
    s="${s//\"/\\\"}"   # double quote
    s="${s//$'\n'/\\n}" # newline
    s="${s//$'\r'/\\r}" # carriage return
    s="${s//$'\t'/\\t}" # tab
    echo "$s"
}

# Kumpulkan UID unik dari users/ + akun SSH
_get_all_user_ids() {
    {
        for ufile in "$USERS_DIR"/*.user; do
            [[ -f "$ufile" ]] || continue
            grep "^UID=" "$ufile" | cut -d= -f2
        done
        for conf in "$ACCOUNT_DIR"/*.conf; do
            [[ -f "$conf" ]] || continue
            grep "^TG_USER_ID=" "$conf" | cut -d= -f2
        done
    } | tr -d '[:space:]' | sort -u
}

# Kirim ke satu user — pure curl, no python3
_send_to_user() {
    local uid="$1" text="$2"
    local escaped; escaped=$(_json_str "$text")
    local payload="{\"chat_id\":\"${uid}\",\"text\":\"${escaped}\",\"parse_mode\":\"HTML\"}"
    local result
    result=$(curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -H "Content-Type: application/json" -d "$payload" \
        --max-time 10 2>/dev/null)
    echo "$result" | grep -q '"ok":true'
}

broadcast_menu() {
    while true; do
        clear
        echo -e "${BCYAN}  ┌──────────────────────────────────────────────┐${NC}"
        echo -e "  │           ${BWHITE}BROADCAST TELEGRAM${NC}                │"
        echo -e "${BCYAN}  └──────────────────────────────────────────────┘${NC}"
        echo ""

        # Kumpulkan user — O(n) sekali
        local -a uids=()
        while IFS= read -r uid; do [[ -n "$uid" ]] && uids+=("$uid"); done < <(_get_all_user_ids)
        local reg_count=0
        for uf in "$USERS_DIR"/*.user; do [[ -f "$uf" ]] && reg_count=$(( reg_count + 1 )); done

        echo -e "  ${BWHITE}Total penerima :${NC} ${BGREEN}${#uids[@]} user${NC} ${BCYAN}(${reg_count} terdaftar)${NC}"
        echo ""
        echo -e "  ${BGREEN}[1]${NC} Kirim ke semua user"
        echo -e "  ${BGREEN}[2]${NC} Kirim ke user tertentu"
        echo -e "  ${BGREEN}[3]${NC} Preview daftar user"
        echo ""
        echo -e "  ${BRED}[0]${NC} Kembali"
        echo ""
        read -rp "  Pilihan: " ch

        case "$ch" in
            1)
                [[ ${#uids[@]} -eq 0 ]] && { echo -e "\n  ${BYELLOW}Belum ada user.${NC}"; press_any_key; continue; }
                echo ""
                echo -e "  ${BYELLOW}Ketik pesan (HTML diperbolehkan):${NC}"
                echo -e "  ${BCYAN}<b>bold</b> <i>italic</i> <code>code</code>${NC}"
                echo ""
                read -rp "  Pesan: " pesan
                [[ -z "$pesan" ]] && continue
                echo ""
                echo -e "  ${BWHITE}Preview:${NC}"
                echo -e "  ─────────────────────────────────"
                echo -e "  $pesan"
                echo -e "  ─────────────────────────────────"
                echo ""
                echo -e "  ${BYELLOW}Kirim ke ${#uids[@]} user?${NC}"
                read -rp "  Konfirmasi [y/N]: " konfirm
                [[ "${konfirm,,}" != "y" ]] && continue
                echo ""
                local ok=0 fail=0
                for uid in "${uids[@]}"; do
                    if _send_to_user "$uid" "$pesan"; then
                        echo -e "  ${BGREEN}✓${NC} $uid"; ok=$(( ok + 1 ))
                    else
                        echo -e "  ${BRED}✗${NC} $uid (gagal)"; fail=$(( fail + 1 ))
                    fi
                    sleep 0.05
                done
                echo ""
                echo -e "  ${BGREEN}Selesai! Terkirim: ${ok}   Gagal: ${fail}${NC}"
                echo ""
                press_any_key
                ;;
            2)
                echo ""
                read -rp "  Telegram User ID: " uid
                [[ -z "$uid" ]] && continue
                read -rp "  Pesan: " pesan
                [[ -z "$pesan" ]] && continue
                if _send_to_user "$uid" "$pesan"; then
                    echo -e "\n  ${BGREEN}✓ Terkirim ke ${uid}${NC}"
                else
                    echo -e "\n  ${BRED}✗ Gagal. User mungkin blokir bot.${NC}"
                fi
                echo ""; press_any_key
                ;;
            3)
                clear
                echo -e "${BCYAN}  ┌──────────────────────────────────────────────┐${NC}"
                echo -e "  │             ${BWHITE}DAFTAR USER TELEGRAM${NC}             │"
                echo -e "${BCYAN}  └──────────────────────────────────────────────┘${NC}"
                echo ""
                printf "  ${BWHITE}%-15s %-12s %-10s${NC}\n" "User ID" "Saldo" "Jml Akun"
                echo -e "  ${BCYAN}────────────────────────────────────────${NC}"

                # Bangun lookup akun per uid sekali — O(n) bukan O(n²)
                declare -A uid_akun_count
                for conf in "$ACCOUNT_DIR"/*.conf; do
                    [[ -f "$conf" ]] || continue
                    local cuid; cuid=$(grep "^TG_USER_ID=" "$conf" | cut -d= -f2 | tr -d '[:space:]')
                    [[ -n "$cuid" ]] && uid_akun_count["$cuid"]=$(( ${uid_akun_count["$cuid"]:-0} + 1 ))
                done

                [[ ${#uids[@]} -eq 0 ]] && echo -e "  ${BYELLOW}Belum ada user.${NC}"
                for uid in "${uids[@]}"; do
                    local saldo="0"
                    [[ -f "${SALDO_DIR}/${uid}.saldo" ]] && {
                        saldo=$(< "${SALDO_DIR}/${uid}.saldo")
                        saldo="${saldo#SALDO=}"; saldo="${saldo//[[:space:]]/}"
                        [[ "$saldo" =~ ^[0-9]+$ ]] || saldo="0"
                    }
                    printf "  ${BGREEN}%-15s${NC} Rp%-12s %-10s\n" \
                        "$uid" "$(_fmt "$saldo")" "${uid_akun_count[$uid]:-0} akun"
                done
                echo ""; press_any_key
                ;;
            0) break ;;
            *) echo -e "  ${BRED}Tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}

tg_load || {
    echo -e "${BRED}  Telegram belum dikonfigurasi!${NC}"
    echo -e "  Setup dulu di: System → Setup Telegram Bot"
    press_any_key; exit 1
}

broadcast_menu
