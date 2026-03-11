#!/bin/bash
# ============================================================
#   ZV-Manager - Statistik Penjualan
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/helpers.sh

ACCOUNT_DIR="/etc/zv-manager/accounts/ssh"
VMESS_DIR="/etc/zv-manager/accounts/vmess"
SALDO_DIR="/etc/zv-manager/accounts/saldo"
SERVER_DIR="/etc/zv-manager/servers"
LOG="/var/log/zv-manager/install.log"

_fmt() {
    local n="${1//[^0-9]/}" result="" len i
    [[ -z "$n" || "$n" == "0" ]] && { echo "0"; return; }
    n=$(( 10#$n )); len=${#n}
    for (( i=0; i<len; i++ )); do
        [[ $i -gt 0 && $(( (len-i) % 3 )) -eq 0 ]] && result="${result}."
        result="${result}${n:$i:1}"
    done
    echo "$result"
}

_today()     { date +"%Y-%m-%d"; }
_this_month(){ date +"%Y-%m"; }

show_statistik() {
    while true; do
        clear
        local today; today=$(_today)
        local this_month; this_month=$(_this_month)
        local now_ts; now_ts=$(date +%s)

        # ── Hitung akun SSH ───────────────────────────────────────
        local ssh_total=0 ssh_aktif=0 ssh_expired=0
        local ssh_premium=0 ssh_trial=0
        local ssh_baru_hari=0 ssh_baru_bulan=0

        for conf in "$ACCOUNT_DIR"/*.conf; do
            [[ -f "$conf" ]] || continue
            local exp created is_trial
            exp=$(grep      "^EXPIRED="  "$conf" | cut -d= -f2)
            created=$(grep  "^CREATED="  "$conf" | cut -d= -f2)
            is_trial=$(grep "^IS_TRIAL=" "$conf" | cut -d= -f2)

            ssh_total=$(( ssh_total + 1 ))
            [[ "$is_trial" == "1" ]] && ssh_trial=$(( ssh_trial + 1 )) || ssh_premium=$(( ssh_premium + 1 ))
            [[ "$exp" < "$today" ]] && ssh_expired=$(( ssh_expired + 1 )) || ssh_aktif=$(( ssh_aktif + 1 ))
            [[ "$created" == "$today" ]]       && ssh_baru_hari=$(( ssh_baru_hari + 1 ))
            [[ "$created" == "$this_month"* ]] && ssh_baru_bulan=$(( ssh_baru_bulan + 1 ))
        done

        # ── Hitung akun VMess ─────────────────────────────────────
        local vm_total=0 vm_aktif=0 vm_expired=0
        local vm_premium=0 vm_trial=0
        local vm_baru_hari=0 vm_baru_bulan=0

        if [[ -d "$VMESS_DIR" ]]; then
            for conf in "$VMESS_DIR"/*.conf; do
                [[ -f "$conf" ]] || continue
                local v_exp_ts v_created v_trial
                v_exp_ts=$(grep "^EXPIRED_TS=" "$conf" | cut -d= -f2 | tr -d '"' | tr -d '[:space:]')
                v_created=$(grep "^CREATED="   "$conf" | cut -d= -f2 | tr -d '"')
                v_trial=$(grep   "^IS_TRIAL="  "$conf" | cut -d= -f2 | tr -d '"')

                vm_total=$(( vm_total + 1 ))
                [[ "$v_trial" == "1" ]] && vm_trial=$(( vm_trial + 1 )) || vm_premium=$(( vm_premium + 1 ))
                if [[ -n "$v_exp_ts" && "$v_exp_ts" =~ ^[0-9]+$ ]]; then
                    [[ "$v_exp_ts" -lt "$now_ts" ]] && vm_expired=$(( vm_expired + 1 )) || vm_aktif=$(( vm_aktif + 1 ))
                fi
                [[ "$v_created" == "$today" ]]       && vm_baru_hari=$(( vm_baru_hari + 1 ))
                [[ "$v_created" == "$this_month"* ]] && vm_baru_bulan=$(( vm_baru_bulan + 1 ))
            done
        fi

        # ── Total gabungan ────────────────────────────────────────
        local total_akun=$(( ssh_total + vm_total ))
        local total_aktif=$(( ssh_aktif + vm_aktif ))
        local total_expired=$(( ssh_expired + vm_expired ))
        local baru_hari=$(( ssh_baru_hari + vm_baru_hari ))
        local baru_bulan=$(( ssh_baru_bulan + vm_baru_bulan ))

        # ── Hitung total saldo semua user ─────────────────────────
        local total_saldo=0
        for sf in "$SALDO_DIR"/*.saldo; do
            [[ -f "$sf" ]] || continue
            local sv; sv=$(cat "$sf" | tr -d "[:space:]")
            sv="${sv#SALDO=}"
            [[ "$sv" =~ ^[0-9]+$ ]] && total_saldo=$(( total_saldo + sv ))
        done

        # ── Pendapatan dari log (semua jenis transaksi) ───────────
        # Match: BELI:, VMESS_BELI:, RENEW:, VMESS_RENEW:, BW_BELI:, VMESS_BW_BELI:
        local pendapatan_hari=0 pendapatan_bulan=0
        if [[ -f "$LOG" ]]; then
            while IFS= read -r line; do
                [[ "$line" == *"total="* ]] || continue
                echo "$line" | grep -qE "(BELI|RENEW):" || continue
                local nominal; nominal=$(echo "$line" | grep -oP 'total=\K[0-9]+')
                [[ -z "$nominal" ]] && continue
                local log_date; log_date=$(echo "$line" | grep -oP '^\[\K[0-9]{4}-[0-9]{2}-[0-9]{2}')
                [[ "$log_date" == "$today" ]]       && pendapatan_hari=$(( pendapatan_hari + nominal ))
                [[ "$log_date" == "$this_month"* ]] && pendapatan_bulan=$(( pendapatan_bulan + nominal ))
            done < <(tail -n 2000 "$LOG")
        fi

        # ── Hitung per server ─────────────────────────────────────
        local server_stats=""
        declare -A srv_count_ssh srv_count_vm
        for ac in "$ACCOUNT_DIR"/*.conf; do
            [[ -f "$ac" ]] || continue
            local asrv; asrv=$(grep "^SERVER=" "$ac" | cut -d= -f2)
            [[ -n "$asrv" ]] && srv_count_ssh["$asrv"]=$(( ${srv_count_ssh["$asrv"]:-0} + 1 ))
        done
        if [[ -d "$VMESS_DIR" ]]; then
            for ac in "$VMESS_DIR"/*.conf; do
                [[ -f "$ac" ]] || continue
                local asrv; asrv=$(grep "^SERVER=" "$ac" | cut -d= -f2)
                [[ -n "$asrv" ]] && srv_count_vm["$asrv"]=$(( ${srv_count_vm["$asrv"]:-0} + 1 ))
            done
        fi
        for conf in "$SERVER_DIR"/*.conf; do
            [[ -f "$conf" && "$conf" != *.tg.conf ]] || continue
            local sname; sname=$(grep "^NAME=" "$conf" | cut -d= -f2)
            if [[ -n "$sname" ]]; then
                local s_ssh="${srv_count_ssh[$sname]:-0}" s_vm="${srv_count_vm[$sname]:-0}"
                server_stats+="  ${BWHITE}${sname}${NC} : SSH ${BGREEN}${s_ssh}${NC} | VMess ${BGREEN}${s_vm}${NC}\n"
            fi
        done

        # ── Tampilan ──────────────────────────────────────────────
        echo -e "${BCYAN}  ┌──────────────────────────────────────────────┐${NC}"
        echo -e "  │           ${BWHITE}STATISTIK PENJUALAN${NC}               │"
        echo -e "${BCYAN}  └──────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "  ${BCYAN}[ Akun SSH ]${NC}"
        printf "  ${BWHITE}%-22s${NC} ${BGREEN}%s${NC}\n" "Total SSH"     "$ssh_total"
        printf "  ${BWHITE}%-22s${NC} ${BGREEN}%s${NC}\n" "Aktif"         "$ssh_aktif"
        printf "  ${BWHITE}%-22s${NC} ${BRED}%s${NC}\n"   "Expired"       "$ssh_expired"
        printf "  ${BWHITE}%-22s${NC} ${BYELLOW}%s${NC}\n" "Premium"      "$ssh_premium"
        printf "  ${BWHITE}%-22s${NC} ${BYELLOW}%s${NC}\n" "Trial"        "$ssh_trial"
        echo ""
        echo -e "  ${BCYAN}[ Akun VMess ]${NC}"
        printf "  ${BWHITE}%-22s${NC} ${BGREEN}%s${NC}\n" "Total VMess"   "$vm_total"
        printf "  ${BWHITE}%-22s${NC} ${BGREEN}%s${NC}\n" "Aktif"         "$vm_aktif"
        printf "  ${BWHITE}%-22s${NC} ${BRED}%s${NC}\n"   "Expired"       "$vm_expired"
        printf "  ${BWHITE}%-22s${NC} ${BYELLOW}%s${NC}\n" "Premium"      "$vm_premium"
        printf "  ${BWHITE}%-22s${NC} ${BYELLOW}%s${NC}\n" "Trial"        "$vm_trial"
        echo ""
        echo -e "  ${BCYAN}[ Total Gabungan ]${NC}"
        printf "  ${BWHITE}%-22s${NC} ${BGREEN}%s${NC}\n" "Total Semua"   "$total_akun"
        printf "  ${BWHITE}%-22s${NC} ${BGREEN}%s${NC}\n" "Aktif"         "$total_aktif"
        printf "  ${BWHITE}%-22s${NC} ${BRED}%s${NC}\n"   "Expired"       "$total_expired"
        echo ""
        echo -e "  ${BCYAN}[ Baru ]${NC}"
        printf "  ${BWHITE}%-22s${NC} ${BGREEN}%s akun${NC}\n" "Hari ini ($today)"      "$baru_hari"
        printf "  ${BWHITE}%-22s${NC} ${BGREEN}%s akun${NC}\n" "Bulan ini ($this_month)" "$baru_bulan"
        echo ""
        echo -e "  ${BCYAN}[ Pendapatan ]${NC}"
        printf "  ${BWHITE}%-22s${NC} ${BGREEN}Rp%s${NC}\n"  "Hari ini"     "$(_fmt "$pendapatan_hari")"
        printf "  ${BWHITE}%-22s${NC} ${BGREEN}Rp%s${NC}\n"  "Bulan ini"    "$(_fmt "$pendapatan_bulan")"
        printf "  ${BWHITE}%-22s${NC} ${BYELLOW}Rp%s${NC}\n" "Saldo di bot" "$(_fmt "$total_saldo")"
        echo ""
        if [[ -n "$server_stats" ]]; then
            echo -e "  ${BCYAN}[ Per Server ]${NC}"
            echo -e "$server_stats"
        fi
        echo -e "  ${BCYAN}─────────────────────────────────────────────${NC}"
        echo -e "  ${BYELLOW}[r]${NC} Refresh    ${BRED}[0]${NC} Kembali"
        echo ""
        read -rp "  Pilihan: " ch
        case "$ch" in
            r|R) continue ;;
            0)   break ;;
            *)   ;;
        esac
    done
}

show_statistik
