#!/bin/bash
# ============================================================
#   ZV-Manager - Menu Utama
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/config.conf

_bulan_indo() {
    case $1 in
        01) echo "Januari" ;; 02) echo "Februari" ;; 03) echo "Maret" ;;
        04) echo "April"   ;; 05) echo "Mei"       ;; 06) echo "Juni" ;;
        07) echo "Juli"    ;; 08) echo "Agustus"   ;; 09) echo "September" ;;
        10) echo "Oktober" ;; 11) echo "November"  ;; 12) echo "Desember" ;;
    esac
}

_hari_indo() {
    case $1 in
        Monday)    echo "Senin"  ;; Tuesday)  echo "Selasa" ;;
        Wednesday) echo "Rabu"   ;; Thursday) echo "Kamis"  ;;
        Friday)    echo "Jumat"  ;; Saturday) echo "Sabtu"  ;;
        Sunday)    echo "Minggu" ;;
    esac
}

_waktu_indo() {
    local hari_en tgl bulan_en tahun jam
    hari_en=$(TZ="Asia/Jakarta" date +"%A")
    tgl=$(TZ="Asia/Jakarta" date +"%d")
    bulan_en=$(TZ="Asia/Jakarta" date +"%m")
    tahun=$(TZ="Asia/Jakarta" date +"%Y")
    jam=$(TZ="Asia/Jakarta" date +"%H:%M:%S")
    echo "$(_hari_indo "$hari_en"), ${tgl} $(_bulan_indo "$bulan_en") ${tahun} — ${jam} WIB"
}

svc_status() {
    systemctl is-active --quiet "$1" 2>/dev/null && \
        echo -e "${BGREEN}●${NC}" || echo -e "${BRED}●${NC}"
}

get_license_display() {
    local info_file="/etc/zv-manager/license.info"
    [[ ! -f "$info_file" ]] && {
        echo -e "  ${BCYAN}║${NC}  ${BWHITE}Expired  :${NC} ${BYELLOW}Belum dicek${NC}"
        return
    }
    local LICENSE_NAME LICENSE_DAYS_LEFT
    source "$info_file" 2>/dev/null
    local txt col
    if [[ "$LICENSE_DAYS_LEFT" -eq 99999 ]] 2>/dev/null; then
        txt="Seumur hidup"; col="$BGREEN"
    elif [[ "$LICENSE_DAYS_LEFT" -gt 2 ]] 2>/dev/null; then
        txt="${LICENSE_DAYS_LEFT} hari lagi"; col="$BGREEN"
    elif [[ "$LICENSE_DAYS_LEFT" -ge 0 ]] 2>/dev/null; then
        txt="${LICENSE_DAYS_LEFT} hari lagi — segera perpanjang!"; col="$BYELLOW"
    else
        txt="Habis! Segera perpanjang!"; col="$BRED"
    fi
    echo -e "  ${BCYAN}║${NC}  ${BWHITE}Nama     :${NC} ${BPURPLE}${LICENSE_NAME:-?}${NC}"
    echo -e "  ${BCYAN}║${NC}  ${BWHITE}Expired  :${NC} ${col}${txt}${NC}"
}

