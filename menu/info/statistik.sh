#!/bin/bash
# ============================================================
#   ZV-Manager - Statistik Penjualan
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/helpers.sh

ACCOUNT_DIR="/etc/zv-manager/accounts/ssh"
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

        # ── Hitung semua akun ─────────────────────────────────────
        local total_akun=0 aktif=0 expired_count=0
        local premium=0 trial_count=0
        local baru_hari=0 baru_bulan=0

        for conf in "$ACCOUNT_DIR"/*.conf; do
            [[ -f "$conf" ]] || continue
            local exp created is_trial
            exp=$(grep     "^EXPIRED="  "$conf" | cut -d= -f2)
            created=$(grep "^CREATED="  "$conf" | cut -d= -f2)
            is_trial=$(grep "^IS_TRIAL=" "$conf" | cut -d= -f2)

            total_akun=$(( total_akun + 1 ))
            [[ "$is_trial" == "1" ]] && trial_count=$(( trial_count + 1 )) || premium=$(( premium + 1 ))
            [[ "$exp" < "$today" ]] && expired_count=$(( expired_count + 1 )) || aktif=$(( aktif + 1 ))
            [[ "$created" == "$today" ]]       && baru_hari=$(( baru_hari + 1 ))
            [[ "$created" == "$this_month"* ]] && baru_bulan=$(( baru_bulan + 1 ))
        done

        # ── Hitung total saldo semua user ─────────────────────────
        local total_saldo=0
        for sf in "$SALDO_DIR"/*.saldo; do
            [[ -f "$sf" ]] || continue
            local sv; sv=$(cat "$sf" | tr -d "[:space:]")
            sv="${sv#SALDO=}"
            [[ "$sv" =~ ^[0-9]+$ ]] && total_saldo=$(( total_saldo + sv ))
        done

        # ── Estimasi pendapatan dari log — tail 2000 baris ───────
        local pendapatan_hari=0 pendapatan_bulan=0
        if [[ -f "$LOG" ]]; then
            while IFS= read -r line; do
                [[ "$line" == *"BELI:"* && "$line" == *"total="* ]] || continue
                local nominal; nominal=$(echo "$line" | grep -oP 'total=\K[0-9]+')
                [[ -z "$nominal" ]] && continue
                local log_date; log_date=$(echo "$line" | grep -oP '^\[\K[0-9]{4}-[0-9]{2}-[0-9]{2}')
                [[ "$log_date" == "$today" ]]       && pendapatan_hari=$(( pendapatan_hari + nominal ))
                [[ "$log_date" == "$this_month"* ]] && pendapatan_bulan=$(( pendapatan_bulan + nominal ))
            done < <(tail -n 2000 "$LOG")
        fi

        # ── Hitung per server — O(n) dengan awk ─────────────────
        local server_stats=""
        declare -A srv_count
        for ac in "$ACCOUNT_DIR"/*.conf; do
            [[ -f "$ac" ]] || continue
            local asrv; asrv=$(grep "^SERVER=" "$ac" | cut -d= -f2)
            [[ -n "$asrv" ]] && srv_count["$asrv"]=$(( ${srv_count["$asrv"]:-0} + 1 ))
        done
        for conf in "$SERVER_DIR"/*.conf; do
            [[ -f "$conf" && "$conf" != *.tg.conf ]] || continue
            local sname; sname=$(grep "^NAME=" "$conf" | cut -d= -f2)
            [[ -n "$sname" ]] && server_stats+="  ${BWHITE}${sname}${NC} : ${BGREEN}${srv_count[$sname]:-0} akun${NC}\n"
        done

        # ── Tampilan ──────────────────────────────────────────────
        echo -e "${BCYAN}  ┌──────────────────────────────────────────────┐${NC}"
        echo -e "  │           ${BWHITE}STATISTIK PENJUALAN${NC}               │"
        echo -e "${BCYAN}  └──────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "  ${BCYAN}[ Akun ]${NC}"
        printf "  ${BWHITE}%-22s${NC} ${BGREEN}%s${NC}\n" "Total Akun"    "$total_akun"
        printf "  ${BWHITE}%-22s${NC} ${BGREEN}%s${NC}\n" "Aktif"         "$aktif"
        printf "  ${BWHITE}%-22s${NC} ${BRED}%s${NC}\n"   "Expired"       "$expired_count"
        printf "  ${BWHITE}%-22s${NC} ${BYELLOW}%s${NC}\n" "Premium"      "$premium"
        printf "  ${BWHITE}%-22s${NC} ${BYELLOW}%s${NC}\n" "Trial"        "$trial_count"
        echo ""
        echo -e "  ${BCYAN}[ Baru ]${NC}"
        printf "  ${BWHITE}%-22s${NC} ${BGREEN}%s akun${NC}\n" "Hari ini ($today)"   "$baru_hari"
        printf "  ${BWHITE}%-22s${NC} ${BGREEN}%s akun${NC}\n" "Bulan ini ($this_month)" "$baru_bulan"
        echo ""
        echo -e "  ${BCYAN}[ Pendapatan ]${NC}"
        printf "  ${BWHITE}%-22s${NC} ${BGREEN}Rp%s${NC}\n" "Hari ini"      "$(_fmt "$pendapatan_hari")"
        printf "  ${BWHITE}%-22s${NC} ${BGREEN}Rp%s${NC}\n" "Bulan ini"     "$(_fmt "$pendapatan_bulan")"
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
