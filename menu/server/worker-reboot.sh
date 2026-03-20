#!/bin/bash
# ============================================================
#   ZV-Manager - Auto Reboot Worker Server
#   Set jadwal reboot otomatis di server tunneling (worker)
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/utils/logger.sh

SERVER_DIR="/etc/zv-manager/servers"
LOCAL_IP=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null | tr -d '[:space:]')

# ── Ambil jadwal reboot aktif dari worker via SSH ─────────────
_get_worker_schedule() {
    local ip="$1" port="$2" user="$3" pass="$4"
    local result
    result=$(sshpass -p "$pass" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=8 \
        -o BatchMode=no \
        -p "$port" "${user}@${ip}" \
        "grep -v '^#' /etc/cron.d/zv-reboot 2>/dev/null | grep -v '^\$' | head -1" 2>/dev/null)
    if [[ -z "$result" ]]; then
        echo "off"
    else
        local hour min
        min=$(awk '{print $1}' <<< "$result")
        hour=$(awk '{print $2}' <<< "$result")
        printf "%02d:%02d" "$hour" "$min"
    fi
}

# ── Set cron reboot di worker ─────────────────────────────────
_set_worker_reboot() {
    local ip="$1" port="$2" user="$3" pass="$4" hour="$5" min="$6"
    sshpass -p "$pass" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 \
        -o BatchMode=no \
        -p "$port" "${user}@${ip}" \
        "printf '# ZV-Manager - Auto Reboot\n${min} ${hour} * * * root /sbin/reboot\n' > /etc/cron.d/zv-reboot && service cron restart" \
        &>/dev/null
    return $?
}

# ── Hapus cron reboot di worker ───────────────────────────────
_del_worker_reboot() {
    local ip="$1" port="$2" user="$3" pass="$4"
    sshpass -p "$pass" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 \
        -o BatchMode=no \
        -p "$port" "${user}@${ip}" \
        "rm -f /etc/cron.d/zv-reboot && service cron restart" \
        &>/dev/null
    return $?
}

