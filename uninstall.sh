#!/bin/bash
# ============================================================
#   ZV-Manager — Uninstaller / Self-Destruct
#   Mengembalikan VPS ke kondisi bersih setelah apt update & upgrade
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

_log "====== MULAI UNINSTALL ZV-MANAGER ======"

# ── LANGKAH 1: Hapus semua akun SSH yang dibuat ZV-Manager ───────────────────
_log "Langkah 1: Menghapus akun SSH..."

if [[ -d "/etc/zv-manager/accounts/ssh" ]]; then
    for conf_file in /etc/zv-manager/accounts/ssh/*.conf; do
        [[ -f "$conf_file" ]] || continue
        username=""
        # Baca USERNAME dari file conf
        while IFS='=' read -r key val; do
            [[ "$key" == "USERNAME" ]] && username="$val"
        done < "$conf_file"

        if [[ -n "$username" ]]; then
            pkill -u "$username" 2>/dev/null
            sleep 0.3
            userdel -r "$username" 2>/dev/null
            _log "  Akun dihapus: $username"
        fi
    done
else
    _log "  Tidak ada akun SSH ditemukan"
fi

# ── LANGKAH 2: Stop semua service ZV-Manager ─────────────────────────────────
_log "Langkah 2: Menghentikan service ZV-Manager..."

for svc in zv-wss zv-stunnel zv-udp zv-ws zv-badvpn; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        systemctl stop "$svc" 2>/dev/null
        _log "  Stop: $svc"
    fi
    systemctl disable "$svc" 2>/dev/null
done

# Hapus file service
for f in /etc/systemd/system/zv-*.service; do
    [[ -f "$f" ]] && rm -f "$f" && _log "  Hapus service file: $f"
done
systemctl daemon-reload 2>/dev/null

# ── LANGKAH 3: Uninstall package yang dipasang ZV-Manager ────────────────────
_log "Langkah 3: Menghapus package..."

DEBIAN_FRONTEND=noninteractive apt-get purge -y \
    nginx nginx-common nginx-core \
    stunnel4 \
    dropbear \
    2>/dev/null
apt-get autoremove -y 2>/dev/null
_log "  Package nginx, stunnel4, dropbear dihapus"

# OpenSSH TIDAK di-purge — hanya config yang dikembalikan ke default
# supaya VPS masih bisa diakses via SSH setelah uninstall

# ── LANGKAH 4: Kembalikan sshd_config ke default Ubuntu 24.04 ─────────────────
_log "Langkah 4: Restore konfigurasi OpenSSH..."

SSHD_CONFIG="/etc/ssh/sshd_config"

# Coba restore dari backup yang dibuat saat install
BACKUP=$(ls -1t /etc/ssh/sshd_config.bak.* 2>/dev/null | head -1)
if [[ -n "$BACKUP" ]]; then
    cp "$BACKUP" "$SSHD_CONFIG"
    _log "  sshd_config di-restore dari backup: $BACKUP"
else
    # Tidak ada backup — tulis ulang ke default Ubuntu 24.04 yang aman
    _log "  Backup tidak ditemukan, menulis ulang sshd_config ke default..."
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

# Hapus Port 500 dan 40000 yang ditambahkan ZV-Manager (kalau backup tidak tersedia)
sed -i '/^Port 500$/d' "$SSHD_CONFIG"
sed -i '/^Port 40000$/d' "$SSHD_CONFIG"

# Hapus baris Banner yang ditambahkan ZV-Manager
sed -i '/^Banner \/etc\/issue.net$/d' "$SSHD_CONFIG"

# Restart SSH
systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
_log "  OpenSSH di-restart dengan config default"

# ── LANGKAH 5: Kembalikan file sistem yang diubah ZV-Manager ─────────────────
_log "Langkah 5: Restore file sistem..."

# /etc/issue.net — kembalikan ke default Ubuntu
cat > /etc/issue.net <<'ISSUEOF'
Ubuntu 24.04.2 LTS
ISSUEOF
_log "  /etc/issue.net dikembalikan ke default"

# /etc/update-motd.d/ — hapus file ZV-Manager, aktifkan kembali yang lain
rm -f /etc/update-motd.d/00-zv-manager
_log "  /etc/update-motd.d/00-zv-manager dihapus"

# Aktifkan kembali script MOTD default Ubuntu yang mungkin di-disable
for f in /etc/update-motd.d/*; do
    [[ -f "$f" ]] && chmod +x "$f"
done
_log "  Script MOTD default diaktifkan kembali"

# /root/.profile — kembalikan ke default Ubuntu 24.04
cat > /root/.profile <<'PROFILEOF'
# ~/.profile: executed by Bourne-compatible login shells.
if [ "$BASH" ]; then
  if [ -f ~/.bashrc ]; then
    . ~/.bashrc
  fi
fi
mesg n 2>/dev/null || true
PROFILEOF
_log "  /root/.profile dikembalikan ke default"

# Hapus config stunnel ZV-Manager
rm -f /etc/stunnel/zv-wss.conf
_log "  Config stunnel ZV-Manager dihapus"

# ── LANGKAH 6: Hapus cron job ZV-Manager ─────────────────────────────────────
_log "Langkah 6: Menghapus cron jobs..."

for f in /etc/cron.d/zv-*; do
    [[ -f "$f" ]] && rm -f "$f" && _log "  Hapus cron: $f"
done
service cron restart 2>/dev/null

# ── LANGKAH 7: Hapus semua file ZV-Manager ───────────────────────────────────
_log "Langkah 7: Menghapus file ZV-Manager..."

rm -f /usr/local/bin/menu
rm -f /usr/local/bin/zv-ws-proxy.py
_log "  Symlink dan binary global dihapus"

# Hapus UDP Custom binary dan config
rm -rf /etc/zv-manager/udp
_log "  UDP Custom binary dihapus"

# Hapus folder utama ZV-Manager
rm -rf /etc/zv-manager
_log "  /etc/zv-manager dihapus"

# Hapus repo clone kalau ada
rm -rf /root/ZV-Manager
_log "  /root/ZV-Manager dihapus"

# ── LANGKAH 8: Backup sshd_config lama (cleanup) ─────────────────────────────
# Hapus semua backup lama yang pernah dibuat
for bak in /etc/ssh/sshd_config.bak.*; do
    [[ -f "$bak" ]] && rm -f "$bak"
done
_log "  Backup sshd_config lama dihapus"

# ── Selesai ───────────────────────────────────────────────────────────────────
_log "====== UNINSTALL SELESAI ======"

if [[ "$SILENT" == false ]]; then
    echo ""
    echo "  ╔══════════════════════════════════════╗"
    echo "  ║    ✔  UNINSTALL SELESAI              ║"
    echo "  ╚══════════════════════════════════════╝"
    echo ""
    echo "  Semua komponen ZV-Manager telah dihapus."
    echo "  VPS sudah kembali bersih."
    echo ""
    echo "  Log tersimpan di: $LOG"
    echo ""
fi

# Tampilkan notifikasi ke terminal aktif kalau ada
if [ -t 1 ] || [[ "$SILENT" == true ]]; then
    echo ""
    echo "  ╔══════════════════════════════════════╗"
    echo "  ║    ⚠  IZIN VPS TELAH BERAKHIR  ⚠    ║"
    echo "  ╚══════════════════════════════════════╝"
    echo ""
    echo "  Izin penggunaan ZV-Manager untuk VPS ini"
    echo "  telah berakhir dan melewati masa toleransi."
    echo ""
    echo "  ZV-Manager telah dihapus dari VPS ini."
    echo "  Silahkan hubungi Telegram: @ZenXNF / t.me/ZenXNF"
    echo ""
fi

# Self-delete script ini sendiri (self-destruct)
rm -f "$0"

exit 0