# Baca hasil cek update dari file cache (ditulis cron, tidak blocking)
get_update_banner() {
    local cache="/tmp/zv-update-available"
    [[ ! -f "$cache" ]] && return
    local latest; latest=$(cat "$cache" 2>/dev/null | tr -d "[:space:]")
    [[ -z "$latest" || "$latest" == "$COMMIT_HASH" ]] && return
    echo -e "${BYELLOW}  ╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${BYELLOW}  ║${NC}  ${BRED}⚠  Update tersedia:${NC} ${BWHITE}#${COMMIT_HASH}${NC} ${BYELLOW}→${NC} ${BGREEN}#${latest}${NC}   ${BYELLOW}Pilih [6]${NC}  ${BYELLOW}║${NC}"
    echo -e "${BYELLOW}  ╚══════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_header() {
    local ip today
    ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null || curl -s --max-time 5 ipv4.icanhazip.com)
    today=$(_waktu_indo)

    local s_ssh s_db s_ng s_wss s_udp s_ssl s_xray
    s_ssh=$(svc_status ssh); s_db=$(svc_status dropbear)
    s_ng=$(svc_status nginx); s_wss=$(svc_status zv-wss)
    s_udp=$(svc_status zv-udp)
    # SSL sekarang dihandle nginx port 443, bukan stunnel
    ss -tlnp 2>/dev/null | grep -q ":443 " && s_ssl="${BGREEN}●${NC}" || s_ssl="${BRED}●${NC}"
    s_xray=$(svc_status zv-xray)

    clear
    get_update_banner
    echo -e "${BCYAN}  ╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${BCYAN}  ║${NC}  ${BWHITE}ZV-Manager${NC} ${BYELLOW}#${COMMIT_HASH:-unknown}${NC}                                ${BCYAN}║${NC}"
    echo -e "${BCYAN}  ╠══════════════════════════════════════════════════╣${NC}"
    echo -e "${BCYAN}  ║${NC}  ${BWHITE}IP    :${NC} ${BGREEN}${ip}${NC}"
    echo -e "${BCYAN}  ║${NC}  ${BWHITE}Waktu :${NC} ${BYELLOW}${today}${NC}"
    echo -e "${BCYAN}  ╠══════════════════════════════════════════════════╣${NC}"
    get_license_display
    echo -e "${BCYAN}  ╠══════════════════════════════════════════════════╣${NC}"
    echo -e "${BCYAN}  ║${NC}  ${s_ssh} SSH  ${s_db} Dropbear  ${s_ng} Nginx  ${s_ssl} SSL  ${s_wss} WS  ${s_udp} UDP  ${s_xray} Xray"
    echo -e "${BCYAN}  ╚══════════════════════════════════════════════════╝${NC}"
    echo ""
}

main_menu() {
    while true; do
        show_header
        echo -e "  ${BCYAN}┌──────────────────────────────────────────────┐${NC}"
        echo -e "  │                 ${BWHITE}MENU UTAMA${NC}                   │"
        echo -e "  ${BCYAN}└──────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "  ${BGREEN}[1]${NC} Manajemen SSH        ${BGREEN}[2]${NC} Manajemen Server"
        echo -e "  ${BGREEN}[3]${NC} Informasi Server     ${BGREEN}[4]${NC} System & Services"
        echo -e "  ${BGREEN}[5]${NC} Statistik Penjualan  ${BGREEN}[6]${NC} Update Script"
        echo -e "  ${BGREEN}[7]${NC} Manajemen VMess"
        echo ""
        echo -e "  ${BYELLOW}[r]${NC} Restart Services     ${BRED}[0]${NC} Keluar"
        echo ""
        read -rp "  Pilihan: " choice

        case $choice in
            1) bash /etc/zv-manager/menu/ssh/menu-ssh.sh ;;
            2) bash /etc/zv-manager/menu/server/menu-server.sh ;;
            3) bash /etc/zv-manager/menu/info/server-info.sh ;;
            4) bash /etc/zv-manager/menu/system/menu-system.sh ;;
            5) bash /etc/zv-manager/menu/info/statistik.sh ;;
            7) bash /etc/zv-manager/menu/vmess/menu-vmess.sh ;;
            6)
                echo ""
                echo -e "  ${BYELLOW}Menjalankan update...${NC}"
                echo ""
                bash /etc/zv-manager/update.sh
                # Hapus cache update setelah update selesai
                rm -f /tmp/zv-update-available
                echo ""
                read -rp "  Tekan Enter untuk kembali ke menu..." _
                # Reload config (versi baru)
                source /etc/zv-manager/config.conf 2>/dev/null
                ;;
            r|R)
                for svc in ssh dropbear nginx zv-wss zv-udp zv-xray; do
                    systemctl restart "$svc" &>/dev/null
                done
                echo -e "  ${BGREEN}Semua service di-restart!${NC}"; sleep 2 ;;
            0) clear; exit 0 ;;
            *) echo -e "  ${BRED}Pilihan tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}

main_menu