worker_reboot_menu() {
    while true; do
        clear
        _sep
        _grad " AUTO REBOOT SERVER WORKER" 255 0 127 0 210 255
        _sep
        echo ""

        # Build daftar server worker (skip lokal)
        local servers=() names=() labels=() schedules=()
        for conf in "${SERVER_DIR}"/*.conf; do
            [[ -f "$conf" ]] || continue
            [[ "$conf" == *.tg.conf ]] && continue
            unset NAME IP PORT USER PASS
            source "$conf"
            [[ -z "$NAME" ]] && continue
            [[ "$IP" == "$LOCAL_IP" ]] && continue   # skip brain

            local tg_label
            tg_label=$(grep "^TG_SERVER_LABEL=" "${SERVER_DIR}/${NAME}.tg.conf" 2>/dev/null \
                | cut -d= -f2 | tr -d '"')
            [[ -z "$tg_label" ]] && tg_label="$NAME"

            servers+=("$conf")
            names+=("$NAME")
            labels+=("$tg_label")
        done

        if [[ ${#servers[@]} -eq 0 ]]; then
            echo -e "  ${BYELLOW}Belum ada server worker yang ditambahkan.${NC}"
            echo ""
            press_any_key
            return
        fi

        # Tampilkan list server + jadwal reboot
        echo -e "  ${BYELLOW}Mengecek jadwal reboot di setiap server...${NC}"
        echo ""
        local i=0
        for conf in "${servers[@]}"; do
            unset NAME IP PORT USER PASS
            source "$conf"
            local sched
            sched=$(_get_worker_schedule "$IP" "${PORT:-22}" "${USER:-root}" "$PASS")
            schedules+=("$sched")
            if [[ "$sched" == "off" ]]; then
                printf "  ${BGREEN}[%s]${NC} %-20s ${BYELLOW}Mati${NC}\n" "$((i+1))" "${labels[$i]}"
            else
                printf "  ${BGREEN}[%s]${NC} %-20s ${BGREEN}Setiap hari jam %s WIB${NC}\n" \
                    "$((i+1))" "${labels[$i]}" "$sched"
            fi
            i=$((i+1))
        done

        echo ""
        echo -e "  ${BRED}[0]${NC} Kembali"
        echo ""
        read -rp "  Pilih server: " choice

        [[ "$choice" == "0" ]] && return
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || \
           [[ "$choice" -lt 1 || "$choice" -gt ${#servers[@]} ]]; then
            print_error "Pilihan tidak valid."
            sleep 1
            continue
        fi

        local idx=$(( choice - 1 ))
        local sel_conf="${servers[$idx]}"
        local sel_name="${names[$idx]}"
        local sel_label="${labels[$idx]}"
        local sel_sched="${schedules[$idx]}"

        unset NAME IP PORT USER PASS
        source "$sel_conf"

        # ── Sub-menu server terpilih ──────────────────────────
        while true; do
            clear
            _sep
            _grad " AUTO REBOOT SERVER WORKER" 255 0 127 0 210 255
            _sep
            echo ""
            echo -e "  ${BWHITE}Server  :${NC} ${BGREEN}${sel_label}${NC}"
            if [[ "$sel_sched" == "off" ]]; then
                echo -e "  ${BWHITE}Jadwal  :${NC} ${BYELLOW}Tidak aktif${NC}"
            else
                echo -e "  ${BWHITE}Jadwal  :${NC} ${BGREEN}Setiap hari jam ${sel_sched} WIB${NC}"
            fi
            echo ""
            echo -e "  ${BWHITE}[1]${NC} Set jam reboot"
            echo -e "  ${BWHITE}[2]${NC} Matikan auto reboot"
            echo -e "  ${BWHITE}[0]${NC} Kembali"
            echo ""
            read -rp "  Pilihan: " sub

            case "$sub" in
                1)
                    echo ""
                    echo -e "  ${BYELLOW}Format HH:MM — contoh: 03:00${NC}"
                    echo -e "  ${BYELLOW}Rekomendasi dini hari saat traffic rendah${NC}"
                    echo ""
                    while true; do
                        read -rp "  Jam reboot [HH:MM]: " input_time
                        if [[ "$input_time" =~ ^([01][0-9]|2[0-3]):([0-5][0-9])$ ]]; then
                            local rhour rmin
                            rhour=$(echo "$input_time" | cut -d: -f1 | sed 's/^0*//')
                            rmin=$(echo  "$input_time" | cut -d: -f2 | sed 's/^0*//')
                            [[ -z "$rhour" ]] && rhour=0
                            [[ -z "$rmin"  ]] && rmin=0
                            echo ""
                            print_info "Menerapkan ke ${sel_label}..."
                            if _set_worker_reboot "$IP" "${PORT:-22}" "${USER:-root}" "$PASS" \
                                                  "$rhour" "$rmin"; then
                                sel_sched=$(printf "%02d:%02d" "$rhour" "$rmin")
                                print_ok "Auto reboot diset jam ${sel_sched} WIB di ${sel_label}."
                            else
                                print_error "Gagal terhubung ke ${sel_label}."
                            fi
                            press_any_key
                            break
                        else
                            echo -e "  ${BRED}Format salah. Gunakan HH:MM (contoh: 03:00)${NC}"
                        fi
                    done
                    ;;
                2)
                    echo ""
                    print_info "Menonaktifkan auto reboot di ${sel_label}..."
                    if _del_worker_reboot "$IP" "${PORT:-22}" "${USER:-root}" "$PASS"; then
                        sel_sched="off"
                        print_ok "Auto reboot dimatikan di ${sel_label}."
                    else
                        print_error "Gagal terhubung ke ${sel_label}."
                    fi
                    press_any_key
                    ;;
                0) break ;;
                *) print_error "Pilihan tidak valid."; sleep 1 ;;
            esac
        done
    done
}

worker_reboot_menu
