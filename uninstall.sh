#!/bin/bash
# ============================================================
#   ZV-Manager — Uninstaller / Self-Destruct
#   Mengembalikan VPS ke kondisi bersih
#
#   Penggunaan:
#     bash uninstall.sh           → interaktif (minta konfirmasi)
#     bash uninstall.sh --silent  → otomatis tanpa konfirmasi (dipanggil dari cron/license)
# ============================================================

if [[ "$EUID" -ne 0 ]]; then
    echo "[ERROR] Jalankan sebagai root!"
    exit 1
fi

SILENT=false
[[ "$1" == "--silent" ]] && SILENT=true

LOG="/var/log/zv-manager/uninstall.log"
mkdir -p /var/log/zv-manager
touch "$LOG" 2>/dev/null

_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG"
}

_log_silent() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG" 2>/dev/null
}

# ── Konfirmasi (kalau bukan silent) ───────────────────────────────────────────
if [[ "$SILENT" == false ]]; then
    echo ""
    echo "  ╔══════════════════════════════════════╗"
    echo "  ║    ⚠  UNINSTALL ZV-MANAGER  ⚠       ║"
    echo "  ╚══════════════════════════════════════╝"
    echo ""
    echo "  Ini akan menghapus ZV-Manager beserta:"
    echo "  - Semua service (nginx, stunnel4, dropbear, ws-proxy, UDP)"
    echo "  - Semua akun SSH yang pernah dibuat"
    echo "  - Semua file konfigurasi ZV-Manager"
    echo "  - Semua cron job ZV-Manager"
    echo ""
    read -rp "  Ketik 'HAPUS' untuk konfirmasi: " confirm
    if [[ "$confirm" != "HAPUS" ]]; then
        echo ""
        echo "  Dibatalkan."
        exit 0
    fi
    echo ""
fi

_log_silent "====== MULAI UNINSTALL ZV-MANAGER ======"

# ── LANGKAH 1: Hapus semua akun SSH yang dibuat ZV-Manager ───────────────────
_log_silent "Langkah 1: Menghapus akun SSH..."

