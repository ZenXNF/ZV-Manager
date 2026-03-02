#!/bin/bash
# ============================================================
#   ZV-Manager - Monitor Online
#   Deteksi sesi SSH aktif per akun (direct + tunneled)
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh

# Hitung sesi aktif per user
# who → hanya PTY/direct SSH
# ps aux "sshd: USER" → deteksi tunneled (HTTP Custom, WS, dll)
# Gabungkan keduanya dan deduplikasi
count_sessions() {
    local username="$1"

    # Sesi direct SSH (via who)
    local direct
    direct=$(who 2>/dev/null | grep "^${username} " | wc -l)
    direct=$(echo "$direct" | tr -d '[:space:]')

    # Sesi tunneled — deteksi dari sshd process yang berjalan untuk user ini
    # Setiap koneksi SSH (termasuk tunneled) menghasilkan "sshd: username" di ps
    # Exclude: [priv] (monitor process, bukan user session) dan grep itu sendiri
    local tunneled
    tunneled=$(ps aux 2>/dev/null \
        | grep "sshd: ${username}" \
        | grep -v "\[priv\]\|grep" \
        | wc -l)
    tunneled=$(echo "$tunneled" | tr -d '[:space:]')

    # Ambil nilai terbesar antara direct dan tunneled
    # (tunneled sudah mencakup direct, tapi kadang ps lebih akurat)
    if [[ "$tunneled" -gt "$direct" ]]; then
        echo "$tunneled"
    else
        echo "$direct"
    fi
}

# Ambil IP client dari sesi aktif user
get_client_ips() {
    local username="$1"
    # IP dari direct SSH (via who)
    local direct_ips
    direct_ips=$(who 2>/dev/null \
        | grep "^${username} " \
        | awk '{print $5}' \
        | sed 's/[()]//g' \
        | grep -v "^$")

    # IP dari ws-proxy connection (tunneled lewat localhost)
    # Kalau ada tunneled session → tampilkan "(via tunnel)"
    local tunneled
    tunneled=$(ps aux 2>/dev/null \
        | grep "sshd: ${username}" \
        | grep -v "\[priv\]\|grep\|$(who 2>/dev/null | grep "^${username} " | awk '{print $2}' | head -1)" \
        | wc -l)
    tunneled=$(echo "$tunneled" | tr -d '[:space:]')

    if [[ -n "$direct_ips" ]]; then
        echo "$direct_ips"
    elif [[ "$tunneled" -gt 0 ]]; then
        echo "via-tunnel"
    fi
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
        "Username" "Sesi" "Status" "IP/Mode"
    echo -e "  ${BCYAN}──────────────────────────────────────────────────${NC}"

    for conf_file in /etc/zv-manager/accounts/ssh/*.conf; do
        [[ -f "$conf_file" ]] || continue
        ada_data=true

        unset USERNAME PASSWORD LIMIT EXPIRED
        source "$conf_file"

        local sesi
        sesi=$(count_sessions "$USERNAME")
        [[ -z "$sesi" ]] && sesi=0

        local status_exp
        if [[ "$EXPIRED" < "$today" ]]; then
            status_exp="${BRED}Expired${NC}"
        else
            status_exp="${BGREEN}Aktif${NC}"
        fi

        if [[ "$sesi" -gt 0 ]]; then
            local ip_display
            ip_display=$(get_client_ips "$USERNAME" | head -1)
            [[ -z "$ip_display" ]] && ip_display="tunnel"

            printf "  ${BGREEN}%-16s${NC} " "$USERNAME"
            printf "${BYELLOW}%-8s${NC} " "${sesi}x"
            printf "%-18b" "$status_exp"
            echo -e "${BCYAN}${ip_display}${NC}"

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
    sesi=$(count_sessions "$target")

    if [[ "$sesi" -eq 0 ]]; then
        print_info "User '$target' tidak sedang online."
        sleep 1
        return
    fi

    # Kill semua proses: session PTY + tunneled sshd process
    pkill -u "$target" &>/dev/null
    pkill -f "sshd: ${target}" &>/dev/null
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
