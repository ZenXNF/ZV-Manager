#!/bin/bash
# ============================================================
#   ZV-Manager - List SSH Users (Local + Remote)
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/remote.sh

list_ssh_users() {
    local target
    target=$(get_target_server)
    local target_info
    target_info=$(target_display)

    clear
    local today
    today=$(date +"%Y-%m-%d")

    echo -e "${BCYAN} ┌──────────────────────────────────────────────────────────┐${NC}"
    echo -e " │                  ${BWHITE}DAFTAR AKUN SSH AKTIF${NC}                  │"
    echo -e "${BCYAN} └──────────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BWHITE}Target :${NC} ${BGREEN}${target_info}${NC}"
    echo ""
    printf "  ${BWHITE}%-18s %-14s %-10s %-6s %-8s${NC}\n" "Username" "Expired" "Status" "Limit" "Type"
    echo -e "  ${BCYAN}──────────────────────────────────────────────────────────${NC}"

    local count=0

    if is_local_target; then
        local account_dir="/etc/zv-manager/accounts/ssh"

        # Pastikan dir ada
        if [[ ! -d "$account_dir" ]]; then
            echo -e "  ${BYELLOW}Direktori akun belum ada.${NC}"
        else
            local found=0
            for conf_file in "$account_dir"/*.conf; do
                [[ -f "$conf_file" ]] || continue
                found=1

                # Baca per-field, hindari source langsung
                local uname exp limit is_trial
                uname=$(grep "^USERNAME=" "$conf_file" | cut -d= -f2)
                exp=$(grep "^EXPIRED=" "$conf_file" | cut -d= -f2)
                limit=$(grep "^LIMIT=" "$conf_file" | cut -d= -f2)
                is_trial=$(grep "^IS_TRIAL=" "$conf_file" | cut -d= -f2)

                [[ -z "$uname" ]] && continue

                local status type_label
                if [[ "$exp" < "$today" ]]; then
                    status="${BRED}Expired${NC}"
                else
                    status="${BGREEN}Aktif  ${NC}"
                fi

                [[ "$is_trial" == "1" ]] && type_label="${BYELLOW}Trial${NC}" || type_label="${BWHITE}SSH  ${NC}"

                local online
                online=$(ps aux 2>/dev/null | grep -cE "sshd: ${uname}(@pts|$)" || true)
                online=$(( online > 0 ? online : 0 ))

                printf "  %-18s %-14s " "$uname" "$exp"
                printf "%-17b" "$status"
                printf "%-7s " "${limit}x"
                printf "%-14b" "$type_label"
                echo -e "${BCYAN}${online} online${NC}"

                count=$((count + 1))
            done

            [[ $found -eq 0 || $count -eq 0 ]] && \
                echo -e "  ${BYELLOW}Belum ada akun SSH yang dibuat.${NC}"
        fi

    else
        echo -e "  ${BCYAN}Mengambil data dari ${target_info}...${NC}"
        echo ""

        local raw
        raw=$(remote_agent "$target" "list")

        if [[ "$raw" == REMOTE-ERR* ]]; then
            echo -e "  ${BRED}${raw#REMOTE-ERR|}${NC}"
        elif [[ "$raw" == "LIST-EMPTY" || -z "$raw" ]]; then
            echo -e "  ${BYELLOW}Belum ada akun SSH di ${target_info}.${NC}"
        else
            while IFS='|' read -r r_user r_pass r_limit r_exp r_created; do
                [[ -z "$r_user" ]] && continue

                local status
                if [[ "$r_exp" < "$today" ]]; then
                    status="${BRED}Expired${NC}"
                else
                    status="${BGREEN}Aktif  ${NC}"
                fi

                printf "  %-18s %-14s " "$r_user" "$r_exp"
                printf "%-17b" "$status"
                echo -e "${BWHITE}${r_limit}x${NC}"

                count=$((count + 1))
            done <<< "$raw"

            [[ $count -eq 0 ]] && \
                echo -e "  ${BYELLOW}Belum ada akun SSH di ${target_info}.${NC}"
        fi
    fi

    echo ""
    echo -e "  ${BYELLOW}Total akun: ${count}${NC}"
    echo ""
    read -rp "  Tekan Enter untuk kembali..." _dummy < /dev/tty
    echo ""
}

list_ssh_users
