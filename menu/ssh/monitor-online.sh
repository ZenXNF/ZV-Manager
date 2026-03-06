#!/bin/bash
# ============================================================
#   ZV-Manager - Monitor Online
#   Deteksi semua tipe koneksi: Direct SSH, WebSocket, UDP Custom, Dropbear
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/utils/remote.sh

# ============================================================
# Hitung semua sesi aktif untuk satu user
# - sshd: username@notty  → WS/UDP/Direct (no PTY, via proxy)
# - sshd: username@pts/x  → Direct SSH interactive
# - dropbear: username    → Dropbear connection
# who tidak dipakai → tidak detect koneksi tanpa PTY (UDP/WS)
# ============================================================
# File tracking koneksi UDP Custom dari udp-tracker
UDP_ONLINE_FILE="/tmp/zv-udp-online"

count_sessions() {
    local username="$1"
    local n_ssh n_drop n_udp
    n_ssh=$(ps aux | grep -E "sshd: ${username}(@|$)" | grep -v grep | grep -v '\[priv\]' | wc -l)
    n_drop=$(ps aux | grep -E "dropbear: ${username}(@|$)" | grep -v grep | wc -l)
    # Cek koneksi UDP Custom dari tracker file
    n_udp=0
    if [[ -f "$UDP_ONLINE_FILE" ]]; then
        grep -qi "^${username}:1" "$UDP_ONLINE_FILE" 2>/dev/null && n_udp=1
    fi
    echo $(( n_ssh + n_drop + n_udp ))
}

# Tipe koneksi dari UDP tracker file
get_ws_type() {
    local username="$1"
    [[ ! -f "$UDP_ONLINE_FILE" ]] && return
    grep -qi "^${username}:1" "$UDP_ONLINE_FILE" 2>/dev/null && echo "UDP"
}

# ============================================================
# Deteksi tipe koneksi + IP untuk user tertentu
# ============================================================
get_connection_info() {
    local username="$1"

    # PID sshd worker untuk user ini (bukan [priv])
    local ssh_pids
    mapfile -t ssh_pids < <(
        ps aux | grep -E "sshd: ${username}(@|$)" \
               | grep -v grep | grep -v '\[priv\]' \
               | awk '{print $2}'
    )

    # PID dropbear untuk user ini
    local drop_pids
    mapfile -t drop_pids < <(
        ps aux | grep -E "dropbear: ${username}(@|$)" \
               | grep -v grep \
               | awk '{print $2}'
    )

    local direct_ips=()
    local has_tunneled=false

    # --- Cek koneksi tiap sshd worker ---
    for pid in "${ssh_pids[@]}"; do
        [[ -z "$pid" ]] && continue

        # PPID = sshd monitor [priv] yang pegang socket
        local ppid
        ppid=$(awk '{print $4}' /proc/"$pid"/stat 2>/dev/null)

        local remote_ip=""
        for check_pid in "$pid" "$ppid"; do
            [[ -z "$check_pid" ]] && continue
            remote_ip=$(ss -tnp 2>/dev/null \
                | grep "pid=${check_pid}," \
                | awk '{print $5}' \
                | sed 's/:[0-9]*$//' \
                | grep -v "^$" \
                | head -1)
            [[ -n "$remote_ip" ]] && break
        done

        if [[ -z "$remote_ip" ]] || [[ "$remote_ip" =~ ^127\. ]] || [[ "$remote_ip" == "::1" ]]; then
            has_tunneled=true
        else
            direct_ips+=("$remote_ip")
        fi
    done

    # --- Cek koneksi tiap dropbear ---
    for pid in "${drop_pids[@]}"; do
        [[ -z "$pid" ]] && continue
        local remote_ip
        remote_ip=$(ss -tnp 2>/dev/null \
            | grep "pid=${pid}," \
            | awk '{print $5}' \
            | sed 's/:[0-9]*$//' \
            | grep -v "^$" \
            | head -1)

        if [[ -n "$remote_ip" ]] && ! [[ "$remote_ip" =~ ^127\. ]]; then
            direct_ips+=("${remote_ip} (Dropbear)")
        else
            has_tunneled=true
        fi
    done

    # --- Cek WS/UDP dari tracking file ---
    local ws_type
    ws_type=$(get_ws_type "$username")
    [[ -n "$ws_type" ]] && has_tunneled=true

    # --- Output IP direct (deduplikasi) ---
    local shown=()
    for ip in "${direct_ips[@]}"; do
        local dup=false
        for s in "${shown[@]}"; do [[ "$s" == "$ip" ]] && dup=true; done
        if [[ "$dup" == false ]]; then
            shown+=("$ip")
            echo "$ip"
        fi
    done

    # --- Output label tunnel ---
    if [[ "$has_tunneled" == true ]]; then
        # Cek UDP tracker file dulu (prioritas tertinggi)
        if [[ -n "$ws_type" ]]; then
            echo "[UDP]"
        else
            # Fallback: deteksi dari port aktif
            local udp_conns ws_conns
            udp_conns=$(ss -unp 2>/dev/null | grep -c ":36712" || echo 0)
            ws_conns=$(ss -tnp 2>/dev/null | grep ":8880" | grep -c "ESTAB" || echo 0)
            # Pastikan hanya angka
            [[ ! "$udp_conns" =~ ^[0-9]+$ ]] && udp_conns=0
            [[ ! "$ws_conns"  =~ ^[0-9]+$ ]] && ws_conns=0

            if   [[ "$udp_conns" -gt 0 ]] && [[ "$ws_conns" -gt 0 ]]; then
                echo "[UDP + WS]"
            elif [[ "$udp_conns" -gt 0 ]]; then
                echo "[UDP]"
            elif [[ "$ws_conns" -gt 0 ]]; then
                echo "[WebSocket]"
            else
                echo "[Tunnel]"
            fi
        fi
    fi
}

