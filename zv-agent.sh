#!/bin/bash
# ============================================================
#   ZV-Agent - SSH User Management Agent
#   Diinstall di remote VPS: /usr/local/bin/zv-agent
#   Dipanggil dari otak VPS via SSH
#
#   Usage: zv-agent <command> [args...]
#
#   Commands:
#     ping                          → health check
#     add  <user> <pass> <limit> <days>
#     del  <user>
#     info <user>
#     edit <user> <field> <value>   field: pass | limit | expired
#     list
#     renew  <user> <days>
#     lock   <user>
#     unlock <user>
#     check  <user>
#     online
# ============================================================

ACCOUNT_DIR="/etc/zv-manager/accounts/ssh"
mkdir -p "$ACCOUNT_DIR"

# ---------- helpers internal ----------
_user_exists() { id "$1" &>/dev/null; }

_exp_date_from_days() {
    date -d "$1 days" +"%Y-%m-%d" 2>/dev/null
}

_exp_date_from_base() {
    # _exp_date_from_base <base_date> <+N>
    date -d "$1 +$2 days" +"%Y-%m-%d" 2>/dev/null
}

_today() { date +"%Y-%m-%d"; }

# ---------- command: ping ----------
cmd_ping() {
    echo "ZV-AGENT-OK"
}

# ---------- command: add ----------
cmd_add() {
    local user="$1" pass="$2" limit="$3" days="$4"

    [[ -z "$user" || -z "$pass" || -z "$days" ]] && {
        echo "ADD-ERR|Argumen tidak lengkap (user pass limit days)"; return 1
    }
    [[ -z "$limit" ]] && limit=2

    # Cek duplikat
    _user_exists "$user" && { echo "ADD-ERR|User '$user' sudah ada di sistem"; return 1; }
    [[ -f "${ACCOUNT_DIR}/${user}.conf" ]] && { echo "ADD-ERR|Data akun '$user' sudah ada"; return 1; }

    local exp_date
    exp_date=$(_exp_date_from_days "$days")
    [[ -z "$exp_date" ]] && { echo "ADD-ERR|Format hari tidak valid: $days"; return 1; }

    useradd -e "$exp_date" -s /bin/false -M "$user" &>/dev/null
    echo "$user:$pass" | chpasswd &>/dev/null

    cat > "${ACCOUNT_DIR}/${user}.conf" <<EOF
USERNAME=$user
PASSWORD=$pass
LIMIT=$limit
EXPIRED=$exp_date
CREATED=$(date +"%Y-%m-%d")
EOF

    echo "ADD-OK|${user}|${pass}|${limit}|${exp_date}"
}

# ---------- command: del ----------
cmd_del() {
    local user="$1"
    [[ -z "$user" ]] && { echo "DEL-ERR|Username wajib diisi"; return 1; }
    ! _user_exists "$user" && { echo "DEL-ERR|User '$user' tidak ditemukan"; return 1; }

    pkill -u "$user" &>/dev/null
    userdel -r "$user" &>/dev/null
    rm -f "${ACCOUNT_DIR}/${user}.conf"

    echo "DEL-OK|${user}"
}

# ---------- command: info ----------
cmd_info() {
    local user="$1"
    [[ -z "$user" ]] && { echo "INFO-ERR|Username wajib diisi"; return 1; }

    local conf="${ACCOUNT_DIR}/${user}.conf"
    [[ ! -f "$conf" ]] && { echo "INFO-ERR|Akun '$user' tidak ditemukan"; return 1; }

    unset USERNAME PASSWORD LIMIT EXPIRED CREATED
    source "$conf"
    echo "INFO-OK|${USERNAME}|${PASSWORD}|${LIMIT}|${EXPIRED}|${CREATED:-?}"
}

# ---------- command: edit ----------
# edit <user> pass   <newpass>
# edit <user> limit  <newlimit>
# edit <user> expired <newdate|+N|+N:exp>
cmd_edit() {
    local user="$1" field="$2" value="$3"

    [[ -z "$user" || -z "$field" || -z "$value" ]] && {
        echo "EDIT-ERR|Argumen tidak lengkap (user field value)"; return 1
    }

    local conf="${ACCOUNT_DIR}/${user}.conf"
    [[ ! -f "$conf" ]] && { echo "EDIT-ERR|Akun '$user' tidak ditemukan"; return 1; }

    unset USERNAME PASSWORD LIMIT EXPIRED CREATED
    source "$conf"

    case "$field" in
        pass)
            echo "$user:$value" | chpasswd &>/dev/null
            sed -i "s/^PASSWORD=.*/PASSWORD=${value}/" "$conf"
            echo "EDIT-OK|${user}|pass|${value}"
            ;;
        limit)
            [[ ! "$value" =~ ^[0-9]+$ ]] && { echo "EDIT-ERR|Limit harus angka"; return 1; }
            sed -i "s/^LIMIT=.*/LIMIT=${value}/" "$conf"
            echo "EDIT-OK|${user}|limit|${value}"
            ;;
        expired)
            local new_exp="$value"
            if [[ "$new_exp" =~ ^\+([0-9]+)$ ]]; then
                new_exp=$(date -d "+${BASH_REMATCH[1]} days" +"%Y-%m-%d")
            elif [[ "$new_exp" =~ ^\+([0-9]+):exp$ ]]; then
                new_exp=$(date -d "${EXPIRED} +${BASH_REMATCH[1]} days" +"%Y-%m-%d")
            fi
            date -d "$new_exp" +"%Y-%m-%d" &>/dev/null 2>&1 || {
                echo "EDIT-ERR|Format tanggal tidak valid: $value"; return 1
            }
            new_exp=$(date -d "$new_exp" +"%Y-%m-%d")
            chage -E "$new_exp" "$user" &>/dev/null
            sed -i "s/^EXPIRED=.*/EXPIRED=${new_exp}/" "$conf"
            echo "EDIT-OK|${user}|expired|${new_exp}"
            ;;
        *)
            echo "EDIT-ERR|Field tidak dikenal: $field (pass|limit|expired)"
            return 1
            ;;
    esac
}

