#!/bin/bash
source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/utils/remote.sh

ZIVPN_ACCT_DIR="/etc/zv-manager/accounts/zivpn"

_gen_zivpn_pw()   { tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 16; }
_gen_zivpn_user() { local r; r=$(tr -dc 'a-z0-9' < /dev/urandom | head -c 6); echo "zivpn-${r}"; }

add_zivpn() {
    clear; _sep; _grad " BUAT AKUN ZIVPN UDP" 0 210 255 160 80 255; _sep; echo ""

    # Pilih server
    local server_dir="/etc/zv-manager/servers"
    local local_ip; local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null)
    local count=0 snames=()
    for conf in "${server_dir}"/*.conf; do
        [[ -f "$conf" && "$conf" != *.tg.conf ]] || continue
        unset NAME IP; source "$conf"
        count=$((count+1)); snames+=("$NAME")
        local mark=""; [[ "$IP" == "$local_ip" ]] && mark=" ${BYELLOW}[lokal]${NC}"
        echo -e "  ${BGREEN}[${count}]${NC} ${BWHITE}${NAME}${NC} — ${IP}${mark}"
    done
    [[ $count -eq 0 ]] && { print_error "Belum ada server."; press_any_key; return; }
    echo ""; echo -e "  ${BRED}[0]${NC} Kembali"; echo ""
    read -rp "  Pilih server: " schoice
    [[ "$schoice" == "0" ]] && return
    if ! [[ "$schoice" =~ ^[0-9]+$ ]] || [[ "$schoice" -lt 1 || "$schoice" -gt $count ]]; then
        print_error "Pilihan tidak valid!"; press_any_key; return
    fi
    local sname="${snames[$((schoice-1))]}"
    local domain; domain=$(cat /etc/zv-manager/domain 2>/dev/null)
    echo ""; echo -e "  ${BWHITE}Server :${NC} ${BYELLOW}${sname}${NC}"; echo ""

    read -rp "  Username [kosongkan = auto]: " username
    [[ -z "$username" ]] && username=$(_gen_zivpn_user) || username=$(echo "$username" | tr -dc 'a-zA-Z0-9-_')
    [[ -f "${ZIVPN_ACCT_DIR}/${username}.conf" ]] && { print_error "Username sudah digunakan!"; press_any_key; return; }

    read -rp "  Durasi (hari) [default: 30]: " exp_days
    exp_days="${exp_days:-30}"
    [[ ! "$exp_days" =~ ^[0-9]+$ || "$exp_days" -lt 1 ]] && { print_error "Durasi tidak valid!"; press_any_key; return; }

    local password; password=$(_gen_zivpn_pw)
    local now_ts; now_ts=$(date +%s)
    local exp_ts=$(( now_ts + exp_days * 86400 ))
    local exp_date; exp_date=$(date -d "@${exp_ts}" +"%Y-%m-%d")

    echo ""; print_info "Membuat akun ZiVPN di server ${sname}..."
    mkdir -p "$ZIVPN_ACCT_DIR"
    cat > "${ZIVPN_ACCT_DIR}/${username}.conf" << CONFEOF
USERNAME="${username}"
PASSWORD="${password}"
DOMAIN="${domain}"
EXPIRED_TS="${exp_ts}"
EXPIRED_DATE="${exp_date}"
CREATED="$(date +"%Y-%m-%d")"
IS_TRIAL="0"
TG_USER_ID="0"
SERVER="${sname}"
CONFEOF

    local result; result=$(remote_zivpn_agent "$sname" add "$username" "$password" "$exp_days" "0")
    if echo "$result" | grep -q "^ADD-OK"; then
        print_ok "Akun ZiVPN berhasil dibuat!"
    else
        print_warning "Agent: ${result}"; rm -f "${ZIVPN_ACCT_DIR}/${username}.conf"; press_any_key; return
    fi

    clear; _sep; _grad " AKUN ZIVPN BERHASIL DIBUAT" 0 210 255 160 80 255; _sep; echo ""
    echo -e "  ${BWHITE}Username  :${NC} ${BYELLOW}${username}${NC}"
    echo -e "  ${BWHITE}ZiVPN PW  :${NC} ${BYELLOW}${password}${NC}"
    echo -e "  ${BWHITE}Host      :${NC} ${BYELLOW}${domain}${NC}"
    echo -e "  ${BWHITE}Port UDP  :${NC} ${BYELLOW}5667${NC}"
    echo -e "  ${BWHITE}Obfs      :${NC} ${BYELLOW}zivpn${NC}"
    echo -e "  ${BWHITE}Server    :${NC} ${BYELLOW}${sname}${NC}"
    echo -e "  ${BWHITE}Expired   :${NC} ${BYELLOW}${exp_date}${NC} (${exp_days} hari)"
    echo ""; press_any_key
}
add_zivpn
