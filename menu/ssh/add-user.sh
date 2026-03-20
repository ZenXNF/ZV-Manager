#!/bin/bash
# ============================================================
#   ZV-Manager - Add SSH User (Local + Remote)
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/utils/remote.sh

# Ambil domain untuk server lokal
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

# Ambil domain untuk server target
get_target_domain() {
    local target="$1"
    if [[ "$target" == "local" || -z "$target" ]]; then
        get_local_domain
        return
    fi
    local conf="/etc/zv-manager/servers/${target}.conf"
    if [[ -f "$conf" ]]; then
        unset DOMAIN IP
        source "$conf"
        echo "${DOMAIN:-$IP}"
    fi
}

add_ssh_user() {
    local target
    target=$(get_target_server)
    local target_info
    target_info=$(target_display)

    clear
    _sep
    _grad " TAMBAH AKUN SSH BARU" 255 0 127 0 210 255
    _sep
    echo ""
    echo -e "  ${BWHITE}Target :${NC} ${BGREEN}${target_info}${NC}"
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

    [[ -z "$limit" ]] && limit=2

    # ============================================================
    # LOCAL
    # ============================================================
    if is_local_target; then
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

        local exp_date exp_ts
        exp_date=$(expired_date "$days")
        exp_ts=$(date -d "${exp_date}" +%s 2>/dev/null || echo "")
        useradd -e "$exp_date" -s /bin/false -M "$username" &>/dev/null
        echo -e "$password\n$password" | passwd "$username" &>/dev/null

        # Cari nama server lokal dari conf
        local local_ip local_server_name
        local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null)
        local_server_name=""
        for _sc in /etc/zv-manager/servers/*.conf; do
            [[ -f "$_sc" && "$_sc" != *.tg.conf ]] || continue
            unset NAME IP; source "$_sc"
            [[ "$IP" == "$local_ip" ]] && { local_server_name="$NAME"; break; }
        done

        mkdir -p /etc/zv-manager/accounts/ssh
        cat > "/etc/zv-manager/accounts/ssh/${username}.conf" <<EOF
USERNAME=$username
PASSWORD=$password
LIMIT=$limit
EXPIRED=$exp_date
EXPIRED_TS=${exp_ts}
CREATED=$(date +"%Y-%m-%d")
IS_TRIAL=0
SERVER=${local_server_name}
DOMAIN=$(get_local_domain)
EOF
        _show_account_info "$username" "$password" "$limit" "$exp_date" "$(get_local_domain)"

    # ============================================================
    # REMOTE
    # ============================================================
    else
        print_info "Membuat akun di ${target_info}..."
        echo ""

        local result
        result=$(remote_agent "$target" "add" "$username" "$password" "$limit" "$days")

        if [[ "$result" == ADD-OK* ]]; then
            IFS='|' read -r _ r_user r_pass r_limit r_exp <<< "$result"
            print_ok "Akun berhasil dibuat di ${target_info}!"
            echo ""
            local domain
            domain=$(get_target_domain "$target")
            # Simpan conf lokal di otak (untuk notif expired, backup, dll)
            local r_exp_ts; r_exp_ts=$(date -d "$r_exp" +%s 2>/dev/null || echo "")
            mkdir -p /etc/zv-manager/accounts/ssh
            cat > "/etc/zv-manager/accounts/ssh/${r_user}.conf" <<CONFEOF
USERNAME=${r_user}
PASSWORD=${r_pass}
LIMIT=${r_limit}
EXPIRED=${r_exp}
EXPIRED_TS=${r_exp_ts}
CREATED=$(date +"%Y-%m-%d")
IS_TRIAL=0
SERVER=${target}
DOMAIN=${domain}
CONFEOF
            _show_account_info "$r_user" "$r_pass" "$r_limit" "$r_exp" "$domain"
        elif [[ "$result" == ADD-ERR* ]]; then
            local reason="${result#ADD-ERR|}"
            print_error "Gagal: ${reason}"
            press_any_key
        elif [[ "$result" == REMOTE-ERR* ]]; then
            local reason="${result#REMOTE-ERR|}"
            print_error "${reason}"
            press_any_key
        else
            print_error "Response tidak dikenal: ${result}"
            press_any_key
        fi
    fi
}

_show_account_info() {
    local username="$1" password="$2" limit="$3" exp_date="$4" host="$5"
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
