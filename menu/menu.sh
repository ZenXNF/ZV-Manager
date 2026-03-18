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
        printf "  \033[38;5;226m%-12s\033[0m : \033[1;97m%s\033[0m\n" "Lisensi" "Belum dicek"
        return
    }
    local LICENSE_NAME LICENSE_DAYS_LEFT
    source "$info_file" 2>/dev/null
    local txt col
    if [[ "$LICENSE_DAYS_LEFT" -eq 99999 ]] 2>/dev/null; then
        txt="Seumur hidup"; col="\033[38;5;46m"
    elif [[ "$LICENSE_DAYS_LEFT" -gt 2 ]] 2>/dev/null; then
        txt="${LICENSE_DAYS_LEFT} hari lagi"; col="\033[38;5;46m"
    elif [[ "$LICENSE_DAYS_LEFT" -ge 0 ]] 2>/dev/null; then
        txt="${LICENSE_DAYS_LEFT} hari lagi — segera perpanjang!"; col="\033[38;5;226m"
    else
        txt="Habis! Segera perpanjang!"; col="\033[38;5;196m"
    fi
    printf "  \033[38;5;226m%-12s\033[0m : \033[38;5;129m%s\033[0m · ${col}%s\033[0m\n" "Lisensi" "${LICENSE_NAME:-?}" "$txt"
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
            printf "  \033[38;5;226m%-12s\033[0m : \033[38;5;226m#%s\033[0m \033[38;5;196m→\033[0m \033[38;5;46m#%s\033[0m \033[38;5;226m⚠ Ada update! [6]\033[0m\n" "Versi" "$local_hash" "$latest"
            return
        fi
    fi
    printf "  \033[38;5;226m%-12s\033[0m : \033[38;5;46m#%s ✔\033[0m\n" "Versi" "$local_hash"
}

show_header() {
    # ── Data sistem ───────────────────────────────────────────
    local ip domain os_name isp ram cpu uptime_str today
    ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null | tr -d '[:space:]')
    [[ -z "$ip" ]] && ip=$(curl -s --max-time 5 ipv4.icanhazip.com 2>/dev/null | tr -d '[:space:]')
    domain=$(cat /etc/zv-manager/domain 2>/dev/null | tr -d '[:space:]')
    os_name=$(grep "^PRETTY_NAME=" /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "Linux")
    isp=$(curl -s --max-time 4 "https://ipinfo.io/${ip}/org" 2>/dev/null | sed 's/^AS[0-9]* //' || echo "-")
    ram=$(free -m 2>/dev/null | awk '/^Mem:/{printf "%d MB", $2}')
    cpu=$(nproc 2>/dev/null || echo "?")
    uptime_str=$(uptime -p 2>/dev/null | sed 's/^up //' || echo "-")
    today=$(_waktu_indo)

    # ── Jumlah akun ───────────────────────────────────────────
    local n_ssh=0 n_vmess=0
    for f in /etc/zv-manager/accounts/ssh/*.conf;   do [[ -f "$f" ]] && n_ssh=$((n_ssh+1));     done
    for f in /etc/zv-manager/accounts/vmess/*.conf; do [[ -f "$f" ]] && n_vmess=$((n_vmess+1)); done

    # ── Warna ─────────────────────────────────────────────────
    local R="\e[1;31m" O="\e[1;33m" G="\e[1;32m" C="\e[1;36m"
    local B="\e[1;34m" P="\e[1;35m" W="\e[1;97m" D="\e[0;37m"
    local NC="\e[0m"
    local LINE="${D}----------------------------------------------------${NC}"

    _svc_txt() {
        systemctl is-active --quiet "$1" 2>/dev/null && \
            echo -e "${G}ON${NC}" || echo -e "${R}OFF${NC}"
    }

    clear
    # ── Banner ────────────────────────────────────────────────
    echo -e "${R}  __   ____${O}     __   __${G}  ____${C}   __  __${P}   __  __ ${NC}"
    echo -e "${R} |   \  / |${O}    \ \ / /${G} |    \${C} |  \/  |${P}  |  \/  |${NC}"
    echo -e "${R} | |\ \/ /|${O}     \ V / ${G} | || |${C} | |\/| |${P}  | |\/| |${NC}"
    echo -e "${R} |_| \__/ |${O}      \_/  ${G} |____/${C} |_|  |_|${P}  |_|  |_|${NC}"
    echo -e "  ${D}ZV-Manager — SSH & VMess Tunneling Panel${NC}"
    echo -e "  $LINE"

    # ── Info Server ───────────────────────────────────────────
    echo -e "  ${C}>> ${W}INFORMASI SERVER${NC}"
    echo -e "  $LINE"
    printf "  ${G}%-10s${NC} : ${W}%s${NC}\n"       "OS"     "$os_name"
    printf "  ${G}%-10s${NC} : ${W}%s${NC}\n"       "IP"     "$ip"
    printf "  ${G}%-10s${NC} : ${W}%s${NC}\n"       "Domain" "${domain:--}"
    printf "  ${G}%-10s${NC} : ${W}%s${NC}\n"       "ISP"    "${isp:--}"
    printf "  ${G}%-10s${NC} : ${W}%s${NC}\n"       "RAM"    "$ram"
    printf "  ${G}%-10s${NC} : ${W}%s vCore${NC}\n" "CPU"    "$cpu"
    printf "  ${G}%-10s${NC} : ${W}%s${NC}\n"       "Uptime" "$uptime_str"
    printf "  ${G}%-10s${NC} : ${W}%s${NC}\n"       "Waktu"  "$today"
    echo -e "  $LINE"

    # ── Info Akun ─────────────────────────────────────────────
    echo -e "  ${O}>> ${W}INFORMASI AKUN${NC}"
    echo -e "  $LINE"
    printf "  ${O}%-10s${NC} : ${W}%s akun${NC}\n" "SSH"   "$n_ssh"
    printf "  ${O}%-10s${NC} : ${W}%s akun${NC}\n" "VMess" "$n_vmess"
    echo -e "  $LINE"

    # ── Status Service ────────────────────────────────────────
    echo -e "  ${C}>> ${W}STATUS SERVICE${NC}"
    echo -e "  $LINE"
    printf "  ${D}SSH${NC}     : %-12b  ${D}Nginx${NC}   : %-12b  ${D}Xray${NC} : %b\n" \
        "$(_svc_txt ssh)" "$(_svc_txt nginx)" "$(_svc_txt zv-xray)"
    printf "  ${D}Dropbear${NC}: %-12b  ${D}WS Proxy${NC}: %-12b  ${D}UDP${NC}  : %b\n" \
        "$(_svc_txt dropbear)" "$(_svc_txt zv-wss)" "$(_svc_txt zv-udp)"
    printf "  ${D}Bot TG${NC}  : %b\n" "$(_svc_txt zv-telegram)"
    echo -e "  $LINE"

    # ── Versi & Lisensi ───────────────────────────────────────
    get_version_line
    get_license_display
    echo -e "  $LINE"
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
