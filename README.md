<div align="center">

<img src="https://readme-typing-svg.demolab.com?font=Fira+Code&size=14&duration=2500&pause=500&color=00D9FF&center=true&vCenter=true&multiline=true&width=700&height=60&lines=🚀+SSH+Tunneling+Panel+%7C+Multi-Server+%7C+Telegram+Bot;📶+Bandwidth+Tracking+%7C+Auto-Maintenance+%7C+Self-Hosted" alt="Typing SVG" />

<br><br>

```
 ███████╗██╗   ██╗      ███╗   ███╗ █████╗ ███╗   ██╗ █████╗  ██████╗ ███████╗██████╗
 ╚══███╔╝██║   ██║      ████╗ ████║██╔══██╗████╗  ██║██╔══██╗██╔════╝ ██╔════╝██╔══██╗
   ███╔╝ ██║   ██║      ██╔████╔██║███████║██╔██╗ ██║███████║██║  ███╗█████╗  ██████╔╝
  ███╔╝  ╚██╗ ██╔╝      ██║╚██╔╝██║██╔══██║██║╚██╗██║██╔══██║██║   ██║██╔══╝  ██╔══██╗
 ███████╗ ╚████╔╝       ██║ ╚═╝ ██║██║  ██║██║ ╚████║██║  ██║╚██████╔╝███████╗██║  ██║
 ╚══════╝  ╚═══╝        ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝
```

**Panel SSH Tunneling self-hosted untuk Ubuntu 24.04**

Kelola akun SSH, pantau bandwidth, dan otomasi semuanya — langsung dari terminal atau Telegram.

<br>

![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)
![Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white)
![Python](https://img.shields.io/badge/Bot-Python%203-3776AB?style=for-the-badge&logo=python&logoColor=white)
![Telegram](https://img.shields.io/badge/Telegram-Bot-26A5E4?style=for-the-badge&logo=telegram&logoColor=white)

</div>

---

## 📖 Tentang

ZV-Manager adalah panel manajemen SSH tunneling yang bisa kamu hosting sendiri di VPS Ubuntu 24.04. Dirancang untuk reseller SSH yang butuh sistem yang lengkap — mulai dari pembuatan akun, manajemen saldo pelanggan, tracking bandwidth, hingga backup otomatis — semua tanpa aplikasi tambahan. Cukup terminal dan Telegram.

---

## 🎯 Fitur

<table>
<tr>
<td width="50%">

### 👤 Manajemen Akun SSH
- Buat, edit, hapus, kunci & buka kunci akun
- Limit IP per akun (proteksi multi-login)
- Kuota bandwidth per akun
- Akun trial dengan auto-cleanup
- Auto-hapus akun expired
- Auto-kill akun yang melebihi limit — notif Telegram

</td>
<td width="50%">

### 🤖 Telegram Bot
- Buat & perpanjang akun via bot
- Sistem saldo (top up → beli akun)
- Harga bisa diatur per server
- Beli tambahan bandwidth via bot
- `/saldo` `/history` `/start`
- Notifikasi expired otomatis
- Broadcast ke semua user

</td>
</tr>
<tr>
<td width="50%">

### 🌐 Multi-Server
- **Otak VPS** — panel penuh + Telegram bot
- **Remote VPS** — agent ringan (`zv-agent.sh`)
- Akun disinkron otomatis ke semua server
- Auth via password (sshpass) atau SSH key
- Tambah/hapus server dari menu

</td>
<td width="50%">

### 📶 Bandwidth Tracking
- Tracking berbasis PAM session
- Bekerja lewat Stunnel / HTTP Custom
- Kuota iptables: `hari × GB/hari`
- Warning 80% via Telegram
- Blokir otomatis jika habis
- Beli bandwidth tambahan via bot

</td>
</tr>
<tr>
<td width="50%">

### 💾 Backup & Restore
- Backup harian jam 02:00 → kirim ke Telegram
- Backup real-time setiap transaksi
- Backup per-server (akun SSH)
- Restore saat install ulang

</td>
<td width="50%">

### 🛠️ Sistem & Otomasi
- Watchdog — auto-restart service mati
- Manajemen SSL (Let's Encrypt / custom)
- Banner SSH yang bisa dikustomisasi
- Statistik konsol (akun, pendapatan)
- Versi tracking via commit hash GitHub

</td>
</tr>
</table>

---

## 🔌 Protokol

| Protokol | Port | Keterangan |
|---|---|---|
| OpenSSH | 22, 500, 40000 | SSH standar |
| Dropbear | 109, 143 | SSH alternatif |
| WebSocket HTTP | 80 | WS non-SSL, catch-all host |
| WebSocket HTTPS | 443 | WS via Stunnel SSL |
| UDP Custom | 1–65535 | TPROXY intercept semua port |
| BadVPN UDPGW | 7300 | UDP over TCP |

---

## ⏱️ Cron Jobs

| Job | Jadwal |
|---|---|
| Auto-kill multi-login | Setiap menit |
| Cleanup akun trial | Setiap menit |
| Cek bandwidth | Setiap 5 menit |
| Notifikasi expired | Setiap jam |
| Auto-hapus akun expired | 00:02 |
| Backup harian | 02:00 |
| Cek update | 06:00 |

---

## 📋 Kebutuhan

- Ubuntu **24.04 LTS** (fresh install dianjurkan)
- Akses **root**
- **Domain** yang mengarah ke IP VPS
- **Telegram Bot Token** + Admin Chat ID

---

## 📦 Instalasi

```bash
wget -q https://raw.githubusercontent.com/ZenXNF/ZV-Manager/main/install.sh && bash install.sh
```

Ikuti instruksi di layar. Installer akan setup semua otomatis — Nginx, SSH, Dropbear, WebSocket, UDP Custom, BadVPN, SSL, Telegram Bot, dan semua cron job.

---

## 🔄 Update

```bash
bash /etc/zv-manager/update.sh
```

Atau lewat menu terminal → **[6] Update Script**

---

## 🗑️ Uninstall

```bash
bash /etc/zv-manager/uninstall.sh
```

---

## 📁 Struktur Direktori

```
/etc/zv-manager/
├── accounts/
│   ├── ssh/          # Konfigurasi akun (*.conf)
│   ├── saldo/        # Saldo user Telegram (*.saldo)
│   └── users/        # Data user Telegram (*.user)
├── servers/          # Konfigurasi server remote + harga bot
├── core/             # Library inti (bandwidth, SSL, telegram, dll)
├── cron/             # Script otomasi terjadwal
├── menu/             # Menu terminal interaktif
├── services/         # Installer service (nginx, ssh, telegram, dll)
├── ssl/              # Sertifikat SSL
└── config.conf       # Konfigurasi global
```

---

---

## 📬 Kontak

<div align="center">

<a href="https://t.me/ZenXNF">
  <img src="https://img.shields.io/badge/Telegram-%40ZenXNF-26A5E4?style=for-the-badge&logo=telegram&logoColor=white" alt="Telegram ZenXNF"/>
</a>

</div>

---

<div align="center">

**ZV-Manager** — *Built for SSH resellers who mean business.*

</div>
