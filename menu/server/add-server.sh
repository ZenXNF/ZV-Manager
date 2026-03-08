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
    echo -e "  ${BWHITE}Label  :${NC} ${BGREEN}${tg_label}${NC}"
    echo -e "  ${BWHITE}Tipe   :${NC} ${BGREEN}${server_type}${NC}"
    [[ "$server_type" != "vmess" ]] && \
        echo -e "  ${BWHITE}Harga SSH   :${NC} ${BGREEN}Rp${tg_harga_hari}/hari${NC}"
    [[ "$server_type" != "ssh" ]] && \
        echo -e "  ${BWHITE}Harga VMess :${NC} ${BGREEN}Rp${tg_harga_vmess_hari}/hari${NC}"
    press_any_key
}

add_server