show_monitor() {
    clear
    local today now
    today=$(date +"%Y-%m-%d")
    now=$(date +"%H:%M:%S")

    local target
    target=$(get_target_server)
    local target_info
    target_info=$(target_display)

    echo -e "${BCYAN}  ╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${BCYAN}  ║${NC}  ${BWHITE}⚡ MONITOR SSH ONLINE${NC}  ${BYELLOW}${now}${NC}"
    echo -e "${BCYAN}  ║${NC}  ${BWHITE}Target :${NC} ${BGREEN}${target_info}${NC}"
    echo -e "${BCYAN}  ╚══════════════════════════════════════════════════╝${NC}"
    echo ""

    local total_sesi=0
    local total_akun_online=0
    local ada_data=false

    # ---- REMOTE mode: tampilkan hanya jumlah sesi ----
    if ! is_local_target; then
        print_info "Mengambil data online dari ${target_info}..."
        echo ""
        local raw
        raw=$(remote_agent "$target" "online")
        printf "  ${BWHITE}%-16s %-8s${NC}\n" "Username" "Sesi"
        echo -e "  ${BCYAN}──────────────────────────────────────────────────────${NC}"
        if [[ "$raw" == REMOTE-ERR* ]]; then
            echo -e "  ${BRED}${raw#REMOTE-ERR|}${NC}"
        elif [[ -z "$raw" ]]; then
            echo -e "  ${BYELLOW}Belum ada akun SSH.${NC}"
        else
            while IFS='|' read -r r_user r_sesi; do
                [[ -z "$r_user" ]] && continue
                ada_data=true
                if [[ "$r_sesi" -gt 0 ]]; then
                    printf "  ${BGREEN}%-16s${NC} ${BYELLOW}%sx${NC}\n" "$r_user" "$r_sesi"
                    total_sesi=$(( total_sesi + r_sesi ))
                    total_akun_online=$(( total_akun_online + 1 ))
                else
                    printf "  ${WHITE}%-16s${NC} ${WHITE}offline${NC}\n" "$r_user"
                fi
            done <<< "$raw"
        fi
        echo ""
        echo -e "  ${BCYAN}──────────────────────────────────────────────────────${NC}"
        echo -e "  ${BWHITE}Total sesi aktif :${NC} ${BYELLOW}${total_sesi}${NC}"
        echo -e "  ${BWHITE}Akun online      :${NC} ${BYELLOW}${total_akun_online}${NC}"
        echo ""
        return
    fi

    # ---- LOCAL mode ----
    printf "  ${BWHITE}%-16s %-7s %-9s %-22s${NC}\n" \
        "Username" "Sesi" "Status" "Koneksi"
    echo -e "  ${BCYAN}──────────────────────────────────────────────────────${NC}"

    for conf_file in /etc/zv-manager/accounts/ssh/*.conf; do
        [[ -f "$conf_file" ]] || continue
        ada_data=true

        unset USERNAME PASSWORD LIMIT EXPIRED
        source "$conf_file"

        local sesi
        sesi=$(count_sessions "$USERNAME")
        sesi="${sesi// /}"
        [[ -z "$sesi" ]] && sesi=0

        local status_exp
        if [[ "$EXPIRED" < "$today" ]]; then
            status_exp="${BRED}Expired${NC}"
        else
            status_exp="${BGREEN}Aktif${NC}"
        fi

        if [[ "$sesi" -gt 0 ]]; then
            local conn_lines
            mapfile -t conn_lines < <(get_connection_info "$USERNAME")
            local first_conn="${conn_lines[0]:-?}"

            printf "  ${BGREEN}%-16s${NC} " "$USERNAME"
            printf "${BYELLOW}%-7s${NC} " "${sesi}x"
            printf "%-17b" "$status_exp"
            echo -e "${BCYAN}${first_conn}${NC}"

            for ((i=1; i<${#conn_lines[@]}; i++)); do
                printf "  %-16s %-7s %-17s ${BCYAN}%s${NC}\n" \
                    "" "" "" "${conn_lines[$i]}"
            done

            total_sesi=$(( total_sesi + sesi ))
            total_akun_online=$(( total_akun_online + 1 ))
        else
            printf "  ${WHITE}%-16s${NC} " "$USERNAME"
            printf "${WHITE}%-7s${NC} " "offline"
            printf "%-17b\n" "$status_exp"
        fi
    done

    if [[ "$ada_data" == false ]]; then
        echo -e "  ${BYELLOW}Belum ada akun SSH yang dibuat.${NC}"
    fi

    echo ""
    echo -e "  ${BCYAN}──────────────────────────────────────────────────────${NC}"
    echo -e "  ${BWHITE}Total sesi aktif :${NC} ${BYELLOW}${total_sesi}${NC}"
    echo -e "  ${BWHITE}Akun online      :${NC} ${BYELLOW}${total_akun_online}${NC}"
    echo ""
    echo -e "  ${WHITE}Koneksi: IP=Direct  [WebSocket]=WS/WSS  [UDP Custom]=UDP  [Tunnel]=Umum${NC}"
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

    # Kill semua proses user (termasuk sshd tunneled sessions)
    pkill -u "$target" &>/dev/null
    for pid in $(ps aux | grep "sshd: ${target}" | grep -v grep | grep -v '\[priv\]' | awk '{print $2}'); do
        kill -9 "$pid" &>/dev/null
    done

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
