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
    local h tgl b th j
    h=$(TZ="Asia/Jakarta" date +"%A"); tgl=$(TZ="Asia/Jakarta" date +"%d")
    b=$(TZ="Asia/Jakarta" date +"%m"); th=$(TZ="Asia/Jakarta" date +"%Y")
    j=$(TZ="Asia/Jakarta" date +"%H:%M:%S")
    echo "$(_hari_indo "$h"), ${tgl} $(_bulan_indo "$b") ${th} — ${j} WIB"
}

svc_dot() {
    systemctl is-active --quiet "$1" 2>/dev/null && \
        echo -e "${BGREEN}●${NC}" || echo -e "${BRED}●${NC}"
}

get_license_display() {
    local info_file="/etc/zv-manager/license.info"
    [[ ! -f "$info_file" ]] && {
        echo -e "  ${BCYAN}║${NC}  ${BWHITE}Lisensi  :${NC} ${BYELLOW}Belum dicek${NC}"
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
    echo -e "  ${BCYAN}║${NC}  ${BWHITE}Lisensi  :${NC} ${BPURPLE}${LICENSE_NAME:-?}${NC} ${BWHITE}·${NC} ${col}${txt}${NC}"
}

# Cek versi GitHub di background (non-blocking)
_check_version_bg() {
    (
        local latest
        latest=$(curl -sf --max-time 8 \
            "https://api.github.com/repos/ZenXNF/ZV-Manager/commits/main" 2>/dev/null \
            | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['sha'][:7])" 2>/dev/null)
        [[ -z "$latest" ]] && return
        if [[ "$latest" != "$COMMIT_HASH" ]]; then
            echo "$latest" > /tmp/zv-update-available
        else
            rm -f /tmp/zv-update-available
        fi
    ) &>/dev/null &
}

get_version_line() {
    local local_hash="${COMMIT_HASH:-unknown}"
    local cache="/tmp/zv-update-available"
    if [[ -f "$cache" ]]; then
        local latest; latest=$(cat "$cache" 2>/dev/null | tr -d "[:space:]")
        if [[ -n "$latest" && "$latest" != "$local_hash" ]]; then
            echo -e "  ${BCYAN}║${NC}  ${BWHITE}Versi    :${NC} ${BYELLOW}#${local_hash}${NC} ${BRED}→${NC} ${BGREEN}#${latest}${NC} ${BYELLOW}⚠ Ada update!${NC} ${BWHITE}[6]${NC}"
            return
        fi
    fi
    echo -e "  ${BCYAN}║${NC}  ${BWHITE}Versi    :${NC} ${BGREEN}#${local_hash} ✔${NC}"
}

show_header() {
    local ip today
    ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null || curl -s --max-time 5 ipv4.icanhazip.com)
    today=$(_waktu_indo)

    local s_ssh s_db s_ng s_ssl s_wss s_udp s_xray s_bot
    s_ssh=$(svc_dot ssh); s_db=$(svc_dot dropbear); s_ng=$(svc_dot nginx)
    ss -tlnp 2>/dev/null | grep -q ":443 " && s_ssl="${BGREEN}●${NC}" || s_ssl="${BRED}●${NC}"
    s_wss=$(svc_dot zv-wss); s_udp=$(svc_dot zv-udp)
    s_xray=$(svc_dot zv-xray); s_bot=$(svc_dot zv-telegram)

    clear
    echo -e "${BCYAN}  ╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${BCYAN}  ║${NC}  ${BPURPLE}ZV-Manager${NC}                                        ${BCYAN}║${NC}"
    echo -e "${BCYAN}  ╠══════════════════════════════════════════════════╣${NC}"
    echo -e "  ${BCYAN}║${NC}  ${BWHITE}IP       :${NC} ${BGREEN}${ip}${NC}"
    echo -e "  ${BCYAN}║${NC}  ${BWHITE}Waktu    :${NC} ${BYELLOW}${today}${NC}"
    get_version_line
    get_license_display
    echo -e "${BCYAN}  ╠══════════════════════════════════════════════════╣${NC}"
    echo -e "  ${BCYAN}║${NC}  ${s_ssh} SSH  ${s_db} Dropbear  ${s_ng} Nginx  ${s_ssl} SSL"
    echo -e "  ${BCYAN}║${NC}  ${s_wss} WS   ${s_udp} UDP       ${s_xray} Xray  ${s_bot} Bot"
    echo -e "${BCYAN}  ╚══════════════════════════════════════════════════╝${NC}"
    echo ""
}

main_menu() {
    _check_version_bg

    while true; do
        show_header
        echo -e "  ${BCYAN}┌──────────────────────────────────────────────┐${NC}"
        echo -e "  │                 ${BWHITE}MENU UTAMA${NC}                   │"
        echo -e "  ${BCYAN}└──────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "  ${BGREEN}[1]${NC} Akun SSH             ${BGREEN}[2]${NC} Akun VMess"
        echo -e "  ${BGREEN}[3]${NC} Manajemen Server     ${BGREEN}[4]${NC} Sistem"
        echo -e "  ${BGREEN}[5]${NC} Info & Statistik     ${BGREEN}[6]${NC} Update Script"
        echo ""
        echo -e "  ${BYELLOW}[r]${NC} Restart Semua        ${BRED}[0]${NC} Keluar"
        echo ""
        read -rp "  Pilihan: " choice

        case $choice in
            1) bash /etc/zv-manager/menu/ssh/menu-ssh.sh ;;
            2) bash /etc/zv-manager/menu/vmess/menu-vmess.sh ;;
            3) bash /etc/zv-manager/menu/server/menu-server.sh ;;
            4) bash /etc/zv-manager/menu/system/menu-system.sh ;;
            5) bash /etc/zv-manager/menu/info/menu-info.sh ;;
            6)
                echo ""
                echo -e "  ${BYELLOW}Menjalankan update...${NC}"
                echo ""
                bash /etc/zv-manager/update.sh
                rm -f /tmp/zv-update-available
                echo ""
                read -rp "  Tekan Enter untuk kembali ke menu..." _
                source /etc/zv-manager/config.conf 2>/dev/null
                ;;
            r|R)
                echo ""
                echo -e "  ${BYELLOW}Merestart semua service...${NC}"
                for svc in ssh dropbear nginx zv-wss zv-udp zv-xray zv-telegram; do
                    systemctl restart "$svc" &>/dev/null && \
                        echo -e "  ${BGREEN}✔${NC} ${svc}" || \
                        echo -e "  ${BRED}✘${NC} ${svc}"
                done
                echo ""
                read -rp "  Tekan Enter untuk kembali..." _
                ;;
            0) clear; exit 0 ;;
            *) echo -e "  ${BRED}Pilihan tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}

main_menu
