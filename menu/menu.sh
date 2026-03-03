#!/bin/bash
# ============================================================
#   ZV-Manager - Menu Utama
#   Versi: 1.0.0
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/config.conf

# Nama bulan dalam Bahasa Indonesia
_bulan_indo() {
    local bulan=$1
    case $bulan in
        01) echo "Januari" ;;
        02) echo "Februari" ;;
        03) echo "Maret" ;;
        04) echo "April" ;;
        05) echo "Mei" ;;
        06) echo "Juni" ;;
        07) echo "Juli" ;;
        08) echo "Agustus" ;;
        09) echo "September" ;;
        10) echo "Oktober" ;;
        11) echo "November" ;;
        12) echo "Desember" ;;
    esac
}

# Nama hari dalam Bahasa Indonesia
_hari_indo() {
    local hari=$1
    case $hari in
        Monday)    echo "Senin" ;;
        Tuesday)   echo "Selasa" ;;
        Wednesday) echo "Rabu" ;;
        Thursday)  echo "Kamis" ;;
        Friday)    echo "Jumat" ;;
        Saturday)  echo "Sabtu" ;;
        Sunday)    echo "Minggu" ;;
    esac
}

# Waktu realtime Asia/Jakarta dalam format Indonesia
_waktu_indo() {
    local hari_en bulan_en tgl tahun jam_wib
    hari_en=$(TZ="Asia/Jakarta" date +"%A")
    tgl=$(TZ="Asia/Jakarta" date +"%d")
    bulan_en=$(TZ="Asia/Jakarta" date +"%m")
    tahun=$(TZ="Asia/Jakarta" date +"%Y")
    jam_wib=$(TZ="Asia/Jakarta" date +"%H:%M:%S")

    local hari_id bulan_id
    hari_id=$(_hari_indo "$hari_en")
    bulan_id=$(_bulan_indo "$bulan_en")

    echo "${hari_id}, ${tgl} ${bulan_id} ${tahun} — ${jam_wib} WIB"
}

# Status satu service: ● hijau kalau aktif, ● merah kalau mati
svc_status() {
    local name="$1"
    if systemctl is-active --quiet "$name" 2>/dev/null; then
        echo -e "${BGREEN}●${NC}"
    else
        echo -e "${BRED}●${NC}"
    fi
}

# Baca info izin dari cache license.info
get_license_display() {
    local info_file="/etc/zv-manager/license.info"

    if [[ ! -f "$info_file" ]]; then
        echo -e "  ${BCYAN}║${NC}  ${BWHITE}Expired  :${NC} ${BYELLOW}Belum dicek${NC}"
        return
    fi

    local LICENSE_NAME LICENSE_EXPIRED LICENSE_DAYS_LEFT LICENSE_CODE
    source "$info_file" 2>/dev/null

    local nama_display="${LICENSE_NAME:-Tidak diketahui}"
    local expired_text expired_color

    if [[ "$LICENSE_DAYS_LEFT" -eq 99999 ]] 2>/dev/null; then
        expired_text="Seumur hidup"
        expired_color="$BGREEN"
    elif [[ "$LICENSE_DAYS_LEFT" -gt 2 ]] 2>/dev/null; then
        expired_text="${LICENSE_DAYS_LEFT} hari lagi"
        expired_color="$BGREEN"
    elif [[ "$LICENSE_DAYS_LEFT" -ge 0 ]] 2>/dev/null; then
        expired_text="${LICENSE_DAYS_LEFT} hari lagi — segera perpanjang!"
        expired_color="$BYELLOW"
    else
        local days_over=$(( -LICENSE_DAYS_LEFT ))
        local grace_sisa=$(( 2 - days_over ))
        if [[ "$grace_sisa" -gt 0 ]]; then
            expired_text="Habis! ${grace_sisa} hari lagi dinonaktifkan — segera perpanjang!"
            expired_color="$BRED"
        else
            expired_text="Habis! VPS akan segera dinonaktifkan"
            expired_color="$BRED"
        fi
    fi

    echo -e "  ${BCYAN}║${NC}  ${BWHITE}Nama VPS :${NC} ${BPURPLE}${nama_display}${NC}"
    echo -e "  ${BCYAN}║${NC}  ${BWHITE}Expired  :${NC} ${expired_color}${expired_text}${NC}"
}

show_header() {
    local ip today
    ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null || curl -s --max-time 5 ipv4.icanhazip.com)
    today=$(_waktu_indo)

    local s_ssh s_db s_nginx s_wss s_udp s_stunnel
    s_ssh=$(svc_status ssh)
    s_db=$(svc_status dropbear)
    s_nginx=$(svc_status nginx)
    s_wss=$(svc_status zv-wss)
    s_udp=$(svc_status zv-udp)
    s_stunnel=$(svc_status zv-stunnel)

    clear
    echo -e "${BCYAN}  ╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${BCYAN}  ║${NC}  ${BWHITE}ZV-Manager${NC} ${BYELLOW}v${SCRIPT_VERSION}${NC}                                ${BCYAN}║${NC}"
    echo -e "${BCYAN}  ╠══════════════════════════════════════════════════╣${NC}"
    echo -e "${BCYAN}  ║${NC}  ${BWHITE}IP       :${NC} ${BGREEN}${ip}${NC}"
    echo -e "${BCYAN}  ║${NC}  ${BWHITE}Waktu    :${NC} ${BYELLOW}${today}${NC}"
    echo -e "${BCYAN}  ╠══════════════════════════════════════════════════╣${NC}"
    get_license_display
    echo -e "${BCYAN}  ╠══════════════════════════════════════════════════╣${NC}"
    echo -e "${BCYAN}  ║${NC}  ${s_ssh} SSH  ${s_db} Dropbear  ${s_nginx} Nginx  ${s_stunnel} SSL  ${s_wss} WS  ${s_udp} UDP"
    echo -e "${BCYAN}  ╚══════════════════════════════════════════════════╝${NC}"
    echo ""
}

main_menu() {
    while true; do
        show_header
        echo -e "  ${BWHITE}┌─────────────────────────────────────────┐${NC}"
        echo -e "  │          ${BWHITE}MENU UTAMA${NC}                      │"
        echo -e "  ${BWHITE}└─────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "  ${BGREEN}[1]${NC} Manajemen SSH"
        echo -e "  ${BGREEN}[2]${NC} Manajemen Server"
        echo -e "  ${BGREEN}[3]${NC} Informasi Server"
        echo -e "  ${BGREEN}[4]${NC} System & Services"
        echo ""
        echo -e "  ${BYELLOW}[r]${NC} Restart Semua Service"
        echo -e "  ${BRED}[0]${NC} Keluar"
        echo ""
        read -rp "  Pilihan: " choice

        case $choice in
            1) bash /etc/zv-manager/menu/ssh/menu-ssh.sh ;;
            2) bash /etc/zv-manager/menu/server/menu-server.sh ;;
            3) bash /etc/zv-manager/menu/info/server-info.sh ;;
            4) bash /etc/zv-manager/menu/system/menu-system.sh ;;
            r|R)
                for svc in ssh dropbear nginx zv-stunnel zv-wss zv-udp; do
                    systemctl restart "$svc" &>/dev/null
                done
                echo -e "  ${BGREEN}Semua service di-restart!${NC}"
                sleep 2
                ;;
            0) clear; exit 0 ;;
            *) echo -e "  ${BRED}Pilihan tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}

main_menu
