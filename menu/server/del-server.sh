#!/bin/bash
# ============================================================
#   ZV-Manager - Hapus Server
#   - Pilihan backup dulu atau hapus langsung
#   - Hapus semua akun SSH+VMess terkait server
#   - Notif ke user Telegram bahwa akun dihapus
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/core/telegram.sh
tg_load 2>/dev/null || true

SERVER_DIR="/etc/zv-manager/servers"
ACCOUNT_SSH="/etc/zv-manager/accounts/ssh"
ACCOUNT_VMESS="/etc/zv-manager/accounts/vmess"
NOTIFIED_DIR="/etc/zv-manager/accounts/notified"
BACKUP_DIR="/var/backups/zv-manager"
BASE_DIR="/etc/zv-manager"

_tg_send() {
    local chat_id="$1" text="$2"
    [[ -z "$TG_TOKEN" || -z "$chat_id" ]] && return
    printf '%b' "$text" | curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -F "chat_id=${chat_id}" \
        -F "parse_mode=HTML" \
        -F "text=<-" --max-time 10 &>/dev/null
}

_tg_file() {
    local file="$1" caption="$2"
    [[ -z "$TG_TOKEN" || -z "$TG_ADMIN_ID" || ! -f "$file" ]] && return
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendDocument" \
        -F "chat_id=${TG_ADMIN_ID}" \
        -F "document=@${file}" \
        -F "caption=${caption}" \
        -F "parse_mode=HTML" \
        --max-time 60 &>/dev/null
}

_fmt_size() {
    local f="$1"
    [[ ! -f "$f" ]] && echo "?" && return
    local s; s=$(stat -c%s "$f" 2>/dev/null || echo 0)
    if   (( s >= 1048576 )); then printf "%.1f MB" "$(echo "scale=1; $s/1048576" | bc)"
    elif (( s >= 1024    )); then printf "%.1f KB" "$(echo "scale=1; $s/1024"    | bc)"
    else echo "${s} B"; fi
}

