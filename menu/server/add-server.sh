#!/bin/bash
# ============================================================
#   ZV-Manager - Tambah Server
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/core/telegram.sh
tg_load 2>/dev/null || true

_tg_send() {
    local chat_id="$1" text="$2"
    [[ -z "$TG_TOKEN" || -z "$chat_id" ]] && return
    printf '%b' "$text" | curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -F "chat_id=${chat_id}" \
        -F "parse_mode=HTML" \
        -F "text=<-" --max-time 10 &>/dev/null
}

SERVER_DIR="/etc/zv-manager/servers"
mkdir -p "$SERVER_DIR"

add_server() {
    clear
    echo -e "${BCYAN} ┌─────────────────────────────────────────────┐${NC}"
    echo -e " │           ${BWHITE}TAMBAH SERVER BARU${NC}                │"
    echo -e "${BCYAN} └─────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BYELLOW}Tip: Neva (VPS ini sendiri) juga bisa ditambahkan.${NC}"
    echo ""
    while true; do
        read -rp "  Nama server (contoh: vps1, vps-sg)  : " name
        if [[ -z "$name" ]]; then
            echo -e "  ${BRED}Nama server wajib diisi.${NC}"
        elif [[ "$name" =~ [[:space:]] ]]; then
            echo -e "  ${BRED}Nama server tidak boleh mengandung spasi. Gunakan tanda hubung, contoh: neva-jakarta${NC}"
        else
            break
        fi
    done
    read -rp "  IP Address                           : " ip
    read -rp "  Domain (contoh: server.zenxnf.com)   : " domain
    read -rp "  Port SSH              [default: 22]  : " port
    read -rp "  Username              [default: root]: " user
    read -rsp "  Password                             : " pass
    echo ""
    echo ""

    [[ -z "$port" ]] && port=22
    [[ -z "$user" ]] && user=root
    [[ -z "$domain" ]] && domain="$ip"

    [[ -z "$ip" || -z "$pass" ]] && {
        print_error "IP dan password wajib diisi!"
        press_any_key
        return
    }

    if [[ -f "${SERVER_DIR}/${name}.conf" ]]; then
        print_error "Server '${name}' sudah ada!"
        press_any_key
        return
    fi

    # --- Verifikasi domain → IP ---
    if [[ "$domain" != "$ip" ]]; then
        print_info "Memverifikasi domain ${domain}..."
        local resolved_ip=""
        if command -v dig &>/dev/null; then
            resolved_ip=$(dig +short "$domain" A 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
        fi
        if [[ -z "$resolved_ip" ]] && command -v host &>/dev/null; then
            resolved_ip=$(host -t A "$domain" 2>/dev/null | awk '/has address/ {print $4}' | head -1)
        fi
        if [[ -z "$resolved_ip" ]] && command -v nslookup &>/dev/null; then
            resolved_ip=$(nslookup "$domain" 2>/dev/null | awk '/^Address: / {print $2}' | tail -1)
        fi
        if [[ -z "$resolved_ip" ]]; then
            echo ""
            print_warning "Domain tidak bisa di-resolve. Mungkin DNS belum aktif."
            echo -e "  ${BYELLOW}Lanjut tanpa verifikasi domain? [y/n]${NC}"
            read -rp "  " skip_ans
            if [[ ! "$skip_ans" =~ ^[Yy]$ ]]; then
                print_info "Dibatalkan."
                press_any_key
                return
            fi
        elif [[ "$resolved_ip" != "$ip" ]]; then
            echo ""
            print_error "Domain ${domain} mengarah ke ${resolved_ip}, bukan ${ip}!"
            echo -e "  ${BYELLOW}Pastikan DNS record A untuk ${domain} sudah diset ke ${ip}${NC}"
            press_any_key
            return
        else
            print_ok "Domain ${domain} → ${resolved_ip} ✓"
        fi
        echo ""
    fi

    # --- Verifikasi koneksi SSH ---
    print_info "Mencoba koneksi ke ${user}@${ip}:${port}..."
    if ! command -v sshpass &>/dev/null; then
        print_info "Menginstall sshpass..."
        apt-get install -y sshpass &>/dev/null
    fi
    local ssh_result
    ssh_result=$(sshpass -p "$pass" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 \
        -o BatchMode=no \
        -p "$port" \
        "${user}@${ip}" \
        "echo ZV-TEST-OK" 2>&1)
    if [[ "$ssh_result" != *"ZV-TEST-OK"* ]]; then
        echo ""
        print_error "Koneksi SSH gagal! Server tidak disimpan."
        echo ""
        local err_hint
        err_hint=$(echo "$ssh_result" | grep -v "^$" | grep -v "Warning" | tail -2)
        [[ -n "$err_hint" ]] && echo -e "  ${BYELLOW}Detail: ${err_hint}${NC}"
        echo ""
        echo -e "  ${BYELLOW}Kemungkinan penyebab:${NC}"
        echo -e "  - IP atau port salah"
        echo -e "  - Password salah"
        echo -e "  - SSH server belum aktif di VPS tujuan"
        press_any_key
        return
    fi
    print_ok "Koneksi SSH berhasil!"
    echo ""

    # --- Ambil ISP server ---
    print_info "Mengambil info ISP server..."
    local isp
    isp=$(sshpass -p "$pass" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 \
        -o BatchMode=no \
        -p "$port" \
        "${user}@${ip}" \
        "curl -s --max-time 5 ipinfo.io/org 2>/dev/null | sed 's/^AS[0-9]* //'" 2>/dev/null)
    [[ -z "$isp" ]] && isp="Unknown"
    print_ok "ISP: ${isp}"
    echo ""

    # --- Pilih tipe server ---
    echo -e "${BCYAN}  ┌─────────────────────────────────────────────┐${NC}"
    echo -e "  │            ${BWHITE}TIPE SERVER${NC}                      │"
    echo -e "${BCYAN}  └─────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BWHITE}[1]${NC} SSH only   — muncul di menu SSH"
    echo -e "  ${BWHITE}[2]${NC} VMess only — muncul di menu VMess"
    echo -e "  ${BWHITE}[3]${NC} Keduanya   — muncul di SSH + VMess"
    echo ""
    local server_type_choice
    while true; do
        read -rp "  Pilih tipe [1/2/3]: " server_type_choice
        case "$server_type_choice" in
            1) server_type="ssh";   break ;;
            2) server_type="vmess"; break ;;
            3) server_type="both";  break ;;
            *) echo -e "  ${BRED}Pilih 1, 2, atau 3${NC}" ;;
        esac
    done
    echo ""

    # --- Simpan ke file conf ---
    cat > "${SERVER_DIR}/${name}.conf" <<CONFEOF
