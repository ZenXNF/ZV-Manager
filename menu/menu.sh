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
        printf " \e[1;33m%-14s\e[0m = \e[1;33m%s\e[0m\n" "≥ Lisensi" "Belum dicek"
        return
    }
    local LICENSE_NAME LICENSE_DAYS_LEFT
    source "$info_file" 2>/dev/null
    local txt col
    if [[ "$LICENSE_DAYS_LEFT" -eq 99999 ]] 2>/dev/null; then
        txt="Seumur hidup"; col="\e[1;32m"
    elif [[ "$LICENSE_DAYS_LEFT" -gt 2 ]] 2>/dev/null; then
        txt="${LICENSE_DAYS_LEFT} hari lagi"; col="\e[1;32m"
    elif [[ "$LICENSE_DAYS_LEFT" -ge 0 ]] 2>/dev/null; then
        txt="${LICENSE_DAYS_LEFT} hari lagi — segera perpanjang!"; col="\e[1;33m"
    else
        txt="Habis! Segera perpanjang!"; col="\e[1;31m"
    fi
    printf " \e[1;33m%-14s\e[0m = \e[1;35m%s\e[0m · ${col}%s\e[0m\n" "≥ Lisensi" "${LICENSE_NAME:-?}" "$txt"
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
            printf " \e[1;33m%-14s\e[0m = \e[1;33m#%s\e[0m \e[1;31m→\e[0m \e[1;32m#%s\e[0m \e[1;33m⚠ Ada update! [6]\e[0m\n" "≥ Versi" "$local_hash" "$latest"
            return
        fi
    fi
    printf " \e[1;33m%-14s\e[0m = \e[1;32m#%s ✔\e[0m\n" "≥ Versi" "$local_hash"
}


