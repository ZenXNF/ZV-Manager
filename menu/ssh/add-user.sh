#!/bin/bash
# ============================================================
#   ZV-Manager - Add SSH User
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh

# Cari domain yang terdaftar untuk VPS lokal ini
# Logic: cari di servers/*.conf mana yang IP-nya cocok dengan IP lokal
# Kalau ketemu → pakai domainnya, kalau tidak → fallback ke IP
get_local_domain() {
    local local_ip
    local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null)
    [[ -z "$local_ip" ]] && local_ip=$(curl -s --max-time 5 ipv4.icanhazip.com 2>/dev/null)

    local found_domain=""
    for conf in /etc/zv-manager/servers/*.conf; do
        [[ -f "$conf" ]] || continue
        unset IP DOMAIN
        source "$conf"
        if [[ "$IP" == "$local_ip" && -n "$DOMAIN" && "$DOMAIN" != "$local_ip" ]]; then
            found_domain="$DOMAIN"
            break
        fi
    done

    echo "${found_domain:-$local_ip}"
}

add_ssh_user() {
    clear
    local host
    host=$(get_local_domain)
    local ip
    ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null || curl -s --max-time 5 ipv4.icanhazip.com 2>/dev/null)

    echo -e "${BCYAN} ┌─────────────────────────────────────────────┐${NC}"
    echo -e " │           ${BWHITE}TAMBAH AKUN SSH BARU${NC}              │"
    echo -e "${BCYAN} └─────────────────────────────────────────────┘${NC}"
    echo ""
    read -rp "  Username     : " username
    read -rp "  Password     : " password
    read -rp "  Limit Login  : " limit
    read -rp "  Expired (hari): " days
    echo ""

    # Validasi input
    if [[ -z "$username" || -z "$password" || -z "$days" ]]; then
        print_error "Semua field harus diisi!"
        press_any_key
        return
    fi

    # Cek duplicate: Linux user
    if user_exists "$username"; then
        print_error "Username '$username' sudah ada di sistem Linux!"
        press_any_key
        return
    fi

    # Cek duplicate: file conf (bisa terjadi jika user dihapus manual dari sistem)
    if [[ -f "/etc/zv-manager/accounts/ssh/${username}.conf" ]]; then
        print_error "Username '$username' sudah ada di data akun!"
        press_any_key
        return
    fi

    # Buat user Linux
    local exp_date
    exp_date=$(expired_date "$days")
    useradd -e "$exp_date" -s /bin/false -M "$username" &>/dev/null
    echo -e "$password\n$password" | passwd "$username" &>/dev/null

    # Simpan data akun
    mkdir -p /etc/zv-manager/accounts/ssh
    cat > "/etc/zv-manager/accounts/ssh/${username}.conf" <<EOF
USERNAME=$username
PASSWORD=$password
LIMIT=$limit
EXPIRED=$exp_date
CREATED=$(date +"%Y-%m-%d")
EOF

    # Tampilkan info akun
    clear
    echo -e "${BCYAN} ┌─────────────────────────────────────────────┐${NC}"
    echo -e " │            ${BWHITE}INFORMASI AKUN SSH${NC}               │"
    echo -e "${BCYAN} └─────────────────────────────────────────────┘${NC}"
    echo -e "${BCYAN} ┌─────────────────────────────────────────────┐${NC}"
    echo -e "  ${BWHITE}Username    :${NC} ${BGREEN}${username}${NC}"
    echo -e "  ${BWHITE}Password    :${NC} ${BGREEN}${password}${NC}"
    echo -e "  ${BWHITE}Limit Login :${NC} ${BGREEN}${limit}${NC}"
    echo -e "  ${BWHITE}Expired     :${NC} ${BYELLOW}${exp_date}${NC}"
    echo -e "${BCYAN} └─────────────────────────────────────────────┘${NC}"
    echo -e "${BCYAN} ┌─────────────────────────────────────────────┐${NC}"
    echo -e "  ${BWHITE}IP VPS      :${NC} ${BGREEN}${ip}${NC}"
    echo -e "  ${BWHITE}Host        :${NC} ${BGREEN}${host}${NC}"
    echo -e "  ${BWHITE}OpenSSH     :${NC} ${BPURPLE}22${NC}"
    echo -e "  ${BWHITE}SSH-WS      :${NC} ${BPURPLE}80${NC}"
    echo -e "  ${BWHITE}SSH-WSS     :${NC} ${BPURPLE}443${NC}"
    echo -e "  ${BWHITE}Dropbear    :${NC} ${BPURPLE}109, 143${NC}"
    echo -e "  ${BWHITE}UDP Custom  :${NC} ${BPURPLE}1-65535${NC}"
    echo -e "${BCYAN} └─────────────────────────────────────────────┘${NC}"
    echo -e "${BCYAN} ┌─────────────────────────────────────────────┐${NC}"
    echo -e "  ${BWHITE}Payload WS/WSS:${NC}"
    echo -e "  ${BPURPLE}GET / HTTP/1.1[crlf]Host: ${host}[crlf]"
    echo -e "  Upgrade: websocket[crlf][crlf]${NC}"
    echo -e "${BCYAN} └─────────────────────────────────────────────┘${NC}"
    echo -e "${BCYAN} ┌─────────────────────────────────────────────┐${NC}"
    echo -e " │            ${BWHITE}STATUS SERVICE${NC}                    │"
    echo -e "${BCYAN} └─────────────────────────────────────────────┘${NC}"
    for svc in ssh dropbear nginx zv-wss zv-udp; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            echo -e "  ${BGREEN}●${NC} ${svc}: ${BGREEN}Aktif${NC}"
        else
            echo -e "  ${BRED}●${NC} ${svc}: ${BRED}Mati${NC}"
        fi
    done
    echo -e "${BCYAN} └─────────────────────────────────────────────┘${NC}"
    echo ""

    press_any_key
}

add_ssh_user
