#!/bin/bash
# ============================================================
#   ZV-Manager - Monitor Online
#   Lihat sesi SSH aktif per akun secara real-time
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh

get_client_ips() {
    local username="$1"
    ss -tnp 2>/dev/null \
        | grep ESTAB \
        | grep ":22\b\|:500\b\|:40000\b\|:109\b\|:143\b" \
        | awk '{print $5}' \
        | grep -v "127.0.0.1" \
        | sed 's/:[0-9]*$//' \
        | sort -u
}

show_monitor() {
    clear
    local today
    today=$(date +"%Y-%m-%d")
    local now
    now=$(date +"%H:%M:%S")

    echo -e "${BCYAN}  ╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${BCYAN}  ║${NC}  ${BWHITE}⚡ MONITOR SSH ONLINE${NC}  ${BYELLOW}${now}${NC}"
    echo -e "${BCYAN}  ╚══════════════════════════════════════════════════╝${NC}"
    echo ""

    local total_sesi=0
    local total_akun_online=0
    local ada_data=false

    printf "  ${BWHITE}%-16s %-8s %-10s %-16s${NC}\n" \
        "Username" "Sesi" "Status" "IP Client"
    echo -e "  ${BCYAN}──────────────────────────────────────────────────${NC}"

    for conf_file in /etc/zv-manager/accounts/ssh/*.conf; do
        [[ -f "$conf_file" ]] || continue
        ada_data=true

        unset USERNAME PASSWORD LIMIT EXPIRED
        source "$conf_file"

        # wc -l selalu return angka bersih, tidak ada masalah exit code
        local sesi
        sesi=$(who 2>/dev/null | grep "^${USERNAME} " | wc -l)
        sesi=$(echo "$sesi" | tr -d '[:space:]')
        [[ -z "$sesi" ]] && sesi=0

        local status_exp
        if [[ "$EXPIRED" < "$today" ]]; then
            status_exp="${BRED}Expired${NC}"
        else
            status_exp="${BGREEN}Aktif${NC}"
        fi

        if [[ "$sesi" -gt 0 ]]; then
            local ips
            ips=$(get_client_ips "$USERNAME")
            local ip_display
            ip_display=$(echo "$ips" | head -1)
            [[ -z "$ip_display" ]] && ip_display="-"

            printf "  ${BGREEN}%-16s${NC} " "$USERNAME"
            printf "${BYELLOW}%-8s${NC} " "${sesi}x"
            printf "%-18b" "$status_exp"
            echo -e "${BCYAN}${ip_display}${NC}"

            local extra_ips
            extra_ips=$(echo "$ips" | tail -n +2)
            if [[ -n "$extra_ips" ]]; then
                while IFS= read -r ip; do
                    printf "  %-16s %-8s %-18s ${BCYAN}%s${NC}\n" "" "" "" "$ip"
                done <<< "$extra_ips"
            fi

            total_sesi=$(( total_sesi + sesi ))
            total_akun_online=$(( total_akun_online + 1 ))
        else
            printf "  ${WHITE}%-16s${NC} " "$USERNAME"
            printf "${WHITE}%-8s${NC} " "offline"
            printf "%-18b\n" "$status_exp"
        fi
    done

    if [[ "$ada_data" == false ]]; then
        echo -e "  ${BYELLOW}Belum ada akun SSH yang dibuat.${NC}"
    fi

    echo ""
    echo -e "  ${BCYAN}──────────────────────────────────────────────────${NC}"
    echo -e "  ${BWHITE}Total sesi aktif :${NC} ${BYELLOW}${total_sesi}${NC}"
    echo -e "  ${BWHITE}Akun online      :${NC} ${BYELLOW}${total_akun_online}${NC}"
    echo ""
}

kill_user_session() {
    read -rp "  Username yang sesinya ingin di-kill: " target
    [[ -z "$target" ]] && return

    if ! id "$target" &>/dev/null; then
        print_error "User '$target' tidak ditemukan!"
        sleep 1
        return
    fi

    local sesi
    sesi=$(who 2>/dev/null | grep "^${target} " | wc -l)
    sesi=$(echo "$sesi" | tr -d '[:space:]')

    if [[ "$sesi" -eq 0 ]]; then
        print_info "User '$target' tidak sedang online."
        sleep 1
        return
    fi

    pkill -u "$target" &>/dev/null
    print_ok "Semua sesi '$target' (${sesi}x) berhasil di-kill!"
    sleep 1
}

monitor_loop() {
    while true; do
        show_monitor

        echo -e "  ${BWHITE}[r]${NC} Refresh   ${BWHITE}[k]${NC} Kill sesi user   ${BRED}[0]${NC} Kembali"
        echo ""
        read -rp "  Pilihan: " choice

        case "$choice" in
            r|R) continue ;;
            k|K) kill_user_session ;;
            0) break ;;
            *) ;;
        esac
    done
}

monitor_loop