# ---------- command: list ----------
# Output per baris: USERNAME|PASSWORD|LIMIT|EXPIRED|CREATED
cmd_list() {
    local count=0
    for conf in "${ACCOUNT_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue
        unset USERNAME PASSWORD LIMIT EXPIRED CREATED
        source "$conf"
        echo "${USERNAME}|${PASSWORD}|${LIMIT}|${EXPIRED}|${CREATED:-?}"
        count=$((count + 1))
    done
    [[ $count -eq 0 ]] && echo "LIST-EMPTY"
}

# ---------- command: renew ----------
cmd_renew() {
    local user="$1" days="$2"
    [[ -z "$user" || -z "$days" ]] && { echo "RENEW-ERR|Argumen tidak lengkap (user days)"; return 1; }

    local conf="${ACCOUNT_DIR}/${user}.conf"
    [[ ! -f "$conf" ]] && { echo "RENEW-ERR|Akun '$user' tidak ditemukan"; return 1; }

    local new_exp
    new_exp=$(_exp_date_from_days "$days")
    [[ -z "$new_exp" ]] && { echo "RENEW-ERR|Format hari tidak valid"; return 1; }

    chage -E "$new_exp" "$user" &>/dev/null
    sed -i "s/^EXPIRED=.*/EXPIRED=${new_exp}/" "$conf"

    echo "RENEW-OK|${user}|${new_exp}"
}

# ---------- command: lock ----------
cmd_lock() {
    local user="$1"
    [[ -z "$user" ]] && { echo "LOCK-ERR|Username wajib diisi"; return 1; }
    ! _user_exists "$user" && { echo "LOCK-ERR|User '$user' tidak ditemukan"; return 1; }

    passwd -l "$user" &>/dev/null
    pkill -u "$user" &>/dev/null
    echo "LOCK-OK|${user}"
}

# ---------- command: unlock ----------
cmd_unlock() {
    local user="$1"
    [[ -z "$user" ]] && { echo "UNLOCK-ERR|Username wajib diisi"; return 1; }
    ! _user_exists "$user" && { echo "UNLOCK-ERR|User '$user' tidak ditemukan"; return 1; }

    passwd -u "$user" &>/dev/null
    echo "UNLOCK-OK|${user}"
}

# ---------- command: check ----------
cmd_check() {
    local user="$1"
    [[ -z "$user" ]] && { echo "CHECK-ERR|Username wajib diisi"; return 1; }
    if _user_exists "$user" || [[ -f "${ACCOUNT_DIR}/${user}.conf" ]]; then
        echo "EXISTS|${user}"
    else
        echo "NOTFOUND|${user}"
    fi
}

# ---------- command: online ----------
# Output per user yang ada: USERNAME|<session_count>
cmd_online() {
    for conf in "${ACCOUNT_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue
        unset USERNAME
        source "$conf"
        local n_ssh n_drop
        n_ssh=$(ps aux | grep -E "sshd: ${USERNAME}(@|$)" | grep -v grep | grep -v '\[priv\]' | wc -l)
        n_drop=$(ps aux | grep -E "dropbear: ${USERNAME}(@|$)" | grep -v grep | wc -l)
        echo "${USERNAME}|$(( n_ssh + n_drop ))"
    done
}

# ============================================================
# Main dispatcher
# ============================================================
CMD="$1"
shift

case "$CMD" in
    ping)    cmd_ping    ;;
    add)     cmd_add     "$@" ;;
    del)     cmd_del     "$@" ;;
    info)    cmd_info    "$@" ;;
    edit)    cmd_edit    "$@" ;;
    list)    cmd_list    ;;
    renew)   cmd_renew   "$@" ;;
    lock)    cmd_lock    "$@" ;;
    unlock)  cmd_unlock  "$@" ;;
    check)   cmd_check   "$@" ;;
    online)  cmd_online  ;;
    *)
        echo "ZV-AGENT v1.0 — SSH User Management Agent"
        echo "Usage: zv-agent <command> [args]"
        echo ""
        echo "Commands:"
        echo "  ping"
        echo "  add  <user> <pass> <limit> <days>"
        echo "  del  <user>"
        echo "  info <user>"
        echo "  edit <user> <pass|limit|expired> <value>"
        echo "  list"
        echo "  renew  <user> <days>"
        echo "  lock   <user>"
        echo "  unlock <user>"
        echo "  check  <user>"
        echo "  online"
        exit 1
        ;;
esac
