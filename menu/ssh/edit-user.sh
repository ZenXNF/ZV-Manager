#!/bin/bash
# ============================================================
#   ZV-Manager - Edit Akun SSH
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh

ACCOUNT_DIR="/etc/zv-manager/accounts/ssh"

# Pilih user dari list
pick_user() {
    local files=("${ACCOUNT_DIR}"/*.conf)
    if [[ ! -f "${files[0]}" ]]; then
        print_error "Belum ada akun SSH yang dibuat."
        sleep 2
        return 1
    fi

    clear
    echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
    echo -e " │            ${BWHITE}EDIT AKUN SSH${NC}                      │"
    echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BWHITE}Daftar akun:${NC}"
    echo ""

    local i=1
    local userlist=()
    for f in "${ACCOUNT_DIR}"/*.conf; do
        [[ -f "$f" ]] || continue
        local uname
        uname=$(grep "^USERNAME=" "$f" | cut -d= -f2)
        userlist+=("$uname")
        echo -e "  ${BGREEN}[$i]${NC} $uname"
        (( i++ ))
    done

    echo ""
    echo -e "  ${BRED}[0]${NC} Batal"
    echo ""
    read -rp "  Pilih nomor akun: " idx

    [[ "$idx" == "0" ]] && return 1
    [[ -z "$idx" || ! "$idx" =~ ^[0-9]+$ ]] && print_error "Input tidak valid." && sleep 1 && return 1

    local selected="${userlist[$((idx-1))]}"
    if [[ -z "$selected" ]]; then
        print_error "Nomor tidak valid."
        sleep 1
        return 1
    fi

    echo "$selected"
    return 0
}

# Tampil info akun sekarang
show_current_info() {
    local username="$1"
    local conf="${ACCOUNT_DIR}/${username}.conf"

    source "$conf"
    local today
    today=$(date +"%Y-%m-%d")
    local status_exp
    if [[ "$EXPIRED" < "$today" ]]; then
        status_exp="${BRED}Expired${NC}"
    else
        status_exp="${BGREEN}Aktif${NC}"
    fi

    echo ""
    echo -e "${BCYAN}  ──────────────────────────────────────────────${NC}"
    echo -e "  ${BWHITE}Akun     :${NC} ${BYELLOW}${USERNAME}${NC}"
    echo -e "  ${BWHITE}Password :${NC} ${PASSWORD}"
    echo -e "  ${BWHITE}Limit    :${NC} ${LIMIT} perangkat"
    echo -e "  ${BWHITE}Expired  :${NC} ${EXPIRED} ($(printf "%b" "$status_exp"))"
    echo -e "  ${BWHITE}Dibuat   :${NC} ${CREATED}"
    echo -e "${BCYAN}  ──────────────────────────────────────────────${NC}"
    echo ""
}

# Edit password
edit_password() {
    local username="$1"
    local conf="${ACCOUNT_DIR}/${username}.conf"
    source "$conf"

    echo -e "  ${BWHITE}Password sekarang :${NC} ${PASSWORD}"
    read -rp "  Password baru     : " new_pass
    [[ -z "$new_pass" ]] && print_error "Password tidak boleh kosong." && sleep 1 && return 1

    # Update sistem
    echo "${username}:${new_pass}" | chpasswd &>/dev/null

    # Update conf
    sed -i "s/^PASSWORD=.*/PASSWORD=${new_pass}/" "$conf"

    print_ok "Password berhasil diubah!"
    return 0
}

# Edit limit
edit_limit() {
    local username="$1"
    local conf="${ACCOUNT_DIR}/${username}.conf"
    source "$conf"

    echo -e "  ${BWHITE}Limit sekarang :${NC} ${LIMIT} perangkat"
    read -rp "  Limit baru     : " new_limit
    [[ -z "$new_limit" || ! "$new_limit" =~ ^[0-9]+$ || "$new_limit" -lt 1 ]] && \
        print_error "Limit tidak valid. Masukkan angka >= 1." && sleep 1 && return 1

    sed -i "s/^LIMIT=.*/LIMIT=${new_limit}/" "$conf"

    print_ok "Limit berhasil diubah ke ${new_limit} perangkat!"
    return 0
}

# Edit expired
edit_expired() {
    local username="$1"
    local conf="${ACCOUNT_DIR}/${username}.conf"
    source "$conf"

    echo -e "  ${BWHITE}Expired sekarang :${NC} ${EXPIRED}"
    read -rp "  Expired baru (YYYY-MM-DD atau +Nhari): " new_exp

    # Support format +7 (tambah 7 hari dari sekarang) atau +7:expired (tambah dari expired)
    if [[ "$new_exp" =~ ^\+([0-9]+)$ ]]; then
        new_exp=$(date -d "+${BASH_REMATCH[1]} days" +"%Y-%m-%d")
    elif [[ "$new_exp" =~ ^\+([0-9]+):exp$ ]]; then
        new_exp=$(date -d "${EXPIRED} +${BASH_REMATCH[1]} days" +"%Y-%m-%d")
    fi

    # Validasi format YYYY-MM-DD
    if ! date -d "$new_exp" +"%Y-%m-%d" &>/dev/null; then
        print_error "Format tanggal tidak valid. Gunakan YYYY-MM-DD atau +N (hari dari sekarang)."
        sleep 2
        return 1
    fi

    new_exp=$(date -d "$new_exp" +"%Y-%m-%d")
    sed -i "s/^EXPIRED=.*/EXPIRED=${new_exp}/" "$conf"

    print_ok "Expired berhasil diubah ke ${new_exp}!"
    return 0
}

# Edit semua sekaligus
edit_all() {
    local username="$1"
    local conf="${ACCOUNT_DIR}/${username}.conf"
    source "$conf"

    echo -e "  ${BYELLOW}Kosongkan field untuk tidak mengubahnya.${NC}"
    echo ""

    read -rp "  Password baru   [${PASSWORD}]: " new_pass
    read -rp "  Limit baru      [${LIMIT}]  : " new_limit
    read -rp "  Expired baru    [${EXPIRED}]: " new_exp

    local changed=false

    # Password
    if [[ -n "$new_pass" ]]; then
        echo "${username}:${new_pass}" | chpasswd &>/dev/null
        sed -i "s/^PASSWORD=.*/PASSWORD=${new_pass}/" "$conf"
        changed=true
    fi

    # Limit
    if [[ -n "$new_limit" ]]; then
        if [[ ! "$new_limit" =~ ^[0-9]+$ || "$new_limit" -lt 1 ]]; then
            print_error "Limit tidak valid, dilewati."
        else
            sed -i "s/^LIMIT=.*/LIMIT=${new_limit}/" "$conf"
            changed=true
        fi
    fi

    # Expired
    if [[ -n "$new_exp" ]]; then
        if [[ "$new_exp" =~ ^\+([0-9]+)$ ]]; then
            new_exp=$(date -d "+${BASH_REMATCH[1]} days" +"%Y-%m-%d")
        elif [[ "$new_exp" =~ ^\+([0-9]+):exp$ ]]; then
            new_exp=$(date -d "${EXPIRED} +${BASH_REMATCH[1]} days" +"%Y-%m-%d")
        fi

        if ! date -d "$new_exp" +"%Y-%m-%d" &>/dev/null; then
            print_error "Format expired tidak valid, dilewati."
        else
            new_exp=$(date -d "$new_exp" +"%Y-%m-%d")
            sed -i "s/^EXPIRED=.*/EXPIRED=${new_exp}/" "$conf"
            changed=true
        fi
    fi

    if [[ "$changed" == true ]]; then
        print_ok "Akun ${username} berhasil diperbarui!"
    else
        print_info "Tidak ada yang diubah."
    fi
    return 0
}

edit_user_menu() {
    local username
    username=$(pick_user) || return

    while true; do
        clear
        echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
        echo -e " │            ${BWHITE}EDIT AKUN SSH${NC}                      │"
        echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"

        show_current_info "$username"

        echo -e "  ${BGREEN}[1]${NC} Ubah Password"
        echo -e "  ${BGREEN}[2]${NC} Ubah Limit"
        echo -e "  ${BGREEN}[3]${NC} Ubah Expired"
        echo -e "  ${BGREEN}[4]${NC} Ubah Semua Sekaligus"
        echo ""
        echo -e "  ${BRED}[0]${NC} Kembali"
        echo ""
        read -rp "  Pilihan: " choice

        case "$choice" in
            1) edit_password "$username" && sleep 1 ;;
            2) edit_limit "$username" && sleep 1 ;;
            3) edit_expired "$username" && sleep 1 ;;
            4) edit_all "$username" && sleep 1 ;;
            0) break ;;
            *) print_error "Pilihan tidak valid." ; sleep 1 ;;
        esac
    done
}

edit_user_menu
