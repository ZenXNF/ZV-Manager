#!/bin/bash
# ============================================================
#   ZV-Manager — Uninstaller
#   Mengembalikan VPS ke kondisi bersih
#
#   Penggunaan:
#     bash uninstall.sh           → interaktif
#     bash uninstall.sh --silent  → otomatis (dari cron/license)
# ============================================================

if [[ "$EUID" -ne 0 ]]; then
    echo "  [!] Jalankan sebagai root!"
    exit 1
fi

SILENT=false
[[ "$1" == "--silent" ]] && SILENT=true

LOG="/tmp/zv-uninstall.log"
touch "$LOG" 2>/dev/null

_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG" 2>/dev/null; }

# ── Helpers output ────────────────────────────────────────────
_step_un() {
    # Jalankan langkah dengan spinner 1 baris
    local name="$1" ok_msg="$2"; shift 2
    printf "  \033[33m>\033[0m  %-38s\r" "$name"
    if "$@" >> "$LOG" 2>&1; then
        printf "\033[2K"
        printf "  \033[32m+\033[0m  \033[1m%-35s\033[0m  %s\n" "$name" "$ok_msg"
    else
        printf "\033[2K"
        printf "  \033[31m!\033[0m  \033[1m%-35s\033[0m  \033[31mgagal\033[0m\n" "$name"
    fi
}

_done_un() {
    printf "  \033[32m+\033[0m  \033[1m%-35s\033[0m  %s\n" "$1" "$2"
}

_skip_un() {
    printf "  \033[33m-\033[0m  \033[1m%-35s\033[0m  \033[33m%s\033[0m\n" "$1" "$2"
}

# ── Konfirmasi (mode manual) ───────────────────────────────────
if [[ "$SILENT" == false ]]; then
    clear
    printf "\033[1;31m"
    echo "  ╔══════════════════════════════════════╗"
    echo "  ║    ⚠   UNINSTALL ZV-MANAGER  ⚠      ║"
    echo "  ╚══════════════════════════════════════╝"
    printf "\033[0m\n"
    echo "  Menghapus semua komponen ZV-Manager..."
    echo ""
fi

_log "====== MULAI UNINSTALL ZV-MANAGER ======"

# ── Langkah 1: Hapus akun SSH ─────────────────────────────────
echo -e "\033[33m  ──────────────────────────────────────\033[0m"
echo -e "  \033[1mMenghapus Data\033[0m"
echo -e "\033[33m  ──────────────────────────────────────\033[0m"
echo ""

