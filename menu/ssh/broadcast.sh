#!/bin/bash
# ============================================================
#   ZV-Manager - Broadcast Pesan ke User Telegram
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/core/telegram.sh

ACCOUNT_DIR="/etc/zv-manager/accounts/ssh"
SALDO_DIR="/etc/zv-manager/accounts/saldo"

# Kumpulkan semua TG_USER_ID unik dari akun
_get_all_user_ids() {
    local -A seen
    for conf in "$ACCOUNT_DIR"/*.conf; do
        [[ -f "$conf" ]] || continue
        local uid; uid=$(grep "^TG_USER_ID=" "$conf" | cut -d= -f2 | tr -d "[:space:]")
        [[ -z "$uid" || -n "${seen[$uid]}" ]] && continue
        seen[$uid]=1
        echo "$uid"
    done
}

# Kirim pesan ke satu user, return status
_send_to_user() {
    local uid="$1" text="$2"
    local result
    result=$(curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -H "Content-Type: application/json" \
        -d "{\"chat_id\":\"${uid}\",\"text\":$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$text"),\"parse_mode\":\"HTML\"}" \
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

        # Hitung jumlah user unik
        local uids=()
        while IFS= read -r uid; do uids+=("$uid"); done < <(_get_all_user_ids)
        echo -e "  ${BWHITE}Total penerima :${NC} ${BGREEN}${#uids[@]} user${NC}"
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
                if [[ ${#uids[@]} -eq 0 ]]; then
                    echo -e "\n  ${BYELLOW}Belum ada user yang terdaftar.${NC}"
                    press_any_key; continue
                fi

                echo ""
                echo -e "  ${BYELLOW}Ketik pesan broadcast (kosongkan untuk batal):${NC}"
                echo -e "  ${BCYAN}Tips: bisa pakai <b>bold</b>, <i>italic</i>, <code>code</code>${NC}"
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
                        echo -e "  ${BGREEN}✓${NC} $uid"
                        ok=$(( ok + 1 ))
                    else
                        echo -e "  ${BRED}✗${NC} $uid (gagal/diblokir)"
                        fail=$(( fail + 1 ))
                    fi
                    sleep 0.1  # Hindari rate limit Telegram
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
                echo ""
                echo -e "  ${BYELLOW}Ketik pesan:${NC}"
                read -rp "  Pesan: " pesan
                [[ -z "$pesan" ]] && continue

                if _send_to_user "$uid" "$pesan"; then
                    echo -e "\n  ${BGREEN}✓ Pesan terkirim ke ${uid}${NC}"
                else
                    echo -e "\n  ${BRED}✗ Gagal kirim. User mungkin memblokir bot.${NC}"
                fi
                echo ""
                press_any_key
                ;;

            3)
                clear
                echo -e "${BCYAN}  ┌──────────────────────────────────────────────┐${NC}"
                echo -e "  │             ${BWHITE}DAFTAR USER TELEGRAM${NC}             │"
                echo -e "${BCYAN}  └──────────────────────────────────────────────┘${NC}"
                echo ""
                printf "  ${BWHITE}%-15s %-12s %-10s${NC}\n" "User ID" "Saldo" "Jml Akun"
                echo -e "  ${BCYAN}────────────────────────────────────────${NC}"

                local found=0
                for uid in "${uids[@]}"; do
                    # Hitung jumlah akun per user
                    local jumlah=0
                    for conf in "$ACCOUNT_DIR"/*.conf; do
                        [[ -f "$conf" ]] || continue
                        local cuid; cuid=$(grep "^TG_USER_ID=" "$conf" | cut -d= -f2 | tr -d "[:space:]")
                        [[ "$cuid" == "$uid" ]] && jumlah=$(( jumlah + 1 ))
                    done
                    # Baca saldo
                    local saldo="0"
                    [[ -f "${SALDO_DIR}/${uid}.saldo" ]] && saldo=$(cat "${SALDO_DIR}/${uid}.saldo" | tr -d "[:space:]")
                    saldo="${saldo#SALDO=}"; [[ "$saldo" =~ ^[0-9]+$ ]] || saldo="0"
                    local saldo_fmt; saldo_fmt=$(python3 -c "print('{:,}'.format(int('$saldo')).replace(',','.'))" 2>/dev/null || echo "$saldo")

                    printf "  ${BGREEN}%-15s${NC} Rp%-12s %-10s\n" "$uid" "$saldo_fmt" "${jumlah} akun"
                    found=$(( found + 1 ))
                done
                [[ $found -eq 0 ]] && echo -e "  ${BYELLOW}Belum ada user.${NC}"
                echo ""
                press_any_key
                ;;

            0) break ;;
            *) echo -e "  ${BRED}Tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}

# Pastikan telegram sudah dikonfigurasi
tg_load || {
    echo -e "${BRED}  Telegram belum dikonfigurasi!${NC}"
    echo -e "  Setup dulu di: System → Setup Telegram Bot"
    press_any_key
    exit 1
}

broadcast_menu
