#!/bin/bash
# ============================================================
#   ZV-Manager - Add SSH User
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh

add_ssh_user() {
    clear
    local domain
    domain=$(cat /etc/zv-manager/domain 2>/dev/null)
    local ip
    ip=$(curl -s --max-time 5 ipv4.icanhazip.com 2>/dev/null)

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

    if user_exists "$username"; then
        print_error "Username '$username' sudah ada!"
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
    echo -e "  ${BWHITE}Host        :${NC} ${BGREEN}${domain}${NC}"
    echo -e "  ${BWHITE}OpenSSH     :${NC} ${BPURPLE}22${NC}"
    echo -e "  ${BWHITE}SSH-WS      :${NC} ${BPURPLE}80${NC}"
    echo -e "  ${BWHITE}SSH-WSS     :${NC} ${BPURPLE}443${NC}"
    echo -e "  ${BWHITE}Dropbear    :${NC} ${BPURPLE}109, 143${NC}"
    echo -e "  ${BWHITE}UDP Custom  :${NC} ${BPURPLE}1-65535${NC}"
    echo -e "${BCYAN} └─────────────────────────────────────────────┘${NC}"
    echo -e "${BCYAN} ┌─────────────────────────────────────────────┐${NC}"
    echo -e "  ${BWHITE}Payload WS/WSS:${NC}"
    echo -e "  ${BPURPLE}GET / HTTP/1.1[crlf]Host: ${domain}[crlf]"
    echo -e "  Upgrade: websocket[crlf][crlf]${NC}"
    echo -e "${BCYAN} └─────────────────────────────────────────────┘${NC}"
    echo ""

    press_any_key
}

add_ssh_user