_step_un "Hapus akun SSH" "selesai" bash -c '
    if [[ -d "/etc/zv-manager/accounts/ssh" ]]; then
        for conf_file in /etc/zv-manager/accounts/ssh/*.conf; do
            [[ -f "$conf_file" ]] || continue
            username=""
            while IFS="=" read -r key val; do
                [[ "$key" == "USERNAME" ]] && username="$val"
            done < "$conf_file"
            if [[ -n "$username" ]]; then
                pkill -u "$username" 2>/dev/null
                sleep 0.2
                userdel -r "$username" 2>/dev/null
            fi
        done
    fi
'

# ── Langkah 2: Stop service ───────────────────────────────────
_step_un "Stop service ZV-Manager" "selesai" bash -c '
    for svc in zv-telegram zv-xray zv-wss zv-stunnel zv-udp zv-ws zv-badvpn; do
        systemctl stop "$svc" 2>/dev/null
        systemctl disable "$svc" 2>/dev/null
    done
    for f in /etc/systemd/system/zv-*.service; do
        [[ -f "$f" ]] && rm -f "$f"
    done
    systemctl daemon-reload 2>/dev/null
'

# ── Langkah 3: Hapus packages ────────────────────────────────
_step_un "Hapus packages" "nginx, stunnel4, dropbear dihapus" bash -c '
    DEBIAN_FRONTEND=noninteractive apt-get purge -y \
        nginx nginx-common nginx-core stunnel4 dropbear 2>/dev/null
    apt-get autoremove -y 2>/dev/null
'

echo ""
echo -e "\033[33m  ──────────────────────────────────────\033[0m"
echo -e "  \033[1mRestore Konfigurasi Sistem\033[0m"
echo -e "\033[33m  ──────────────────────────────────────\033[0m"
echo ""

# ── Langkah 4: Restore sshd_config ────────────────────────────
_step_un "Restore OpenSSH config" "selesai" bash -c '
    SSHD_CONFIG="/etc/ssh/sshd_config"
    BACKUP=$(ls -1t /etc/ssh/sshd_config.bak.* 2>/dev/null | head -1)
    if [[ -n "$BACKUP" ]]; then
        cp "$BACKUP" "$SSHD_CONFIG"
    else
        cat > "$SSHD_CONFIG" <<'"'"'SSHDEOF'"'"'
# sshd_config — default Ubuntu 24.04
Include /etc/ssh/sshd_config.d/*.conf
Port 22
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
SSHDEOF
    fi
    sed -i "/^Port 500$/d;/^Port 40000$/d;/^Banner/d" "$SSHD_CONFIG"
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
'

# ── Langkah 5: Restore file sistem ───────────────────────────
_step_un "Restore file sistem" "selesai" bash -c '
    echo "Ubuntu 24.04.2 LTS" > /etc/issue.net
    rm -f /etc/update-motd.d/00-zv-manager
    for f in /etc/update-motd.d/*; do [[ -f "$f" ]] && chmod +x "$f"; done
    rm -f /etc/stunnel/zv-wss.conf
'

# ── Langkah 6: Hapus cron & PAM ──────────────────────────────
_step_un "Hapus cron jobs" "selesai" bash -c '
    for f in /etc/cron.d/zv-*; do [[ -f "$f" ]] && rm -f "$f"; done
    service cron restart 2>/dev/null
'

_step_un "Bersihkan PAM sshd" "selesai" bash -c '
    sed -i "/bw-session.sh/d" /etc/pam.d/sshd 2>/dev/null
'

echo ""
echo -e "\033[33m  ──────────────────────────────────────\033[0m"
echo -e "  \033[1mHapus File ZV-Manager\033[0m"
echo -e "\033[33m  ──────────────────────────────────────\033[0m"
echo ""

# ── Langkah 7: Hapus file ZV-Manager ─────────────────────────
_step_un "Hapus binary & symlink" "selesai" bash -c '
    rm -f /usr/local/bin/menu
    rm -f /usr/local/bin/zv-agent
    rm -f /usr/local/bin/zv-vmess-agent
    rm -f /usr/local/bin/zv-ws-proxy.py
    rm -f /usr/local/bin/badvpn-udpgw
    rm -f /usr/local/bin/xray
    rm -f /usr/local/bin/badvpn-udpgw
'

_step_un "Hapus Xray" "selesai" bash -c '
    rm -rf /usr/local/etc/xray
    rm -rf /var/www/zv-manager
    rm -rf /var/log/zv-manager
'

_step_un "Hapus file config" "selesai" bash -c '
    for bak in /etc/ssh/sshd_config.bak.*; do [[ -f "$bak" ]] && rm -f "$bak"; done
    rm -rf /etc/zv-manager
    rm -rf /var/backups/zv-manager
    rm -rf /root/ZV-Manager
'

_log "====== UNINSTALL SELESAI ======"

# ── .profile ─────────────────────────────────────────────────
if [[ "$SILENT" == true ]]; then
    cat > /root/.profile <<'NOTIFEOF'
# ZV-Manager Expired Notification
if [ "$BASH" ]; then if [ -f ~/.bashrc ]; then . ~/.bashrc; fi; fi
mesg n 2>/dev/null || true
case $- in *i*) ;; *) return ;; esac
[ -t 1 ] || return; [ -z "$SSH_TTY" ] && return
[ -n "$SSH_ORIGINAL_COMMAND" ] && return
clear
printf "\033[1;31m"
echo "  ╔══════════════════════════════════════╗"
echo "  ║    ⚠   IZIN VPS TELAH BERAKHIR  ⚠   ║"
echo "  ╚══════════════════════════════════════╝"
printf "\033[0m\n"
echo "  Izin ZV-Manager telah berakhir."
echo "  Semua konfigurasi & akun SSH telah dihapus."
echo ""
echo -e "  \033[1;33m[1]\033[0m  Hapus semua & kembalikan ke default"
echo -e "  \033[1;32m[2]\033[0m  Perpanjang lisensi  →  t.me/ZenXNF"
echo -e "  \033[1;37m[0]\033[0m  Keluar"
echo ""
while true; do
    read -rp "  Pilihan: " _zvp
    case $_zvp in
        1)
            rm -f /root/zv.sh 2>/dev/null
            cat > /root/.profile <<'DEF'
if [ "$BASH" ]; then if [ -f ~/.bashrc ]; then . ~/.bashrc; fi; fi
mesg n 2>/dev/null || true
DEF
            echo -e "\n  \033[1;32mVPS berhasil dikembalikan ke default.\033[0m\n"
            break ;;
        2)
            echo -e "\n  \033[1;36mHubungi: @ZenXNF / t.me/ZenXNF\033[0m\n"
            break ;;
        0) echo ""; break ;;
        *) echo -e "  \033[1;31mPilihan tidak valid!\033[0m" ;;
    esac
done
NOTIFEOF
else
    cat > /root/.profile <<'PROFILEOF'
if [ "$BASH" ]; then if [ -f ~/.bashrc ]; then . ~/.bashrc; fi; fi
mesg n 2>/dev/null || true
PROFILEOF
fi

# ── Self-delete ───────────────────────────────────────────────
rm -f "$0"

# ── Tampilan akhir (mode manual) ──────────────────────────────
if [[ "$SILENT" == false ]] && [ -t 1 ]; then
    echo ""
    printf "\033[1;32m"
    echo "  ╔══════════════════════════════════════╗"
    echo "  ║    ✔   UNINSTALL SELESAI             ║"
    echo "  ╚══════════════════════════════════════╝"
    printf "\033[0m\n"
    echo "  Semua komponen ZV-Manager telah dihapus."
    echo "  VPS sudah kembali bersih."
    echo ""
    echo -e "  \033[1;33m[1]\033[0m  Hapus file sisa (zv.sh)"
    echo -e "  \033[1;32m[2]\033[0m  Pasang lagi  →  t.me/ZenXNF"
    echo -e "  \033[1;37m[0]\033[0m  Keluar"
    echo ""
    while true; do
        read -rp "  Pilihan: " pilihan
        case $pilihan in
            1)
                rm -f /root/zv.sh /usr/local/bin/zv 2>/dev/null
                cat > /root/.profile <<'DEFPROFILE'
if [ "$BASH" ]; then if [ -f ~/.bashrc ]; then . ~/.bashrc; fi; fi
mesg n 2>/dev/null || true
DEFPROFILE
                echo -e "\n  \033[1;32mFile sisa berhasil dihapus.\033[0m\n"
                echo -e "  Sesi ini akan ditutup.\n"
                sleep 1
                # Kill seluruh process group + sesi SSH
                kill -9 0 2>/dev/null
                exit 0 ;;
            2)
                echo -e "\n  \033[1;36mHubungi: @ZenXNF / t.me/ZenXNF\033[0m"
                echo -e "  bash <(wget -qO- https://raw.githubusercontent.com/ZenXNF/ZV-Manager/main/zv.sh)\n"
                break ;;
            0) echo ""; break ;;
            *) echo -e "  \033[1;31mPilihan tidak valid!\033[0m" ;;
        esac
    done
fi

exit 0
