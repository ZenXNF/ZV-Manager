#!/bin/bash
# ============================================================
#   ZV-Manager - Add SSH User
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh

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

    echo -e "${BCYAN} ┌─────────────────────────────────────────────┐${NC}"
    echo -e " │           ${BWHITE}TAMBAH AKUN SSH BARU${NC}              │"
    echo -e "${BCYAN} └─────────────────────────────────────────────┘${NC}"
    echo ""
    read -rp "  Username      : " username
    read -rp "  Password      : " password
    read -rp "  Limit Login   : " limit
    read -rp "  Expired (hari): " days
    echo ""

    if [[ -z "$username" || -z "$password" || -z "$days" ]]; then
        print_error "Semua field harus diisi!"
        press_any_key
        return
    fi

    if user_exists "$username"; then
        print_error "Username '$username' sudah ada di sistem Linux!"
        press_any_key
        return
    fi

    if [[ -f "/etc/zv-manager/accounts/ssh/${username}.conf" ]]; then
        print_error "Username '$username' sudah ada di data akun!"
        press_any_key
        return
    fi

    local exp_date
    exp_date=$(expired_date "$days")
    useradd -e "$exp_date" -s /bin/false -M "$username" &>/dev/null
    echo -e "$password\n$password" | passwd "$username" &>/dev/null

    mkdir -p /etc/zv-manager/accounts/ssh
    cat > "/etc/zv-manager/accounts/ssh/${username}.conf" <<EOF
USERNAME=$username
PASSWORD=$password
LIMIT=$limit
EXPIRED=$exp_date
CREATED=$(date +"%Y-%m-%d")
EOF

    local created_date
    created_date=$(date +"%d %b %Y")

    clear
    echo ""
    echo -e "  ${BYELLOW}✦ AKUN SSH BERHASIL DIBUAT ✦${NC}"
    echo ""
    echo -e "  ${BCYAN}┌─────────────────────────────────────────┐${NC}"
    echo -e "  ${BCYAN}│${NC}  ${BWHITE}Informasi Akun${NC}"
    echo -e "  ${BCYAN}├─────────────────────────────────────────┤${NC}"
    echo -e "  ${BCYAN}│${NC}  Host       : ${BGREEN}${host}${NC}"
    echo -e "  ${BCYAN}│${NC}  Username   : ${BGREEN}${username}${NC}"
    echo -e "  ${BCYAN}│${NC}  Password   : ${BGREEN}${password}${NC}"
    echo -e "  ${BCYAN}│${NC}  Limit      : ${BWHITE}${limit} perangkat${NC}"
    echo -e "  ${BCYAN}│${NC}  Dibuat     : ${BWHITE}${created_date}${NC}"
    echo -e "  ${BCYAN}│${NC}  Expired    : ${BYELLOW}${exp_date}${NC}"
    echo -e "  ${BCYAN}└─────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BCYAN}┌─────────────────────────────────────────┐${NC}"
    echo -e "  ${BCYAN}│${NC}  ${BWHITE}Port${NC}"
    echo -e "  ${BCYAN}├─────────────────────────────────────────┤${NC}"
    echo -e "  ${BCYAN}│${NC}  OpenSSH    : ${BPURPLE}22, 500, 40000${NC}"
    echo -e "  ${BCYAN}│${NC}  Dropbear   : ${BPURPLE}109, 143${NC}"
    echo -e "  ${BCYAN}│${NC}  SSH WS     : ${BPURPLE}80${NC}"
    echo -e "  ${BCYAN}│${NC}  SSH WSS    : ${BPURPLE}443${NC}"
    echo -e "  ${BCYAN}│${NC}  UDP Custom : ${BPURPLE}1-65535${NC}"
    echo -e "  ${BCYAN}└─────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BCYAN}┌─────────────────────────────────────────┐${NC}"
    echo -e "  ${BCYAN}│${NC}  ${BWHITE}Format HTTP Custom${NC}"
    echo -e "  ${BCYAN}├─────────────────────────────────────────┤${NC}"
    echo -e "  ${BCYAN}│${NC}  WS   : ${BGREEN}${host}:80@${username}:${password}${NC}"
    echo -e "  ${BCYAN}│${NC}  WSS  : ${BGREEN}${host}:443@${username}:${password}${NC}"
    echo -e "  ${BCYAN}│${NC}  UDP  : ${BGREEN}${host}:1-65535@${username}:${password}${NC}"
    echo -e "  ${BCYAN}└─────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BCYAN}┌─────────────────────────────────────────┐${NC}"
    echo -e "  ${BCYAN}│${NC}  ${BWHITE}Payload${NC}"
    echo -e "  ${BCYAN}├─────────────────────────────────────────┤${NC}"
    echo -e "  ${BCYAN}│${NC}  ${BWHITE}WS Non-SSL:${NC}"
    echo -e "  ${BCYAN}│${NC}    ${BPURPLE}GET / HTTP/1.1[crlf]Host: ${host}[crlf]${NC}"
    echo -e "  ${BCYAN}│${NC}    ${BPURPLE}Upgrade: websocket[crlf][crlf]${NC}"
    echo -e "  ${BCYAN}│${NC}"
    echo -e "  ${BCYAN}│${NC}  ${BWHITE}WS SSL (HTTP CONNECT):${NC}"
    echo -e "  ${BCYAN}│${NC}    ${BPURPLE}CONNECT ${host}:443 HTTP/1.0[crlf][crlf]${NC}"
    echo -e "  ${BCYAN}└─────────────────────────────────────────┘${NC}"
    echo ""

    press_any_key
}

add_ssh_user
