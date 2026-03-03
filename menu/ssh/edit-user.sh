#!/bin/bash
# ============================================================
#   ZV-Manager - Edit Akun SSH (Local + Remote)
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/utils/remote.sh

ACCOUNT_DIR="/etc/zv-manager/accounts/ssh"
SELECTED_USER=""

# ============================================================
# LOCAL: pick user dari file lokal
# ============================================================
pick_user_local() {
    SELECTED_USER=""
    local files=("${ACCOUNT_DIR}"/*.conf)
    if [[ ! -f "${files[0]}" ]]; then
        print_error "Belum ada akun SSH yang dibuat."
        sleep 2
        return 1
    fi

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

    SELECTED_USER="$selected"
    return 0
}

# ============================================================
# REMOTE: pick user dari list remote
# ============================================================
pick_user_remote() {
    local target="$1"
    SELECTED_USER=""

    print_info "Mengambil daftar akun dari $(target_display)..."
    local raw
    raw=$(remote_agent "$target" "list")

    if [[ "$raw" == REMOTE-ERR* ]]; then
        print_error "${raw#REMOTE-ERR|}"
        sleep 2
        return 1
    fi

    if [[ "$raw" == "LIST-EMPTY" || -z "$raw" ]]; then
        print_error "Belum ada akun SSH di server remote."
        sleep 2
        return 1
    fi

    echo ""
    echo -e "  ${BWHITE}Daftar akun:${NC}"
    echo ""

    local i=1
    local -a userlist=()
    local today
    today=$(date +"%Y-%m-%d")

    while IFS='|' read -r r_user r_pass r_limit r_exp r_created; do
        [[ -z "$r_user" ]] && continue
        local status_label
        [[ "$r_exp" < "$today" ]] && status_label="${BRED}Expired${NC}" || status_label="${BGREEN}Aktif${NC}"
        printf "  ${BGREEN}[%s]${NC} %-16s Exp: %-12s " "$i" "$r_user" "$r_exp"
        echo -e "$status_label"
        userlist+=("$r_user")
        (( i++ ))
    done <<< "$raw"

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

    SELECTED_USER="$selected"
    return 0
}

# ============================================================
# Show current info (local)
# ============================================================
show_current_info_local() {
    local username="$1"
    local conf="${ACCOUNT_DIR}/${username}.conf"

    unset USERNAME PASSWORD LIMIT EXPIRED CREATED
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

# ============================================================
# Show current info (remote via zv-agent info)
# ============================================================
show_current_info_remote() {
    local username="$1" target="$2"
    local result
    result=$(remote_agent "$target" "info" "$username")

    if [[ "$result" != INFO-OK* ]]; then
        echo -e "  ${BYELLOW}(Tidak bisa ambil detail akun)${NC}"
        echo ""
        return
    fi

    IFS='|' read -r _ r_user r_pass r_limit r_exp r_created <<< "$result"
    local today
    today=$(date +"%Y-%m-%d")
    local status_exp
    [[ "$r_exp" < "$today" ]] && status_exp="${BRED}Expired${NC}" || status_exp="${BGREEN}Aktif${NC}"

    echo ""
    echo -e "${BCYAN}  ──────────────────────────────────────────────${NC}"
    echo -e "  ${BWHITE}Akun     :${NC} ${BYELLOW}${r_user}${NC}"
    echo -e "  ${BWHITE}Password :${NC} ${r_pass}"
    echo -e "  ${BWHITE}Limit    :${NC} ${r_limit} perangkat"
    echo -e "  ${BWHITE}Expired  :${NC} ${r_exp} ($(printf "%b" "$status_exp"))"
    echo -e "  ${BWHITE}Dibuat   :${NC} ${r_created}"
    echo -e "${BCYAN}  ──────────────────────────────────────────────${NC}"
    echo ""
}

# ============================================================
# Edit helpers — Local
# ============================================================
edit_password_local() {
    local username="$1"
    local conf="${ACCOUNT_DIR}/${username}.conf"
    source "$conf"
    echo -e "  ${BWHITE}Password sekarang :${NC} ${PASSWORD}"
    read -rp "  Password baru     : " new_pass
    [[ -z "$new_pass" ]] && print_error "Password tidak boleh kosong." && sleep 1 && return 1
    echo "${username}:${new_pass}" | chpasswd &>/dev/null
    sed -i "s/^PASSWORD=.*/PASSWORD=${new_pass}/" "$conf"
    print_ok "Password berhasil diubah!"
}

edit_limit_local() {
    local username="$1"
    local conf="${ACCOUNT_DIR}/${username}.conf"
    source "$conf"
    echo -e "  ${BWHITE}Limit sekarang :${NC} ${LIMIT} perangkat"
    read -rp "  Limit baru     : " new_limit
    if [[ -z "$new_limit" || ! "$new_limit" =~ ^[0-9]+$ || "$new_limit" -lt 1 ]]; then
        print_error "Limit tidak valid."
        sleep 1
        return 1
    fi
    sed -i "s/^LIMIT=.*/LIMIT=${new_limit}/" "$conf"
    print_ok "Limit berhasil diubah ke ${new_limit} perangkat!"
}

edit_expired_local() {
    local username="$1"
    local conf="${ACCOUNT_DIR}/${username}.conf"
    source "$conf"
    echo -e "  ${BWHITE}Expired sekarang :${NC} ${EXPIRED}"
    echo -e "  ${BYELLOW}Format: YYYY-MM-DD | +N (dari hari ini) | +N:exp (dari expired)${NC}"
    read -rp "  Expired baru     : " new_exp
    if [[ "$new_exp" =~ ^\+([0-9]+)$ ]]; then
        new_exp=$(date -d "+${BASH_REMATCH[1]} days" +"%Y-%m-%d")
    elif [[ "$new_exp" =~ ^\+([0-9]+):exp$ ]]; then
        new_exp=$(date -d "${EXPIRED} +${BASH_REMATCH[1]} days" +"%Y-%m-%d")
    fi
    if ! date -d "$new_exp" +"%Y-%m-%d" &>/dev/null 2>&1; then
        print_error "Format tanggal tidak valid."
        sleep 2
        return 1
    fi
    new_exp=$(date -d "$new_exp" +"%Y-%m-%d")
    chage -E "$new_exp" "$username" &>/dev/null
    sed -i "s/^EXPIRED=.*/EXPIRED=${new_exp}/" "$conf"
    print_ok "Expired berhasil diubah ke ${new_exp}!"
}

# ============================================================
# Edit helpers — Remote (via zv-agent edit)
# ============================================================
edit_field_remote() {
    local username="$1" field="$2" value="$3" target="$4"
    local result
    result=$(remote_agent "$target" "edit" "$username" "$field" "$value")

    if [[ "$result" == EDIT-OK* ]]; then
        IFS='|' read -r _ _ r_field r_val <<< "$result"
        print_ok "Field '${r_field}' berhasil diubah ke: ${r_val}"
    elif [[ "$result" == EDIT-ERR* ]]; then
        print_error "Gagal: ${result#EDIT-ERR|}"
    elif [[ "$result" == REMOTE-ERR* ]]; then
        print_error "${result#REMOTE-ERR|}"
    else
        print_error "Response tidak dikenal: ${result}"
    fi
}

# ============================================================
# Edit menu loop
# ============================================================
edit_user_menu() {
    local target
    target=$(get_target_server)
    local target_info
    target_info=$(target_display)

    clear
    echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
    echo -e " │            ${BWHITE}EDIT AKUN SSH${NC}                      │"
    echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BWHITE}Target :${NC} ${BGREEN}${target_info}${NC}"
    echo ""

    # Pick user
    if is_local_target; then
        pick_user_local || return
    else
        pick_user_remote "$target" || return
    fi

    local username="$SELECTED_USER"

    while true; do
        clear
        echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
        echo -e " │            ${BWHITE}EDIT AKUN SSH${NC}                      │"
        echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
        echo -e "  ${BWHITE}Target :${NC} ${BGREEN}${target_info}${NC}"

        if is_local_target; then
            show_current_info_local "$username"
        else
            show_current_info_remote "$username" "$target"
        fi

        echo -e "  ${BGREEN}[1]${NC} Ubah Password"
        echo -e "  ${BGREEN}[2]${NC} Ubah Limit"
        echo -e "  ${BGREEN}[3]${NC} Ubah Expired"
        echo ""
        echo -e "  ${BRED}[0]${NC} Kembali"
        echo ""
        read -rp "  Pilihan: " choice

        case "$choice" in
            1)
                if is_local_target; then
                    edit_password_local "$username"
                else
                    read -rp "  Password baru: " new_val
                    [[ -n "$new_val" ]] && edit_field_remote "$username" "pass" "$new_val" "$target"
                fi
                sleep 1
                ;;
            2)
                if is_local_target; then
                    edit_limit_local "$username"
                else
                    read -rp "  Limit baru: " new_val
                    [[ -n "$new_val" ]] && edit_field_remote "$username" "limit" "$new_val" "$target"
                fi
                sleep 1
                ;;
            3)
                if is_local_target; then
                    edit_expired_local "$username"
                else
                    echo -e "  ${BYELLOW}Format: YYYY-MM-DD | +N (dari hari ini) | +N:exp (dari expired)${NC}"
                    read -rp "  Expired baru: " new_val
                    [[ -n "$new_val" ]] && edit_field_remote "$username" "expired" "$new_val" "$target"
                fi
                sleep 1
                ;;
            0) break ;;
            *) print_error "Pilihan tidak valid." ; sleep 1 ;;
        esac
    done
}

edit_user_menu