# ── Gradient halus true color (kiri→kanan) ───────────────────
_grad() {
    local text="$1"
    local r1=$2 g1=$3 b1=$4 r2=$5 g2=$6 b2=$7
    local nc="\e[0m"
    local len=0
    for (( c=0; c<${#text}; c++ )); do [[ "${text:$c:1}" != " " ]] && len=$((len+1)); done
    [[ $len -le 1 ]] && len=2
    local i=0 out=""
    for (( c=0; c<${#text}; c++ )); do
        local ch="${text:$c:1}"
        if [[ "$ch" == " " ]]; then out+=" "
        else
            local r=$(( r1 + (r2-r1)*i/(len-1) ))
            local g=$(( g1 + (g2-g1)*i/(len-1) ))
            local b=$(( b1 + (b2-b1)*i/(len-1) ))
            out+="\e[1;38;2;${r};${g};${b}m${ch}${nc}"
            i=$((i+1))
        fi
    done
    echo -e "$out"
}

show_header() {
    # ── Data sistem ───────────────────────────────────────────
    local ip domain os_name isp city ram cpu uptime_str dt tm
    ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null | tr -d '[:space:]')
    [[ -z "$ip" ]] && ip=$(curl -s --max-time 5 ipv4.icanhazip.com 2>/dev/null | tr -d '[:space:]')
    domain=$(cat /etc/zv-manager/domain 2>/dev/null | tr -d '[:space:]')
    os_name=$(grep "^PRETTY_NAME=" /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "Linux")
    local _ipinfo; _ipinfo=$(curl -s --max-time 4 "https://ipinfo.io/${ip}/json" 2>/dev/null)
    isp=$(echo "$_ipinfo"  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('org','').split(' ',1)[-1])" 2>/dev/null || echo "-")
    city=$(echo "$_ipinfo" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('city','-'))" 2>/dev/null || echo "-")
    ram=$(free -m 2>/dev/null | awk '/^Mem:/{printf "%d MB", $2}')
    cpu=$(nproc 2>/dev/null || echo "?")
    uptime_str=$(uptime -p 2>/dev/null | sed 's/^up //' || echo "-")
    dt=$(TZ="Asia/Jakarta" date +"%d-%m-%Y")
    tm=$(TZ="Asia/Jakarta" date +"%H-%M-%S")

    # ── Jumlah akun ───────────────────────────────────────────
    local n_ssh=0 n_vmess=0
    for f in /etc/zv-manager/accounts/ssh/*.conf;   do [[ -f "$f" ]] && n_ssh=$((n_ssh+1));     done
    for f in /etc/zv-manager/accounts/vmess/*.conf; do [[ -f "$f" ]] && n_vmess=$((n_vmess+1)); done

    # ── Warna ─────────────────────────────────────────────────
    local R="\e[1;31m" O="\e[1;33m" G="\e[1;32m" C="\e[1;36m"
    local B="\e[1;34m" P="\e[1;35m" W="\e[1;97m" D="\e[0;37m" Y="\e[0;33m"
    local NC="\e[0m"
    local BAR="${D}$(printf '=%.0s' {1..52})${NC}"

    _dot() {
        systemctl is-active --quiet "$1" 2>/dev/null && \
            echo -e "${G}ON●${NC}" || echo -e "${R}OFF●${NC}"
    }

    clear
    # ── Banner gradient halus pink → cyan ─────────────────────
    echo -e "${D}$(printf '=%.0s' {1..52})${NC}"
    _grad " WELCOME TO ZV-MANAGER TUNNELING PANEL PREMIUM" 255 0 127  0 210 255
    echo -e "${D}$(printf '=%.0s' {1..52})${NC}"
    echo ""

    # ── Info Server ───────────────────────────────────────────
    printf " ${R}%-14s${NC} = ${W}%s${NC}\n"  "≥ System OS"  "$os_name"
    printf " ${O}%-14s${NC} = ${W}%s${NC}\n"  "≥ ISP"        "${isp:--}"
    printf " ${G}%-14s${NC} = ${W}%s${NC}\n"  "≥ City"       "${city:--}"
    printf " ${C}%-14s${NC} = ${W}%s${NC}\n"  "≥ Server RAM" "$ram"
    printf " ${B}%-14s${NC} = ${W}%s${NC}\n"  "≥ Core CPU"   "$cpu"
    printf " ${P}%-14s${NC} = ${W}%s${NC}\n"  "≥ Uptime"     "$uptime_str"
    printf " ${O}%-14s${NC} = ${W}%s${NC}\n"  "≥ Date"       "$dt"
    printf " ${Y}%-14s${NC} = ${W}%s${NC}\n"  "≥ Time"       "$tm"
    printf " ${C}%-14s${NC} = ${W}%s${NC}\n"  "≥ Domain"     "${domain:--}"
    echo ""

    # ── Info Akun ─────────────────────────────────────────────
    echo -e "${D}$(printf '=%.0s' {1..52})${NC}"
    echo -e " ${C}>>>  ${W}INFORMATION ACCOUNT ON VPS${NC}  ${C}<<<${NC}"
    echo -e "${D}$(printf '=%.0s' {1..52})${NC}"
    printf "  ${G}ACCOUNT SSH/UDP${NC}     = ${W}%s${NC}\n" "$n_ssh"
    printf "  ${C}ACCOUNT VMESS/WS${NC}    = ${W}%s${NC}\n" "$n_vmess"
    echo ""

    # ── Status Service ────────────────────────────────────────
    echo -e "${D}$(printf '=%.0s' {1..52})${NC}"
    echo -e " ${C}>>>  ${W}ZV-MANAGER TUNNELING${NC}  ${C}<<<${NC}"
    echo -e "${D}$(printf '=%.0s' {1..52})${NC}"
    printf " ${W}SSH${NC}     : %-14b ${W}NGINX${NC}   : %-14b ${W}XRAY${NC}  : %b\n" \
        "$(_dot ssh)" "$(_dot nginx)" "$(_dot zv-xray)"
    printf " ${W}WS PROXY${NC}: %-14b ${W}DROPBEAR${NC}: %-14b ${W}UDP${NC}   : %b\n" \
        "$(_dot zv-wss)" "$(_dot dropbear)" "$(_dot zv-udp)"
    printf " ${W}BOT TG${NC}  : %b\n" "$(_dot zv-telegram)"
    echo ""

    # ── Versi & Lisensi ───────────────────────────────────────
    echo -e "${D}$(printf '=%.0s' {1..52})${NC}"
    get_version_line
    get_license_display
    echo -e "${D}$(printf '=%.0s' {1..52})${NC}"
    echo ""
}

main_menu() {
    _check_version_bg

    while true; do
        show_header
        _section "MENU UTAMA"
        echo ""
        echo -e "  $(_grad '[1]' 0 210 255 160 80 255) Akun SSH             $(_grad '[2]' 0 210 255 160 80 255) Akun VMess"
        echo -e "  $(_grad '[3]' 0 210 255 160 80 255) Manajemen Server     $(_grad '[4]' 0 210 255 160 80 255) Sistem"
        echo -e "  $(_grad '[5]' 0 210 255 160 80 255) Info & Statistik     $(_grad '[6]' 0 210 255 160 80 255) Update Script"
        echo ""
        echo -e "  \e[38;2;255;200;0m[r]\e[0m Restart Semua        \e[38;2;255;80;80m[0/6]\e[0m Keluar"
        echo ""
        read -rp "  Pilihan [0-6/r]: " choice

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