NAME="${name}"
IP="${ip}"
DOMAIN="${domain}"
PORT="${port}"
USER="${user}"
PASS="${pass}"
SERVER_TYPE="${server_type}"
ISP="${isp}"
ADDED="$(date +"%Y-%m-%d %H:%M")"
CONFEOF
    chmod 600 "${SERVER_DIR}/${name}.conf"
    print_ok "Server '${name}' berhasil disimpan! (tipe: ${server_type})"
    echo ""

    # ================================================================
    #   PENGATURAN TELEGRAM BOT
    # ================================================================
    echo -e "${BCYAN}  ┌─────────────────────────────────────────────┐${NC}"
    echo -e "  │        ${BWHITE}PENGATURAN TELEGRAM BOT${NC}               │"
    echo -e "${BCYAN}  └─────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BYELLOW}Tekan Enter untuk pakai nilai default.${NC}"
    echo ""

    local tg_label="$name"
    read -rp "  Label di bot         [${tg_label}]: " v; [[ -n "$v" ]] && tg_label="$v"

    # Inisialisasi variabel SSH
    local tg_harga_hari="0" tg_harga_bulan="0"
    local tg_limit_ip="2"
    local tg_max_akun="500"
    local tg_bw_per_hari="5"
    # Inisialisasi variabel VMess (terpisah dari SSH)
    local tg_harga_vmess_hari="0" tg_harga_vmess_bulan="0"
    local tg_limit_ip_vmess="2"
    local tg_max_akun_vmess="500"
    local tg_bw_per_hari_vmess="5"

    # --- Pengaturan SSH ---
    if [[ "$server_type" == "ssh" || "$server_type" == "both" ]]; then
        echo ""
        echo -e "  ${BWHITE}── Pengaturan SSH ──────────────────────────${NC}"
        echo -e "  ${BYELLOW}(Semua field wajib diisi)${NC}"
        while true; do
            read -rp "  Harga SSH / hari (Rp)    : " v
            [[ "$v" =~ ^[0-9]+$ && "$v" != "0" ]] && { tg_harga_hari="$v"; break; }
            echo -e "  ${BRED}Harga harus angka dan tidak boleh 0.${NC}"
        done
        tg_harga_bulan=$(( tg_harga_hari * 30 ))
        while true; do
            read -rp "  Limit IP SSH per akun    : " v
            [[ "$v" =~ ^[0-9]+$ && "$v" != "0" ]] && { tg_limit_ip="$v"; break; }
            echo -e "  ${BRED}Limit IP harus angka dan tidak boleh 0.${NC}"
        done
        while true; do
            read -rp "  Maks akun SSH di server  : " v
            [[ "$v" =~ ^[0-9]+$ && "$v" != "0" ]] && { tg_max_akun="$v"; break; }
            echo -e "  ${BRED}Maks akun harus angka dan tidak boleh 0.${NC}"
        done
        while true; do
            read -rp "  Bandwidth / hari (GB)    : " v
            [[ "$v" =~ ^[0-9]+$ ]] && { tg_bw_per_hari="$v"; break; }
            echo -e "  ${BRED}Bandwidth harus angka (0 = unlimited).${NC}"
        done
    fi

    # --- Pengaturan VMess ---
    if [[ "$server_type" == "vmess" || "$server_type" == "both" ]]; then
        echo ""
        echo -e "  ${BWHITE}── Pengaturan VMess ────────────────────────${NC}"
        echo -e "  ${BYELLOW}(Kosongkan/Enter = ikuti setting SSH)${NC}"
        # Default VMess ikuti SSH jika server type both
        if [[ "$server_type" == "both" ]]; then
            tg_harga_vmess_hari="${tg_harga_hari}"
            tg_limit_ip_vmess="${tg_limit_ip}"
            tg_max_akun_vmess="${tg_max_akun}"
            tg_bw_per_hari_vmess="${tg_bw_per_hari}"
        fi
        read -rp "  Harga VMess / hari (Rp)     [${tg_harga_vmess_hari}]: " v
        [[ "$v" =~ ^[0-9]+$ ]] && tg_harga_vmess_hari="$v"
        tg_harga_vmess_bulan=$(( tg_harga_vmess_hari * 30 ))
        read -rp "  Limit IP VMess per akun     [${tg_limit_ip_vmess}]: " v
        [[ "$v" =~ ^[0-9]+$ ]] && tg_limit_ip_vmess="$v"
        read -rp "  Maks akun VMess             [${tg_max_akun_vmess}]: " v
        [[ "$v" =~ ^[0-9]+$ ]] && tg_max_akun_vmess="$v"
        read -rp "  Bandwidth VMess / hari (GB) [${tg_bw_per_hari_vmess}]: " v
        [[ "$v" =~ ^[0-9]+$ ]] && tg_bw_per_hari_vmess="$v"
    fi

    # --- Tulis tg.conf ---
    cat > "${SERVER_DIR}/${name}.tg.conf" <<TGEOF