if [[ -d "/etc/zv-manager/accounts/ssh" ]]; then
    for conf_file in /etc/zv-manager/accounts/ssh/*.conf; do
        [[ -f "$conf_file" ]] || continue
        username=""
        while IFS='=' read -r key val; do
            [[ "$key" == "USERNAME" ]] && username="$val"
        done < "$conf_file"
        if [[ -n "$username" ]]; then
            pkill -u "$username" 2>/dev/null
            sleep 0.3
            userdel -r "$username" 2>/dev/null
            _log_silent "  Akun dihapus: $username"
        fi
    done
else
    _log_silent "  Tidak ada akun SSH ditemukan"
fi

# ── LANGKAH 2: Stop semua service ZV-Manager ─────────────────────────────────
_log_silent "Langkah 2: Menghentikan service ZV-Manager..."

for svc in zv-wss zv-stunnel zv-udp zv-ws zv-badvpn; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        systemctl stop "$svc" 2>/dev/null
        _log_silent "  Stop: $svc"
    fi
    systemctl disable "$svc" 2>/dev/null
done

for f in /etc/systemd/system/zv-*.service; do
    [[ -f "$f" ]] && rm -f "$f" && _log_silent "  Hapus service file: $f"
done
systemctl daemon-reload 2>/dev/null

# ── LANGKAH 3: Uninstall package yang dipasang ZV-Manager ────────────────────
_log_silent "Langkah 3: Menghapus package..."

DEBIAN_FRONTEND=noninteractive apt-get purge -y \
    nginx nginx-common nginx-core \
    stunnel4 \
    dropbear \
    &>/dev/null
apt-get autoremove -y &>/dev/null
_log_silent "  Package nginx, stunnel4, dropbear dihapus"

# ── LANGKAH 4: Kembalikan sshd_config ke default Ubuntu 24.04 ─────────────────
_log_silent "Langkah 4: Restore konfigurasi OpenSSH..."

SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP=$(ls -1t /etc/ssh/sshd_config.bak.* 2>/dev/null | head -1)
if [[ -n "$BACKUP" ]]; then
    cp "$BACKUP" "$SSHD_CONFIG"
    _log_silent "  sshd_config di-restore dari backup: $BACKUP"
else
    _log_silent "  Backup tidak ditemukan, menulis ulang sshd_config ke default..."
    cat > "$SSHD_CONFIG" <<'SSHDEOF'
# sshd_config — default Ubuntu 24.04
# Dikembalikan oleh ZV-Manager uninstaller

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

sed -i '/^Port 500$/d' "$SSHD_CONFIG"
sed -i '/^Port 40000$/d' "$SSHD_CONFIG"
sed -i '/^Banner \/etc\/issue.net$/d' "$SSHD_CONFIG"

systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
_log_silent "  OpenSSH di-restart dengan config default"

# ── LANGKAH 5: Kembalikan file sistem yang diubah ZV-Manager ─────────────────
_log_silent "Langkah 5: Restore file sistem..."

cat > /etc/issue.net <<'ISSUEOF'
Ubuntu 24.04.2 LTS
ISSUEOF
_log_silent "  /etc/issue.net dikembalikan ke default"

rm -f /etc/update-motd.d/00-zv-manager
_log_silent "  /etc/update-motd.d/00-zv-manager dihapus"

for f in /etc/update-motd.d/*; do
    [[ -f "$f" ]] && chmod +x "$f"
done
_log_silent "  Script MOTD default diaktifkan kembali"

# ── .profile — tergantung mode ────────────────────────────────────────────────
if [[ "$SILENT" == true ]]; then
    # Mode otomatis (cron) — tulis .profile berisi notifikasi
    # Notifikasi ini muncul setiap login sampai user pilih [1] hapus
    _log_silent "  /root/.profile diisi notifikasi izin berakhir"
    cat > /root/.profile <<'NOTIFEOF'
# ~/.profile — ZV-Manager Expired Notification
if [ "$BASH" ]; then
    if [ -f ~/.bashrc ]; then
        . ~/.bashrc
    fi
fi
mesg n 2>/dev/null || true

case $- in
    *i*) ;;
    *) return ;;
esac
[ -t 1 ] || return
[ -z "$SSH_TTY" ] && return
[ -n "$SSH_ORIGINAL_COMMAND" ] && return

clear
echo ""
echo -e "\033[1;31m  ╔══════════════════════════════════════╗\033[0m"
echo -e "\033[1;31m  ║    ⚠  IZIN VPS TELAH BERAKHIR  ⚠    ║\033[0m"
echo -e "\033[1;31m  ╚══════════════════════════════════════╝\033[0m"
echo ""
echo -e "\033[0;37m  Izin penggunaan ZV-Manager untuk VPS ini\033[0m"
echo -e "\033[0;37m  telah berakhir dan melewati masa toleransi.\033[0m"
echo ""
echo -e "\033[0;37m  Semua konfigurasi, akun SSH, dan service\033[0m"
echo -e "\033[0;37m  telah dihapus. VPS kembali ke kondisi bersih.\033[0m"
echo ""
echo -e "\033[0;36m  ──────────────────────────────────────\033[0m"
echo ""
echo -e "\033[1;33m  [1]\033[0m Hapus semua & kembalikan ke default"
echo -e "\033[1;32m  [2]\033[0m Perpanjang lisensi → t.me/ZenXNF"
echo -e "\033[1;37m  [0]\033[0m Keluar"
echo ""

while true; do
    read -rp "  Pilihan: " _zvpilihan
    case $_zvpilihan in
        1)
            rm -f /root/zv.sh /root/update.sh 2>/dev/null
            cat > /root/.profile <<'DEFAULTEOF'
# ~/.profile: executed by Bourne-compatible login shells.
if [ "$BASH" ]; then
  if [ -f ~/.bashrc ]; then
    . ~/.bashrc
  fi
fi
mesg n 2>/dev/null || true
DEFAULTEOF
            echo ""
            echo -e "\033[1;32m  Semua file sisa berhasil dihapus.\033[0m"
            echo -e "\033[0;37m  VPS sepenuhnya kembali ke kondisi default.\033[0m"
            echo ""
            break
            ;;
        2)
            echo ""
            echo -e "\033[1;36m  Silahkan hubungi Telegram: @ZenXNF / t.me/ZenXNF\033[0m"
            echo -e "\033[0;37m  Setelah lisensi aktif, jalankan kembali:\033[0m"
            echo -e "\033[1;33m  wget -q https://raw.githubusercontent.com/ZenXNF/ZV-Manager/main/zv.sh && bash zv.sh\033[0m"
            echo ""
            break
            ;;
        0)
            echo ""
            echo -e "\033[0;37m  Notifikasi ini akan muncul kembali saat login berikutnya.\033[0m"
            echo ""
            break
            ;;
        *)
            echo -e "\033[1;31m  Pilihan tidak valid!\033[0m"
            ;;
    esac
done
NOTIFEOF

else
    # Mode manual — kembalikan .profile ke default Ubuntu langsung
    cat > /root/.profile <<'PROFILEOF'
# ~/.profile: executed by Bourne-compatible login shells.
if [ "$BASH" ]; then
  if [ -f ~/.bashrc ]; then
    . ~/.bashrc
  fi
fi
mesg n 2>/dev/null || true
PROFILEOF
    _log_silent "  /root/.profile dikembalikan ke default"
fi

rm -f /etc/stunnel/zv-wss.conf
_log_silent "  Config stunnel ZV-Manager dihapus"

# ── LANGKAH 6: Hapus cron job ZV-Manager ─────────────────────────────────────
_log_silent "Langkah 6: Menghapus cron jobs..."

for f in /etc/cron.d/zv-*; do
    [[ -f "$f" ]] && rm -f "$f" && _log_silent "  Hapus cron: $f"
done
service cron restart 2>/dev/null

# ── LANGKAH 7: Hapus semua file ZV-Manager ───────────────────────────────────
_log_silent "Langkah 7: Menghapus file ZV-Manager..."

rm -f /usr/local/bin/menu
rm -f /usr/local/bin/zv-ws-proxy.py
_log_silent "  Symlink dan binary global dihapus"

rm -rf /etc/zv-manager/udp
_log_silent "  UDP Custom binary dihapus"

rm -rf /etc/zv-manager
_log_silent "  /etc/zv-manager dihapus"

rm -rf /root/ZV-Manager
_log_silent "  /root/ZV-Manager dihapus"

# ── LANGKAH 8: Hapus backup sshd_config lama ─────────────────────────────────
for bak in /etc/ssh/sshd_config.bak.*; do
    [[ -f "$bak" ]] && rm -f "$bak"
done
_log_silent "  Backup sshd_config lama dihapus"

_log_silent "====== UNINSTALL SELESAI ======"

# ── Self-delete script ────────────────────────────────────────────────────────
rm -f "$0"

# ── Notifikasi akhir untuk mode manual ───────────────────────────────────────
if [[ "$SILENT" == false ]] && [ -t 1 ]; then
    clear
    echo ""
    echo -e "\033[1;32m  ╔══════════════════════════════════════╗\033[0m"
    echo -e "\033[1;32m  ║    ✔  UNINSTALL SELESAI              ║\033[0m"
    echo -e "\033[1;32m  ╚══════════════════════════════════════╝\033[0m"
    echo ""
    echo -e "\033[0;37m  Semua komponen ZV-Manager telah dihapus.\033[0m"
    echo -e "\033[0;37m  VPS sudah kembali bersih.\033[0m"
    echo ""
    echo -e "\033[1;33m  [1]\033[0m Hapus file sisa (zv.sh)"
    echo -e "\033[1;32m  [2]\033[0m Pasang lagi → t.me/ZenXNF"
    echo -e "\033[1;37m  [0]\033[0m Keluar"
    echo ""

    while true; do
        read -rp "  Pilihan: " pilihan
        case $pilihan in
            1)
                rm -f /root/zv.sh /root/update.sh 2>/dev/null
                echo ""
                echo -e "\033[1;32m  File sisa berhasil dihapus.\033[0m"
                echo ""
                break
                ;;
            2)
                echo ""
                echo -e "\033[1;36m  Silahkan hubungi Telegram: @ZenXNF / t.me/ZenXNF\033[0m"
                echo -e "\033[0;37m  Setelah lisensi aktif, jalankan kembali:\033[0m"
                echo -e "\033[1;33m  wget -q https://raw.githubusercontent.com/ZenXNF/ZV-Manager/main/zv.sh && bash zv.sh\033[0m"
                echo ""
                break
                ;;
            0)
                echo ""
                break
                ;;
            *)
                echo -e "\033[1;31m  Pilihan tidak valid!\033[0m"
                ;;
        esac
    done
fi

exit 0
