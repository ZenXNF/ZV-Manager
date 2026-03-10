#!/bin/bash
# ============================================================
#   ZV-Manager - Tambah Server
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/logger.sh
source /etc/zv-manager/utils/helpers.sh

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
    read -rp "  Nama server (contoh: vps1, vps-sg)  : " name
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

    [[ -z "$name" || -z "$ip" || -z "$pass" ]] && {
        print_error "Nama, IP, dan password wajib diisi!"
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

    # Inisialisasi semua variabel tg.conf
    local tg_harga_hari="0" tg_harga_bulan="0"
    local tg_harga_vmess_hari="0" tg_harga_vmess_bulan="0"
    local tg_bw_total="Unlimited"
    local tg_limit_ip="2"
    local tg_max_akun="500"
    local tg_bw_per_hari="5"

    # --- Pengaturan SSH ---
    if [[ "$server_type" == "ssh" || "$server_type" == "both" ]]; then
        echo ""
        echo -e "  ${BWHITE}── Pengaturan SSH ──────────────────────────${NC}"
        read -rp "  Harga SSH / hari (Rp)    [${tg_harga_hari}]: " v
        [[ "$v" =~ ^[0-9]+$ ]] && tg_harga_hari="$v"
        tg_harga_bulan=$(( tg_harga_hari * 30 ))
        read -rp "  Limit IP SSH per akun    [${tg_limit_ip}]: " v
        [[ "$v" =~ ^[0-9]+$ ]] && tg_limit_ip="$v"
        read -rp "  Maks akun SSH di server  [${tg_max_akun}]: " v
        [[ "$v" =~ ^[0-9]+$ ]] && tg_max_akun="$v"
        read -rp "  Bandwidth / hari (GB)    [${tg_bw_per_hari}]: " v
        [[ "$v" =~ ^[0-9]+$ ]] && tg_bw_per_hari="$v"
    fi

    # --- Pengaturan VMess ---
    if [[ "$server_type" == "vmess" || "$server_type" == "both" ]]; then
        echo ""
        echo -e "  ${BWHITE}── Pengaturan VMess ────────────────────────${NC}"
        read -rp "  Harga VMess / hari (Rp)  [${tg_harga_vmess_hari}]: " v
        [[ "$v" =~ ^[0-9]+$ ]] && tg_harga_vmess_hari="$v"
        tg_harga_vmess_bulan=$(( tg_harga_vmess_hari * 30 ))
        if [[ "$server_type" == "vmess" ]]; then
            # VMess only — tanya limit IP & max akun juga
            read -rp "  Limit IP VMess per akun  [${tg_limit_ip}]: " v
            [[ "$v" =~ ^[0-9]+$ ]] && tg_limit_ip="$v"
            read -rp "  Maks akun VMess          [${tg_max_akun}]: " v
            [[ "$v" =~ ^[0-9]+$ ]] && tg_max_akun="$v"
            read -rp "  Bandwidth / hari (GB)    [${tg_bw_per_hari}]: " v
            [[ "$v" =~ ^[0-9]+$ ]] && tg_bw_per_hari="$v"
        fi
    fi

    # --- Tulis tg.conf ---
    cat > "${SERVER_DIR}/${name}.tg.conf" <<TGEOF
TG_SERVER_LABEL="${tg_label}"
TG_SERVER_TYPE="${server_type}"
TG_HARGA_HARI="${tg_harga_hari}"
TG_HARGA_BULAN="${tg_harga_bulan}"
TG_HARGA_VMESS_HARI="${tg_harga_vmess_hari}"
TG_HARGA_VMESS_BULAN="${tg_harga_vmess_bulan}"
TG_BW_TOTAL="${tg_bw_total}"
TG_LIMIT_IP="${tg_limit_ip}"
TG_MAX_AKUN="${tg_max_akun}"
TG_BW_PER_HARI="${tg_bw_per_hari}"
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
    while IFS= read -r f; do srv_backups+=("$f"); done < <(ls -t "$BACKUP_DIR"/zv-ssh-*.tar.gz 2>/dev/null)

    if [[ ${#srv_backups[@]} -eq 0 ]]; then
        echo -e "  ${BYELLOW}(Tidak ada backup server tersimpan — lewati)${NC}"
        echo ""
        press_any_key
        return
    fi

    read -rp "  Restore akun dari backup? [y/n]: " do_restore
    if [[ "$do_restore" != "y" && "$do_restore" != "Y" ]]; then
        press_any_key
        return
    fi

    echo ""
    echo -e "  ${BWHITE}Pilih backup server:${NC}"
    echo ""
    local i=1
    for f in "${srv_backups[@]}"; do
        local nm sz
        nm=$(basename "$f" | sed 's/zv-ssh-//;s/.tar.gz//' | tr '_' ' ')
        sz=$(stat -c%s "$f" 2>/dev/null || echo 0)
        if   [[ $sz -ge 1048576 ]]; then sz=$(printf "%.1f MB" "$(echo "scale=1; $sz/1048576" | bc)")
        elif [[ $sz -ge 1024    ]]; then sz=$(printf "%.1f KB" "$(echo "scale=1; $sz/1024" | bc)")
        else sz="${sz} B"; fi
        echo -e "  ${BGREEN}[${i}]${NC} ${nm} (${sz})"
        i=$((i+1))
    done
    echo ""
    read -rp "  Pilih nomor backup: " bnum
    [[ ! "$bnum" =~ ^[0-9]+$ ]] && { press_any_key; return; }
    local sel_backup="${srv_backups[$((bnum-1))]}"
    [[ -z "$sel_backup" ]] && { press_any_key; return; }

    # Jalankan restore langsung (inline, tidak perlu buka menu)
    echo ""
    echo -e "  ${BYELLOW}Memulai restore ke server '${name}'...${NC}"
    echo ""

    local BASE_DIR="/etc/zv-manager"
    local XTMP="/tmp/zv-restore-add-$$"
    mkdir -p "$XTMP"
    tar -xzf "$sel_backup" -C "$XTMP" 2>/dev/null

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
            # Inject Xray dulu (tanpa copy conf supaya agent tidak skip)
            /usr/local/bin/xray api adu -s "127.0.0.1:10085" -inbound "vmess-ws"                 -user "{"vmess":{"id":"${UUID}","email":"${USERNAME}@vmess","alterId":0}}" &>/dev/null || true
            /usr/local/bin/xray api adu -s "127.0.0.1:10085" -inbound "vmess-grpc"                 -user "{"vmess":{"id":"${UUID}","email":"${USERNAME}@vmess","alterId":0}}" &>/dev/null || true
            # Baru copy conf
            cp "$vc" "${BASE_DIR}/accounts/vmess/${USERNAME}.conf"
        else
            remote_vmess_agent "$name" add                 "$USERNAME" "$UUID" "$days_left" "${BW_LIMIT_GB:-0}" 2>/dev/null
            cp "$vc" "${BASE_DIR}/accounts/vmess/${USERNAME}.conf"
        fi
        echo -e "    ${BGREEN}✓${NC} VMess: ${USERNAME}"
        vmess_ok=$((vmess_ok+1))
    done

    if [[ "$is_local" == true && $vmess_ok -gt 0 ]]; then
        echo -e "  ${BYELLOW}Merestart Xray...${NC}"
        systemctl restart zv-xray 2>/dev/null
    fi

    # Restart bot supaya cache counter akun langsung fresh
    echo -e "  ${BYELLOW}Merestart bot...${NC}"
    systemctl restart zv-telegram 2>/dev/null
    sleep 2

    rm -rf "$XTMP"
    echo ""
    echo -e "  ${BGREEN}✓ Restore selesai! SSH: ${ssh_ok} akun, VMess: ${vmess_ok} akun.${NC}"
    [[ -n "$new_domain" ]] && \
        echo -e "  ${BWHITE}Domain akun diupdate ke: ${new_domain}${NC}"
    echo ""

    press_any_key
}

add_server
