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
    printf "  ${BWHITE}%-18s %-14s %-10s %-6s${NC}\n" "Username" "Expired" "Status" "Limit"
    echo -e "  ${BCYAN}──────────────────────────────────────────────────────${NC}"

    local count=0

    # LOCAL
    if is_local_target; then
        for conf_file in /etc/zv-manager/accounts/ssh/*.conf; do
            [[ -f "$conf_file" ]] || continue
            unset USERNAME PASSWORD LIMIT EXPIRED CREATED
            source "$conf_file"

            local status
            if [[ "$EXPIRED" < "$today" ]]; then
                status="${BRED}Expired${NC}"
            else
                status="${BGREEN}Aktif${NC}"
            fi

            local online
            online=$(ps aux | grep -cE "sshd: ${USERNAME}(@|$)" 2>/dev/null || echo 0)
            online=$(( online > 0 ? online : 0 ))

            printf "  %-18s %-14s " "$USERNAME" "$EXPIRED"
            printf "%-17b" "$status"
            echo -e "${BWHITE}${LIMIT}x${NC}  ${BCYAN}${online} online${NC}"

            count=$((count + 1))
        done

        [[ $count -eq 0 ]] && echo -e "  ${BYELLOW}Belum ada akun SSH yang dibuat.${NC}"

    # REMOTE
    else
        print_info "Mengambil data akun dari ${target_info}..."
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
                    status="${BGREEN}Aktif${NC}"
                fi

                printf "  %-18s %-14s " "$r_user" "$r_exp"
                printf "%-17b" "$status"
                echo -e "${BWHITE}${r_limit}x${NC}"

                count=$((count + 1))
            done <<< "$raw"

            [[ $count -eq 0 ]] && echo -e "  ${BYELLOW}Belum ada akun SSH di ${target_info}.${NC}"
        fi
    fi

    echo ""
    echo -e "  ${BYELLOW}Total akun: ${count}${NC}"
    echo ""
    read -rp "  Tekan Enter untuk kembali ke menu... " _dummy
    echo ""
}

list_ssh_users