TG_SERVER_LABEL="${tg_label}"
TG_SERVER_TYPE="${server_type}"
TG_HARGA_HARI="${tg_harga_hari}"
TG_HARGA_BULAN="${tg_harga_bulan}"
TG_LIMIT_IP="${tg_limit_ip}"
TG_MAX_AKUN="${tg_max_akun}"
TG_BW_PER_HARI="${tg_bw_per_hari}"
TG_HARGA_VMESS_HARI="${tg_harga_vmess_hari}"
TG_HARGA_VMESS_BULAN="${tg_harga_vmess_bulan}"
TG_LIMIT_IP_VMESS="${tg_limit_ip_vmess}"
TG_MAX_AKUN_VMESS="${tg_max_akun_vmess}"
TG_BW_PER_HARI_VMESS="${tg_bw_per_hari_vmess}"
TGEOF

    echo ""
    print_ok "Pengaturan Telegram disimpan!"
    echo ""
    echo -e "  ${BWHITE}IP     :${NC} ${BGREEN}${ip}${NC}"
    echo -e "  ${BWHITE}Domain :${NC} ${BGREEN}${domain}${NC}"
    echo -e "  ${BWHITE}ISP    :${NC} ${BGREEN}${isp}${NC}"
    echo -e "  ${BWHITE}Label  :${NC} ${BGREEN}${tg_label}${NC}"
    echo -e "  ${BWHITE}Tipe   :${NC} ${BGREEN}${server_type}${NC}"
    [[ "$server_type" != "vmess" ]] && \
        echo -e "  ${BWHITE}Harga SSH   :${NC} ${BGREEN}Rp${tg_harga_hari}/hari${NC}"
    [[ "$server_type" != "ssh" ]] && \
        echo -e "  ${BWHITE}Harga VMess :${NC} ${BGREEN}Rp${tg_harga_vmess_hari}/hari${NC}"

    # --- Auto deploy agent ke server ---
    local local_ip
    local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null)

    if [[ "$ip" == "$local_ip" ]]; then
        # Server lokal — pastikan binary sudah ada
        cp /etc/zv-manager/zv-agent.sh /usr/local/bin/zv-agent 2>/dev/null
        chmod +x /usr/local/bin/zv-agent 2>/dev/null
        cp /etc/zv-manager/zv-vmess-agent.sh /usr/local/bin/zv-vmess-agent 2>/dev/null
        chmod +x /usr/local/bin/zv-vmess-agent 2>/dev/null
        print_ok "Agent lokal siap."
    else
        # Server remote — deploy via SSH
        echo ""
        print_info "Deploy agent ke remote server ${name}..."
        source /etc/zv-manager/utils/remote.sh
        local r1; r1=$(deploy_agent "$name")
        if [[ "$r1" == "DEPLOY-OK" ]]; then
            print_ok "zv-agent (SSH) berhasil di-deploy ke ${name}!"
        else
            print_warning "zv-agent gagal: ${r1#DEPLOY-ERR|}"
        fi
        local r2; r2=$(deploy_vmess_agent "$name")
        if [[ "$r2" == "DEPLOY-OK" ]]; then
            print_ok "zv-vmess-agent berhasil di-deploy ke ${name}!"
        else
            print_warning "zv-vmess-agent gagal: ${r2#DEPLOY-ERR|}"
        fi
    fi

    # --- Tanya kirim notif server baru ke user ---
    echo ""
    echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
    echo -e " │         ${BWHITE}NOTIFIKASI SERVER BARU${NC}                │"
    echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  Kirim notif ke user tentang server baru ini?"

    # Tentukan target user berdasarkan tipe server
    case "$server_type" in
        ssh)   echo -e "  ${BYELLOW}→ Akan dikirim ke user yang punya akun SSH${NC}" ;;
        vmess) echo -e "  ${BYELLOW}→ Akan dikirim ke user yang punya akun VMess${NC}" ;;
        both)  echo -e "  ${BYELLOW}→ Akan dikirim ke semua user (SSH + VMess)${NC}" ;;
    esac
    echo ""

    read -rp "  Kirim notif? [y/n]: " do_notif
    if [[ "$do_notif" =~ ^[Yy]$ ]]; then
        echo ""
        print_info "Mengumpulkan daftar user..."

        local BASE_DIR="/etc/zv-manager"
        local _notif_uids=()

        # Kumpulkan UID berdasarkan tipe server
        # Kumpulkan semua UID dari registered users (accounts/users/*.user)
        local USERS_DIR="${BASE_DIR}/accounts/users"
        if [[ -d "$USERS_DIR" ]]; then
            for _uf in "${USERS_DIR}"/*.user; do
                [[ -f "$_uf" ]] || continue
                local _uid
                _uid=$(basename "$_uf" .user)
                [[ -z "$_uid" || "$_uid" == "0" ]] && continue
                # Filter berdasarkan tipe server
                # ssh   → hanya user yang punya akun SSH
                # vmess → hanya user yang punya akun VMess
                # both  → semua registered user
                if [[ "$server_type" == "ssh" ]]; then
                    ls "${BASE_DIR}/accounts/ssh"/*.conf 2>/dev/null | \
                        xargs grep -l "^TG_USER_ID=\"${_uid}\"" 2>/dev/null | grep -q . || continue
                elif [[ "$server_type" == "vmess" ]]; then
                    ls "${BASE_DIR}/accounts/vmess"/*.conf 2>/dev/null | \
                        xargs grep -l "^TG_USER_ID=\"${_uid}\"" 2>/dev/null | grep -q . || continue
                fi
                # Cek duplikat
                local _dup=false
                for _x in "${_notif_uids[@]}"; do
                    [[ "$_x" == "$_uid" ]] && _dup=true && break
                done
                [[ "$_dup" == false ]] && _notif_uids+=("$_uid")
            done
        fi

        if [[ ${#_notif_uids[@]} -eq 0 ]]; then
            print_warning "Belum ada user yang bisa dinotif (belum ada akun terdaftar)."
        else
            # Susun isi pesan
            local _type_label=""
            case "$server_type" in
                ssh)   _type_label="✅ Tersedia: 🔑 SSH" ;;
                vmess) _type_label="✅ Tersedia: ⚡ VMess" ;;
                both)  _type_label="✅ Tersedia: 🔑 SSH + ⚡ VMess" ;;
            esac

            local _notif_msg="🆕 <b>Server Baru Tersedia!</b>
━━━━━━━━━━━━━━━━━━━
🖥 ${tg_label}
🌐 <code>${domain}</code>
🏢 ${isp}
━━━━━━━━━━━━━━━━━━━
${_type_label}
━━━━━━━━━━━━━━━━━━━
Buka bot untuk beli akun di server ini! 🚀"

            print_info "Mengirim ke ${#_notif_uids[@]} user..."
            local _ok=0 _fail=0
            for _uid in "${_notif_uids[@]}"; do
                _tg_send "$_uid" "$_notif_msg"
                if [[ $? -eq 0 ]]; then
                    _ok=$((_ok + 1))
                else
                    _fail=$((_fail + 1))
                fi
                sleep 0.1
            done
            print_ok "Notif terkirim: ${_ok} user ✅  Gagal: ${_fail} user"
        fi
    fi

    # --- Tanya restore akun dari backup ---
    echo ""
    echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
    echo -e " │           ${BWHITE}RESTORE AKUN (OPSIONAL)${NC}            │"
    echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  Apakah server ini ${BWHITE}pengganti server lama${NC} yang suspend?"
    echo -e "  Jika ya, akun SSH+VMess lama bisa di-restore sekarang."
    echo ""

    local BACKUP_DIR="/var/backups/zv-manager"
    local srv_backups=()
    while IFS= read -r f; do srv_backups+=("$f"); done < <(ls -t "$BACKUP_DIR"/zv-server-*.zvbak "$BACKUP_DIR"/zv-ssh-*.zvbak 2>/dev/null)

    read -rp "  Restore akun dari backup? [y/n]: " do_restore
    if [[ "$do_restore" != "y" && "$do_restore" != "Y" ]]; then
        press_any_key
        return
    fi

    local sel_backup=""
    echo ""
    if [[ ${#srv_backups[@]} -gt 0 ]]; then
        echo -e "  ${BWHITE}Pilih backup server (atau ketik 0 untuk path manual):${NC}"
        echo ""
        local i=1
        for f in "${srv_backups[@]}"; do
            local nm sz
            nm=$(basename "$f" | sed 's/zv-server-//;s/zv-ssh-//;s/.zvbak//' | tr '_' ' ')
            sz=$(stat -c%s "$f" 2>/dev/null || echo 0)
            if   [[ $sz -ge 1048576 ]]; then sz=$(printf "%.1f MB" "$(echo "scale=1; $sz/1048576" | bc)")
            elif [[ $sz -ge 1024    ]]; then sz=$(printf "%.1f KB" "$(echo "scale=1; $sz/1024" | bc)")
            else sz="${sz} B"; fi
            echo -e "  ${BGREEN}[${i}]${NC} ${nm} (${sz})"
            i=$((i+1))
        done
        echo -e "  ${BYELLOW}[0]${NC} Path manual"
        echo ""
        read -rp "  Pilih nomor backup: " bnum
        if [[ "$bnum" == "0" ]]; then
            read -rp "  Path file backup (.zvbak): " sel_backup
        elif [[ "$bnum" =~ ^[0-9]+$ ]]; then
            sel_backup="${srv_backups[$((bnum-1))]}"
        fi
    else
        echo -e "  ${BYELLOW}Tidak ada backup tersimpan, masukkan path manual:${NC}"
        read -rp "  Path file backup (.zvbak): " sel_backup
    fi

    [[ -z "$sel_backup" || ! -f "$sel_backup" ]] && {
        print_error "File backup tidak ditemukan: $sel_backup"
        press_any_key; return
    }

    # Jalankan restore langsung (inline, tidak perlu buka menu)
    echo ""
    echo -e "  ${BYELLOW}Memulai restore ke server '${name}'...${NC}"
    echo ""

    local BASE_DIR="/etc/zv-manager"
    local XTMP="/tmp/zv-restore-add-$$"
    mkdir -p "$XTMP"
    tar -xzf "$sel_backup" -C "$XTMP" 2>/dev/null

    # Handle subfolder srv-NAME/ jika ada (format baru del-server)
    local _subdir
    _subdir=$(find "$XTMP" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -1)
    if [[ -n "$_subdir" && -d "${_subdir}/ssh-accounts" ]]; then
        # Format baru: ada subfolder
        local _XTMP_BASE="$XTMP"
        XTMP="$_subdir"
    fi

    source /etc/zv-manager/utils/remote.sh 2>/dev/null

    # Deteksi lokal
    local is_local=false
    local _sip _local_ip
    _sip=$(grep "^IP=" "${BASE_DIR}/servers/${name}.conf" 2>/dev/null | cut -d= -f2 | tr -d '"')
    _local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null | tr -d '[:space:]')
    [[ -z "$_sip" || "$_sip" == "$_local_ip" ]] && is_local=true

    # Domain baru dari conf server yang baru saja dibuat
    local new_domain
    new_domain=$(grep "^DOMAIN=" "${BASE_DIR}/servers/${name}.conf" 2>/dev/null | cut -d= -f2 | tr -d '"')
    [[ -z "$new_domain" ]] && new_domain=$(grep "^DOMAIN:" "${XTMP}/server-info.txt" 2>/dev/null | awk '{print $2}')

    local ssh_ok=0 vmess_ok=0

    for ac in "${XTMP}/ssh-accounts"/*.conf; do
        [[ -f "$ac" ]] || continue
        USERNAME=$(grep "^USERNAME=" "$ac" | cut -d= -f2- | tr -d '"\n')
        PASSWORD=$(grep "^PASSWORD=" "$ac" | cut -d= -f2- | tr -d '"\n')
        EXPIRED_TS=$(grep "^EXPIRED_TS=" "$ac" | cut -d= -f2- | tr -d '"\n')
        [[ -z "$USERNAME" || -z "$PASSWORD" ]] && continue
        local now_ts days_left
        now_ts=$(date +%s)
        days_left=$(( (EXPIRED_TS - now_ts) / 86400 ))
        [[ $days_left -lt 1 ]] && days_left=1
        # Extend jika sudah expired
        if [[ "$EXPIRED_TS" -lt "$now_ts" ]]; then
            local _nts=$(( now_ts + days_left * 86400 ))
            local _nd; _nd=$(date -d "@${_nts}" +"%Y-%m-%d" 2>/dev/null)
            sed -i "s/^EXPIRED_TS=.*/EXPIRED_TS=${_nts}/" "$ac"
            sed -i "s/^EXPIRED=.*/EXPIRED=${_nd}/" "$ac"
        fi
        sed -i "s/^SERVER=.*/SERVER=\"${name}\"/" "$ac"
        [[ -n "$new_domain" ]] && sed -i "s/^DOMAIN=.*/DOMAIN=\"${new_domain}\"/" "$ac"
        cp "$ac" "${BASE_DIR}/accounts/ssh/${USERNAME}.conf"
        if [[ "$is_local" == true ]]; then
            if ! id "$USERNAME" &>/dev/null; then
                useradd -M -s /bin/false "$USERNAME" 2>/dev/null
                echo "$USERNAME:$PASSWORD" | chpasswd 2>/dev/null
            fi
        else
            remote_agent "$name" add "$USERNAME" "$PASSWORD" "$days_left" 2>/dev/null
        fi
        echo -e "    ${BGREEN}✓${NC} SSH: ${USERNAME}"
        ssh_ok=$((ssh_ok+1))
    done

    # Hapus placeholder Xray sebelum restore VMess
    if [[ "$is_local" == true ]]; then
        /usr/local/bin/xray api rmu -s "127.0.0.1:10085" -inbound "vmess-ws"   -email "placeholder@vmess" &>/dev/null || true
        /usr/local/bin/xray api rmu -s "127.0.0.1:10085" -inbound "vmess-grpc" -email "placeholder@vmess" &>/dev/null || true
    fi

    for vc in "${XTMP}/vmess-accounts"/*.conf; do
        [[ -f "$vc" ]] || continue
        USERNAME=$(grep "^USERNAME=" "$vc" | cut -d= -f2- | tr -d '"\n')
        UUID=$(grep "^UUID=" "$vc" | cut -d= -f2- | tr -d '"\n')
        EXPIRED_TS=$(grep "^EXPIRED_TS=" "$vc" | cut -d= -f2- | tr -d '"\n')
        BW_LIMIT_GB=$(grep "^BW_LIMIT_GB=" "$vc" | cut -d= -f2- | tr -d '"\n')
        [[ -z "$USERNAME" || -z "$UUID" ]] && continue
        local now_ts days_left
        now_ts=$(date +%s)
        days_left=$(( (EXPIRED_TS - now_ts) / 86400 ))
        [[ $days_left -lt 1 ]] && days_left=1
        # Extend jika sudah expired
        if [[ "$EXPIRED_TS" -lt "$now_ts" ]]; then
            local _nts=$(( now_ts + days_left * 86400 ))
            local _nd; _nd=$(date -d "@${_nts}" +"%Y-%m-%d" 2>/dev/null)
            sed -i "s/^EXPIRED_TS=.*/EXPIRED_TS=\"${_nts}\"/" "$vc"
            sed -i "s/^EXPIRED_DATE=.*/EXPIRED_DATE=\"${_nd}\"/" "$vc"
        fi
        sed -i "s/^SERVER=.*/SERVER=\"${name}\"/" "$vc"
        [[ -n "$new_domain" ]] && sed -i "s/^DOMAIN=.*/DOMAIN=\"${new_domain}\"/" "$vc"
        if [[ "$is_local" == true ]]; then
            # Copy conf dulu
            cp "$vc" "${BASE_DIR}/accounts/vmess/${USERNAME}.conf"
            # Inject ke Xray API (memory)
            local _xjson="{"vmess":{"id":"${UUID}","email":"${USERNAME}@vmess","alterId":0}}"
            /usr/local/bin/xray api adu -s "127.0.0.1:10085" -inbound "vmess-ws"   -user "$_xjson" &>/dev/null || true
            /usr/local/bin/xray api adu -s "127.0.0.1:10085" -inbound "vmess-grpc" -user "$_xjson" &>/dev/null || true
        else
            remote_vmess_agent "$name" add                 "$USERNAME" "$UUID" "$days_left" "${BW_LIMIT_GB:-0}" 2>/dev/null
            cp "$vc" "${BASE_DIR}/accounts/vmess/${USERNAME}.conf"
        fi
        echo -e "    ${BGREEN}✓${NC} VMess: ${USERNAME}"
        vmess_ok=$((vmess_ok+1))
    done

    if [[ "$is_local" == true && $vmess_ok -gt 0 ]]; then
        echo -e "  ${BYELLOW}Merestart Xray...${NC}"
        # Rebuild config.json dari semua conf aktif sebelum restart
        bash /usr/local/bin/zv-vmess-agent rebuild-config 2>/dev/null || \
            bash /etc/zv-manager/zv-vmess-agent.sh rebuild-config 2>/dev/null || true
        systemctl restart zv-xray 2>/dev/null
    fi

    # Restart bot supaya cache counter akun langsung fresh
    echo -e "  ${BYELLOW}Merestart bot...${NC}"
    systemctl restart zv-telegram 2>/dev/null
    sleep 2

    # Kirim notif ke semua user yang punya akun di server ini
    # 1 notif per user per server — berisi list semua akun SSH+VMess miliknya
    if [[ $((ssh_ok + vmess_ok)) -gt 0 && -n "$new_domain" ]]; then
        echo -e "  ${BYELLOW}Mengirim notifikasi ke user...${NC}"

        # Kumpulkan semua UID unik yang punya akun di server ini
        local _all_uids=()
        for _f in "${BASE_DIR}/accounts/ssh"/*.conf "${BASE_DIR}/accounts/vmess"/*.conf; do
            [[ -f "$_f" ]] || continue
            local _srv; _srv=$(grep "^SERVER=" "$_f" | cut -d= -f2 | tr -d '"\n')
            [[ "$_srv" != "$name" ]] && continue
            local _uid; _uid=$(grep "^TG_USER_ID=" "$_f" | cut -d= -f2 | tr -d '"[:space:]')
            [[ -z "$_uid" || "$_uid" == "0" ]] && continue
            # Tambah jika belum ada
            local _exists=false
            for _x in "${_all_uids[@]}"; do [[ "$_x" == "$_uid" ]] && _exists=true && break; done
            [[ "$_exists" == false ]] && _all_uids+=("$_uid")
        done

        # Ambil ISP server baru
        local _isp; _isp=$(grep "^ISP=" "${BASE_DIR}/servers/${name}.conf" 2>/dev/null | cut -d= -f2 | tr -d '"')

        # Kirim 1 notif per UID berisi semua akunnya
        for _uid in "${_all_uids[@]}"; do
            local _msg="✅ <b>Server Sudah Aktif Kembali!</b>

Halo! Server yang sebelumnya kami ganti kini sudah aktif kembali dengan server baru. 🎉
🌐 Domain baru : <code>${new_domain}</code>
🏢 ISP         : ${_isp:-?}

"
            # List akun SSH
            local _has_ssh=false
            for ac in "${BASE_DIR}/accounts/ssh"/*.conf; do
                [[ -f "$ac" ]] || continue
                local _srv; _srv=$(grep "^SERVER=" "$ac" | cut -d= -f2 | tr -d '"\n')
                [[ "$_srv" != "$name" ]] && continue
                local _auid; _auid=$(grep "^TG_USER_ID=" "$ac" | cut -d= -f2 | tr -d '"[:space:]')
                [[ "$_auid" != "$_uid" ]] && continue
                local _uname; _uname=$(grep "^USERNAME=" "$ac" | cut -d= -f2 | tr -d '"[:space:]')
                local _exp_ts; _exp_ts=$(grep "^EXPIRED_TS=" "$ac" | cut -d= -f2 | tr -d '"[:space:]')
                local _exp_d; _exp_d=$(date -d "@${_exp_ts}" "+%d %b %Y" 2>/dev/null || echo "?")
                [[ "$_has_ssh" == false ]] && _msg+="🔑 <b>Akun SSH:</b>
" && _has_ssh=true
                _msg+="👤 ${_uname} · ⏳ ${_exp_d}
"
            done

            # List akun VMess
            local _has_vmess=false
            for vc in "${BASE_DIR}/accounts/vmess"/*.conf; do
                [[ -f "$vc" ]] || continue
                local _srv; _srv=$(grep "^SERVER=" "$vc" | cut -d= -f2 | tr -d '"\n')
                [[ "$_srv" != "$name" ]] && continue
                local _vuid; _vuid=$(grep "^TG_USER_ID=" "$vc" | cut -d= -f2 | tr -d '"[:space:]')
                [[ "$_vuid" != "$_uid" ]] && continue
                local _is_trial; _is_trial=$(grep "^IS_TRIAL=" "$vc" | cut -d= -f2 | tr -d '"[:space:]')
                [[ "$_is_trial" == "1" ]] && continue
                local _uname; _uname=$(grep "^USERNAME=" "$vc" | cut -d= -f2 | tr -d '"[:space:]')
                local _uuid; _uuid=$(grep "^UUID=" "$vc" | cut -d= -f2 | tr -d '"[:space:]')
                local _exp_ts; _exp_ts=$(grep "^EXPIRED_TS=" "$vc" | cut -d= -f2 | tr -d '"[:space:]')
                local _exp_d; _exp_d=$(date -d "@${_exp_ts}" "+%d %b %Y" 2>/dev/null || echo "?")
                [[ "$_has_vmess" == false ]] && _msg+="
⚡ <b>Akun VMess:</b>
" && _has_vmess=true
                _msg+="👤 ${_uname} · <code>${_uuid}</code> · ⏳ ${_exp_d}
"
            done

            _msg+="
Silakan update konfigurasi dengan domain baru di atas.
Hubungi admin jika ada pertanyaan. 😊"
            _tg_send "$_uid" "$_msg"
        done
    fi

    rm -rf "$XTMP"
    echo ""
    echo -e "  ${BGREEN}✓ Restore selesai! SSH: ${ssh_ok} akun, VMess: ${vmess_ok} akun.${NC}"
    [[ -n "$new_domain" ]] && \
        echo -e "  ${BWHITE}Domain akun diupdate ke: ${new_domain}${NC}"
    echo ""

    press_any_key
}

add_server
