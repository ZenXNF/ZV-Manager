#!/bin/bash
# ============================================================
#   ZV-Manager — Uninstaller
# ============================================================

[[ "$EUID" -ne 0 ]] && { echo "  [!] Jalankan sebagai root!"; exit 1; }

SILENT=false
[[ "$1" == "--silent" ]] && SILENT=true

LOG="/tmp/zv-uninstall.log"
touch "$LOG" 2>/dev/null
_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG" 2>/dev/null; }

_TOTAL=7
_CUR=0

G="\e[1;32m" R="\e[1;31m" O="\e[1;33m" C="\e[1;36m"
W="\e[1;97m" D="\e[0;37m" NC="\e[0m"

_grad() {
    local text="$1" r1=$2 g1=$3 b1=$4 r2=$5 g2=$6 b2=$7 nc="\e[0m"
    local len=0
    for (( c=0; c<${#text}; c++ )); do [[ "${text:$c:1}" != " " ]] && len=$((len+1)); done
    [[ $len -le 1 ]] && len=2
    local i=0 out=""
    for (( c=0; c<${#text}; c++ )); do
        local ch="${text:$c:1}"
        if [[ "$ch" == " " ]]; then out+=" "
        else
            local r=$(( r1+(r2-r1)*i/(len-1) )) g=$(( g1+(g2-g1)*i/(len-1) )) b=$(( b1+(b2-b1)*i/(len-1) ))
            out+="\e[1;38;2;${r};${g};${b}m${ch}${nc}"; i=$((i+1))
        fi
    done
    echo -e "$out"
}

_sep() { _grad "$(printf '=%.0s' {1..50})" 0 180 255 120 0 255; }

_run() {
    local label="$1" ok="$2"; shift 2
    _CUR=$(( _CUR + 1 ))
    local pct=$(( _CUR * 100 / _TOTAL ))
    local filled=$(( pct / 5 )) empty=$(( 20 - pct/5 ))
    local bar=""
    for (( i=0; i<filled; i++ )); do bar+="█"; done
    for (( i=0; i<empty; i++ )); do bar+="░"; done
    printf "\r  ${C}[${bar}]${NC} ${W}%3d%%${NC} ${D}%s${NC}...\r" "$pct" "$label"
    if "$@" >> "$LOG" 2>&1; then
        printf "\r\033[K"
        printf "  ${C}[${bar}]${NC} ${W}%3d%%${NC}  ${G}✔${NC}  ${W}%-28s${NC}  ${D}%s${NC}\n" "$pct" "$label" "$ok"
    else
        printf "\r\033[K"
        printf "  ${R}✘${NC}  ${W}%-35s${NC}  ${R}gagal${NC}\n" "$label"
    fi
}

# ── Konfirmasi ────────────────────────────────────────────────
if [[ "$SILENT" == false ]]; then
    clear
    _sep
    _grad " ⚠  UNINSTALL ZV-MANAGER  ⚠" 255 0 0 255 100 0
    _sep
    echo ""
    echo -e "  ${R}Semua komponen ZV-Manager akan dihapus!${NC}"
    echo -e "  ${D}Akun SSH, VMess, config, dan data akan hilang permanen.${NC}"
    echo ""
    echo -e "  ${R}[y]${NC} Lanjutkan uninstall"
    echo -e "  ${D}[n]${NC} Batal"
    echo ""
    read -rp "  Ketik 'y' untuk konfirmasi: " _conf
    [[ "$_conf" != "y" && "$_conf" != "Y" ]] && { echo "  Dibatalkan."; exit 0; }
    echo ""
fi

_log "====== MULAI UNINSTALL ZV-MANAGER ======"

_sep
_grad " MENGHAPUS ZV-MANAGER" 255 50 50 255 150 0
_sep
echo ""

# ── Hapus akun SSH ────────────────────────────────────────────
_run "Hapus akun SSH" "selesai" bash -c '
    if [[ -d "/etc/zv-manager/accounts/ssh" ]]; then
        for conf_file in /etc/zv-manager/accounts/ssh/*.conf; do
            [[ -f "$conf_file" ]] || continue
            username=$(grep "^USERNAME=" "$conf_file" | cut -d= -f2 | tr -d '\''"'\'')
            [[ -n "$username" ]] && pkill -u "$username" 2>/dev/null; sleep 0.2; userdel -r "$username" 2>/dev/null
        done
    fi
'

# ── Stop service ─────────────────────────────────────────────
_run "Stop semua service" "selesai" bash -c '
    for svc in zv-telegram zv-xray zv-wss zv-stunnel zv-udp zv-ws zv-badvpn; do
        systemctl stop "$svc" 2>/dev/null
        systemctl disable "$svc" 2>/dev/null
    done
    for f in /etc/systemd/system/zv-*.service; do [[ -f "$f" ]] && rm -f "$f"; done
    systemctl daemon-reload 2>/dev/null
'

# ── Hapus packages ────────────────────────────────────────────
_run "Hapus packages" "nginx, dropbear dihapus" bash -c '
    DEBIAN_FRONTEND=noninteractive apt-get purge -y nginx nginx-common nginx-core stunnel4 dropbear 2>/dev/null
    apt-get autoremove -y 2>/dev/null
'

# ── Restore sshd_config ───────────────────────────────────────
_run "Restore OpenSSH config" "selesai" bash -c '
    SSHD_CONFIG="/etc/ssh/sshd_config"
    BACKUP=$(ls -1t /etc/ssh/sshd_config.bak.* 2>/dev/null | head -1)
    if [[ -n "$BACKUP" ]]; then
        cp "$BACKUP" "$SSHD_CONFIG"
    else
        printf "%s\n" \
            "Include /etc/ssh/sshd_config.d/*.conf" \
            "Port 22" \
            "PermitRootLogin yes" \
            "PasswordAuthentication yes" \
            "PubkeyAuthentication yes" \
            "PrintMotd no" \
            "AcceptEnv LANG LC_*" \
            "Subsystem sftp /usr/lib/openssh/sftp-server" > "$SSHD_CONFIG"
    fi
    sed -i "/^Port 500$/d;/^Port 40000$/d;/^Banner/d" "$SSHD_CONFIG"
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
'

# ── Hapus cron & PAM ─────────────────────────────────────────
_run "Hapus cron & PAM" "selesai" bash -c '
    for f in /etc/cron.d/zv-*; do [[ -f "$f" ]] && rm -f "$f"; done
    service cron restart 2>/dev/null
    sed -i "/bw-session.sh/d" /etc/pam.d/sshd 2>/dev/null
    echo "Ubuntu 24.04.2 LTS" > /etc/issue.net
    rm -f /etc/update-motd.d/00-zv-manager
    rm -f /etc/stunnel/zv-wss.conf
'

# ── Hapus binary ─────────────────────────────────────────────
_run "Hapus binary & symlink" "selesai" bash -c '
    rm -f /usr/local/bin/menu /usr/local/bin/zv-agent /usr/local/bin/zv-vmess-agent
    rm -f /usr/local/bin/zv-ws-proxy.py /usr/local/bin/badvpn-udpgw /usr/local/bin/xray
'

# ── Hapus file config ─────────────────────────────────────────
_run "Hapus semua file ZV-Manager" "selesai" bash -c '
    for bak in /etc/ssh/sshd_config.bak.*; do [[ -f "$bak" ]] && rm -f "$bak"; done
    rm -rf /etc/zv-manager /var/backups/zv-manager /root/ZV-Manager
    rm -rf /usr/local/etc/xray /var/www/zv-manager /var/log/zv-manager /opt/zv-telegram
'

_log "====== UNINSTALL SELESAI ======"

# ── .profile ─────────────────────────────────────────────────
if [[ "$SILENT" == true ]]; then
    tee /root/.profile > /dev/null << 'NOTIF'
if [ "$BASH" ]; then if [ -f ~/.bashrc ]; then . ~/.bashrc; fi; fi
mesg n 2>/dev/null || true
case $- in *i*) ;; *) return ;; esac
[ -t 1 ] || return; [ -z "$SSH_TTY" ] && return
[ -n "$SSH_ORIGINAL_COMMAND" ] && return
clear
echo ""
echo "  ====================================="
echo "  |   IZIN VPS TELAH BERAKHIR         |"
echo "  ====================================="
echo ""
echo "  Hubungi: @ZenXNF / t.me/ZenXNF"
echo ""
NOTIF
else
    tee /root/.profile > /dev/null << 'DEFPROF'
if [ "$BASH" ]; then if [ -f ~/.bashrc ]; then . ~/.bashrc; fi; fi
mesg n 2>/dev/null || true
DEFPROF
fi

rm -f "$0"

# ── Selesai ───────────────────────────────────────────────────
if [[ "$SILENT" == false ]] && [ -t 1 ]; then
    echo ""
    _sep
    _grad " UNINSTALL SELESAI" 0 210 255 160 80 255
    _sep
    echo ""
    printf "  \e[1;32m+\e[0m  Semua komponen ZV-Manager telah dihapus.\n"
    printf "  \e[1;32m+\e[0m  VPS sudah kembali bersih.\n"
    echo ""
    printf "  \e[1;36mPasang lagi:\e[0m\n"
    echo    "  wget -qO- https://raw.githubusercontent.com/ZenXNF/ZV-Manager/main/zv.sh | bash"
    echo ""
fi

exit 0
