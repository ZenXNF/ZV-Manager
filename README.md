<div align="center">

<img src="https://readme-typing-svg.demolab.com?font=JetBrains+Mono&size=28&duration=3000&pause=1000&color=00E5FF&center=true&vCenter=true&width=700&lines=ZV-Manager+SSH+Tunnel;Auto+Deploy+%7C+Multi+Server;Telegram+Bot+%7C+Full+Panel;Backup+Otomatis+%7C+Broadcast;Optimized+for+512MB+RAM" alt="ZV-Manager" />

<br/>

![Version](https://img.shields.io/badge/version-1.0.0-00e5ff?style=for-the-badge&logo=github)
![Platform](https://img.shields.io/badge/platform-Ubuntu%2024.04-orange?style=for-the-badge&logo=ubuntu)
![License](https://img.shields.io/badge/license-MIT-green?style=for-the-badge)
![Telegram](https://img.shields.io/badge/Telegram-@ZenXNF-blue?style=for-the-badge&logo=telegram)
![RAM](https://img.shields.io/badge/RAM-512MB%20ready-purple?style=for-the-badge)

</div>

---

## Overview

ZV-Manager adalah panel manajemen SSH Tunnel berbasis console untuk Ubuntu 24.04. Dirancang khusus untuk kebutuhan jualan VPN/SSH dengan fitur lengkap mulai dari manajemen akun, multi-server, bot Telegram otomatis, hingga sistem backup real-time. Dioptimasi untuk VPS 512MB RAM.

---

## Fitur

### SSH Management
- Tambah, hapus, edit, renew akun SSH
- Lock / unlock akun
- Monitor akun online real-time (Direct IP, WebSocket, UDP Custom, Dropbear)
- Auto delete akun expired (cron harian jam 00:02)
- Auto kill multi-login (cron per menit)
- Trial gratis otomatis (batas 1x per hari per user)

### Multi Server
- Kelola banyak VPS dari 1 panel (brain/otak)
- Remote via `zv-agent` (lightweight, tanpa menu, tanpa lisensi)
- Dukungan autentikasi SSH key atau password (sshpass)
- Sync akun otomatis ke semua remote server

### Telegram Bot (Python / aiogram 3.x)
- `/start` → menu inline lengkap
- Buat akun SSH langsung dari bot
- Trial gratis 30 menit (1x/hari per user)
- Sistem saldo — potong otomatis saat beli/renew
- Perpanjang akun langsung dari bot
- Notifikasi otomatis 20 jam sebelum expired
- Info server: harga, quota, limit IP, total akun
- Riwayat transaksi & cek saldo
- **Broadcast teks & stiker** ke semua user terdaftar
- Tambah bandwidth tambahan via bot
- Admin panel lengkap (topup, hapus akun, cek user)

### Backup & Restore
- **Backup real-time** — tiap ada akun dibuat/diubah/dihapus, file `.conf` langsung dikirim ke Telegram admin
- **Backup harian otomatis** jam 02:00 — full backup semua data dikompres `.tar.gz` → kirim ke Telegram
- Backup mencakup: akun SSH, saldo, data user bot, daftar server, config, SSL
- Backup remote VPS: `/etc/passwd` + `/etc/shadow` untuk restore user Linux
- Restore 1 perintah dari menu
- Auto hapus backup > 7 hari

### Update Otomatis
- Notifikasi update di menu utama jika ada versi baru
- Tampil banner: `⚠ Update tersedia: v1.0.0 → v1.0.1`
- Update via menu **[6] Update** — tidak perlu command manual
- Cek update background setiap hari jam 06:00 (tidak mempengaruhi performa)

### WebSocket & SSL
- WebSocket WS (port 80) + WSS (port 443)
- Catch-all host header — support bug host / SNI
- Let's Encrypt Wildcard SSL via Cloudflare DNS
- Auto renew certificate harian jam 03:00
- Stunnel4 sebagai SSL termination

### Services
- OpenSSH multi-port (22, 500, 40000)
- Dropbear (109, 143)
- Nginx (reverse proxy WS)
- Stunnel4 (SSL termination)
- BadVPN UDPGW (port 7300)
- UDP Custom (1-65535)
- WebSocket Proxy (ThreadPool, optimized)

### Performa & Optimasi (512MB RAM)
- Pure bash — tanpa spawn python3 di cron
- Cron bw-check, expired, trial-cleanup, tg-notify: pure curl tanpa tempfile
- Bot systemd: `MemoryMax=120M`, `CPUQuota=60%`
- ws-proxy: ThreadPool max 200 koneksi, buffer 8KB, timeout 120s
- Cache conf server 5 menit di bot
- autokill.sh: `who` dipanggil sekali per cycle

### Panel Console
- Sistem lisensi (grace period, auto uninstall)
- Edit server banner dari menu
- Statistik penjualan dengan estimasi pendapatan
- Manajemen saldo user via console
- Broadcast pesan/stiker dari console
- Backup & Restore via menu System

---

## Instalasi

```bash
wget -q https://raw.githubusercontent.com/ZenXNF/ZV-Manager/main/zv.sh && bash zv.sh
```

**Requirement:**
- Ubuntu 24.04 LTS
- Akses root
- Koneksi internet
- Minimum RAM: 512MB (rekomendasi 1GB)

---

## Update

Via menu console:
```
Menu Utama → [6] Update
```

Atau via command:
```bash
bash /etc/zv-manager/update.sh
```

---

## Uninstall

```bash
bash /etc/zv-manager/uninstall.sh
```

---

## Struktur Direktori

```
/etc/zv-manager/
├── core/               # License, SSL, Telegram helper, Bandwidth, Banner
├── menu/
│   ├── ssh/            # Manajemen akun SSH
│   ├── server/         # Manajemen server remote
│   ├── info/           # Statistik & info server
│   └── system/         # System settings, backup
├── services/
│   ├── nginx/          # Nginx config
│   ├── websocket/      # WS proxy + Stunnel
│   ├── badvpn/         # BadVPN UDPGW
│   ├── dropbear/       # Dropbear SSH
│   └── telegram/       # Bot Telegram (Python)
├── cron/               # Auto task (expired, trial, notify, backup, update)
├── utils/              # Colors, logger, helpers, remote
├── accounts/
│   ├── ssh/            # Data akun (.conf per user)
│   ├── saldo/          # Saldo per Telegram user ID
│   └── users/          # Data user terdaftar bot
├── servers/            # Data server remote
└── ssl/                # Sertifikat SSL
```

---

## Setup Telegram Bot

1. Buat bot di [@BotFather](https://t.me/BotFather)
2. Buka menu: **System → Setup Telegram Bot**
3. Masukkan Bot Token → verifikasi otomatis
4. Masukkan Telegram User ID kamu (cek di [@userinfobot](https://t.me/userinfobot))
5. Bot langsung aktif

---

## Setup Wildcard SSL

1. Arahkan `*.domain.com` ke IP VPS di Cloudflare
2. Buka menu: **System → Manajemen SSL → Let's Encrypt Wildcard**
3. Masukkan domain + Cloudflare API Token
4. Sertifikat otomatis diinstall & auto renew tiap hari jam 03:00

---

## Port Default

| Service | Port |
|---|---|
| OpenSSH | 22, 500, 40000 |
| Dropbear | 109, 143 |
| WebSocket (WS) | 80 |
| WebSocket SSL (WSS) | 443 |
| BadVPN UDPGW | 7300 |
| UDP Custom | 1-65535 |
| Web Info | 81 |
| WS Proxy Internal | 8880 |

---

## Cron Schedule

| Cron | Jadwal | Fungsi |
|---|---|---|
| autokill | Tiap 1 menit | Kill multi-login |
| trial-cleanup | Tiap 1 menit | Hapus akun trial expired |
| bw-check | Tiap 5 menit | Cek quota bandwidth |
| tg-notify | Tiap 1 jam | Notif Telegram expired |
| expired | 00:02 | Auto hapus akun expired |
| license-check | 00:05 | Cek lisensi |
| backup | 02:00 | Full backup → Telegram |
| check-update | 06:00 | Cek versi terbaru |

---

## Changelog

### v1.0.4
- Rilis perdana
- SSH Management lengkap (tambah, hapus, edit, renew, lock, unlock)
- Multi-server via zv-agent
- Telegram bot (aiogram 3.x) — beli, renew, trial, saldo, broadcast
- Broadcast teks & stiker
- Sistem backup real-time + harian otomatis
- Notifikasi update di menu utama
- Optimasi performa untuk VPS 512MB RAM
- WebSocket + SSL + BadVPN + UDP Custom
- Sistem lisensi dengan grace period

---

## Kontak

- Telegram : [@ZenXNF](https://t.me/ZenXNF)
- GitHub   : [ZenXNF/ZV-Manager](https://github.com/ZenXNF/ZV-Manager)

---

<div align="center">

Made with ❤️ by ZenXNF

</div>