# Backup server sebelum dihapus
_backup_server() {
    local sname="$1"
    local DATE; DATE=$(date +"%Y-%m-%d_%H-%M")
    local TMP_DIR; TMP_DIR=$(mktemp -d)
    local dst="${TMP_DIR}/srv-${sname}"
    mkdir -p "${dst}/ssh-accounts" "${dst}/vmess-accounts"

    # Conf server
    cp "${SERVER_DIR}/${sname}.conf"    "${dst}/" 2>/dev/null
    cp "${SERVER_DIR}/${sname}.tg.conf" "${dst}/" 2>/dev/null

    # Akun SSH terkait
    local ssh_count=0
    for ac in "${ACCOUNT_SSH}"/*.conf; do
        [[ -f "$ac" ]] || continue
        local srv; srv=$(grep "^SERVER=" "$ac" | cut -d= -f2 | tr -d '"' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ "$srv" == "$sname" ]] || continue
        cp "$ac" "${dst}/ssh-accounts/"
        ssh_count=$((ssh_count + 1))
    done

    # Akun VMess terkait
    local vmess_count=0
    for vc in "${ACCOUNT_VMESS}"/*.conf; do
        [[ -f "$vc" ]] || continue
        local srv; srv=$(grep "^SERVER=" "$vc" | cut -d= -f2 | tr -d '"' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ "$srv" == "$sname" ]] || continue
        cp "$vc" "${dst}/vmess-accounts/"
        vmess_count=$((vmess_count + 1))
    done

    # Catatan restore
    local backup_date; backup_date=$(TZ="Asia/Jakarta" date +"%Y-%m-%d %H:%M WIB")
    cat > "${dst}/RESTORE-NOTE.txt" << NOTETXT
============================
  BACKUP SERVER (PRE-DELETE)
============================
Server  : ${sname}
Dibackup: ${backup_date}
SSH     : ${ssh_count} akun
VMess   : ${vmess_count} akun

Backup ini dibuat otomatis sebelum server dihapus dari ZV-Manager.
NOTETXT

    # Compress
    mkdir -p "$BACKUP_DIR"
    local OUT_FILE="${BACKUP_DIR}/zv-ssh-${sname}-${DATE}.zvbak"
    tar -czf "$OUT_FILE" -C "$TMP_DIR" "srv-${sname}" 2>/dev/null
    rm -rf "$TMP_DIR"

    local SIZE; SIZE=$(_fmt_size "$OUT_FILE")

    # Kirim ke Telegram admin
    _tg_file "$OUT_FILE" "🗑 <b>Backup Pre-Delete: ${sname}</b>
━━━━━━━━━━━━━━━━━━━
📅 ${backup_date}
📦 Ukuran   : ${SIZE}
🔑 Akun SSH : ${ssh_count}
⚡ Akun VMess: ${vmess_count}
━━━━━━━━━━━━━━━━━━━
<i>Backup ini dibuat sebelum server dihapus.</i>"

    echo "$OUT_FILE"
}

# Hapus semua akun terkait server + notif user
_hapus_akun_server() {
    local sname="$1"
    local now_wib; now_wib=$(TZ="Asia/Jakarta" date +"%Y-%m-%d %H:%M WIB")
    local count_ssh=0 count_vmess=0

    # Hapus akun SSH
    for ac in "${ACCOUNT_SSH}"/*.conf; do
        [[ -f "$ac" ]] || continue
        local srv; srv=$(grep "^SERVER=" "$ac" | cut -d= -f2 | tr -d '"' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ "$srv" == "$sname" ]] || continue
        local uname; uname=$(grep "^USERNAME=" "$ac" | cut -d= -f2 | tr -d '"' | tr -d '[:space:]')
        local tg_uid; tg_uid=$(grep "^TG_USER_ID=" "$ac" | cut -d= -f2 | tr -d '"' | tr -d '[:space:]')
        # Notif ke user
        if [[ -n "$tg_uid" && "$tg_uid" != "0" ]]; then
            _tg_send "$tg_uid" "🔧 <b>Informasi Akun SSH</b>

Halo! Kami ingin memberitahu bahwa server <b>${sname}</b> sedang dalam proses pergantian.

👤 Username : <code>${uname}</code>
🌐 Server   : ${sname}

Tenang, data kamu <b>aman</b> dan sudah kami backup. 😊
Silakan hubungi admin untuk info lebih lanjut atau membuat akun di server baru."
        fi
        # Hapus file terkait
        rm -f "$ac"
        rm -f "${NOTIFIED_DIR}/${uname}.notified"
        rm -f "${NOTIFIED_DIR}/${uname}.bw_warn"
        count_ssh=$((count_ssh + 1))
    done

    # Hapus akun VMess
    for vc in "${ACCOUNT_VMESS}"/*.conf; do
        [[ -f "$vc" ]] || continue
        local srv; srv=$(grep "^SERVER=" "$vc" | cut -d= -f2 | tr -d '"' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ "$srv" == "$sname" ]] || continue
        local uname; uname=$(grep "^USERNAME=" "$vc" | cut -d= -f2 | tr -d '"' | tr -d '[:space:]')
        local tg_uid; tg_uid=$(grep "^TG_USER_ID=" "$vc" | cut -d= -f2 | tr -d '"' | tr -d '[:space:]')
        local is_trial; is_trial=$(grep "^IS_TRIAL=" "$vc" | cut -d= -f2 | tr -d '"' | tr -d '[:space:]')
        # Notif ke user (hanya premium)
        if [[ "$is_trial" != "1" && -n "$tg_uid" && "$tg_uid" != "0" ]]; then
            _tg_send "$tg_uid" "🔧 <b>Informasi Akun VMess</b>

Halo! Kami ingin memberitahu bahwa server <b>${sname}</b> sedang dalam proses pergantian.

👤 Username : <code>${uname}</code>
🌐 Server   : ${sname}

Tenang, data kamu <b>aman</b> dan sudah kami backup. 😊
Silakan hubungi admin untuk info lebih lanjut atau membuat akun di server baru."
        fi
        rm -f "$vc"
        rm -f "/tmp/zv-tg-state/vmess_${uname}.notified"
        count_vmess=$((count_vmess + 1))
    done

    echo "$count_ssh $count_vmess"
}

del_server() {
    clear
    echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
    echo -e " │              ${BWHITE}HAPUS SERVER${NC}                    │"
    echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
    echo ""

    local _ipvps; _ipvps=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null | tr -d '[:space:]')
    local count=0
    local servers=()
    for conf in "${SERVER_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue
        [[ "$conf" == *.tg.conf ]] && continue
        local NAME IP PORT
        NAME=$(grep "^NAME=" "$conf" | cut -d= -f2 | tr -d '"')
        IP=$(grep "^IP=" "$conf" | cut -d= -f2 | tr -d '"' | tr -d '[:space:]')
        PORT=$(grep "^PORT=" "$conf" | cut -d= -f2 | tr -d '"' | tr -d '[:space:]')
        local _disp_ip="${IP:-${_ipvps}}"
        local _disp_port="${PORT:-22}"
        count=$((count + 1))
        servers+=("$NAME")
        echo -e "  ${BGREEN}[${count}]${NC} ${NAME} — ${_disp_ip}:${_disp_port}"
    done

    if [[ $count -eq 0 ]]; then
        print_error "Belum ada server yang ditambahkan!"
        press_any_key; return
    fi

    echo ""
    read -rp "  Nama server yang akan dihapus: " sname
    echo ""

    if [[ -z "$sname" ]]; then
        print_error "Nama server tidak boleh kosong!"
        press_any_key; return
    fi

    local conf_file="${SERVER_DIR}/${sname}.conf"
    local tg_conf_file="${SERVER_DIR}/${sname}.tg.conf"

    if [[ ! -f "$conf_file" ]]; then
        print_error "Server '${sname}' tidak ditemukan!"
        press_any_key; return
    fi

    # Hitung akun terkait
    local n_ssh=0 n_vmess=0
    for ac in "${ACCOUNT_SSH}"/*.conf; do
        [[ -f "$ac" ]] || continue
        local srv; srv=$(grep "^SERVER=" "$ac" | cut -d= -f2 | tr -d '"' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ "$srv" == "$sname" ]] && n_ssh=$((n_ssh + 1))
    done
    for vc in "${ACCOUNT_VMESS}"/*.conf; do
        [[ -f "$vc" ]] || continue
        local srv; srv=$(grep "^SERVER=" "$vc" | cut -d= -f2 | tr -d '"' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ "$srv" == "$sname" ]] && n_vmess=$((n_vmess + 1))
    done

    echo -e "  ${BYELLOW}⚠  Server: ${BWHITE}${sname}${NC}"
    echo -e "  ${BYELLOW}   Akun terkait: ${BWHITE}${n_ssh} SSH${NC}, ${BWHITE}${n_vmess} VMess${NC}"
    echo -e "  ${BYELLOW}   Semua akun di server ini akan dihapus!${NC}"
    echo ""
    echo -e "  ${BGREEN}[1]${NC} Backup dulu, lalu hapus"
    echo -e "  ${BRED}[2]${NC} Hapus langsung (tanpa backup)"
    echo -e "  ${BYELLOW}[0]${NC} Batal"
    echo ""
    read -rp "  Pilihan: " pilihan
    echo ""

    case "$pilihan" in
        0|"")
            echo -e "  ${BYELLOW}Dibatalkan.${NC}"
            press_any_key; return ;;
        1)
            echo -e "  ${BCYAN}Membuat backup...${NC}"
            local bak_file
            bak_file=$(_backup_server "$sname")
            if [[ -f "$bak_file" ]]; then
                print_ok "Backup berhasil: $(basename "$bak_file")"
                print_ok "Dikirim ke Telegram admin."
            else
                print_error "Backup gagal, tapi tetap lanjut hapus."
            fi
            echo ""
            ;;
        2)
            read -rp "  ${BRED}Yakin hapus tanpa backup? (y/N): ${NC}" confirm
            echo ""
            [[ "${confirm,,}" != "y" ]] && {
                echo -e "  ${BYELLOW}Dibatalkan.${NC}"
                press_any_key; return
            }
            ;;
        *)
            print_error "Pilihan tidak valid!"
            press_any_key; return ;;
    esac

    # Hapus akun + notif user
    echo -e "  ${BCYAN}Menghapus akun terkait + notif user...${NC}"
    local result
    result=$(_hapus_akun_server "$sname")
    local del_ssh del_vmess
    del_ssh=$(echo "$result" | awk '{print $1}')
    del_vmess=$(echo "$result" | awk '{print $2}')

    # Hapus conf server
    rm -f "$conf_file" "$tg_conf_file"

    echo ""
    print_ok "Server '${sname}' berhasil dihapus."
    print_ok "SSH dihapus  : ${del_ssh} akun"
    print_ok "VMess dihapus: ${del_vmess} akun"
    [[ $((del_ssh + del_vmess)) -gt 0 ]] && print_ok "Notif dikirim ke user terkait."

    press_any_key
}

del_server
