<div align="center">

<img src="https://readme-typing-svg.demolab.com?font=JetBrains+Mono&size=26&duration=2500&pause=800&color=00E5FF&center=true&vCenter=true&width=750&lines=ZV-Manager+%E2%80%94+SSH+%26+VMess+Panel;Multi+Server+%7C+Brain+Architecture;Telegram+Bot+%7C+Auto+Billing;Backup+%26+Restore+Otomatis;Optimized+for+512MB+RAM" alt="ZV-Manager" />

<br/>

![Platform](https://img.shields.io/badge/Ubuntu-24.04%20LTS-orange?style=for-the-badge&logo=ubuntu)
![License](https://img.shields.io/badge/license-MIT-green?style=for-the-badge)
![Telegram](https://img.shields.io/badge/Telegram-@ZenXNF-blue?style=for-the-badge&logo=telegram)
![RAM](https://img.shields.io/badge/RAM-512MB%20ready-purple?style=for-the-badge)

</div>

---

## Overview

ZV-Manager adalah panel manajemen **SSH Tunnel + VMess** berbasis console untuk Ubuntu 24.04. Dirancang untuk kebutuhan jualan VPN/SSH dengan arsitektur **Brain VPS** — satu server pusat mengelola banyak remote VPS via agent ringan. Dilengkapi bot Telegram otomatis, sistem saldo, backup harian + restore otomatis, dan multi-protokol (SSH + VMess/Xray).

---

## Fitur

### SSH Management
- Tambah, hapus, edit, renew akun SSH
- Lock / unlock akun
- Deteksi sesi aktif per user via `ps sshd` (akurat untuk HTTP Custom)
- IP count update tiap **10 detik** via cron loop
- Auto delete akun expired (cron harian jam 00:02)
- Auto kill multi-login tiap **10 detik**
- Trial gratis otomatis (batas 1x per hari per user)

### VMess Management (Xray-core)
- Tambah, hapus, edit, renew akun VMess
- Enable / disable akun (suspend sementara)
- Trial VMess 30 menit otomatis
- Monitor bandwidth per akun via Xray Stats API dengan `--reset` flag
- Auto disable saat bandwidth habis + notif Telegram
- Notif 80% bandwidth hampir habis
- Monitor online VMess tiap **30 detik** via Xray Stats API
- IP limit enforcement per akun VMess
- URL VMess: WS HTTP (80), WS TLS (443), gRPC TLS (443)

### Multi Server (Brain Architecture)
- Kelola banyak VPS dari 1 panel (brain/otak)
- Remote SSH via `zv-agent` (SSH) dan `zv-vmess-agent` (VMess)
- Auto deploy agent saat tambah server baru
- Dukungan autentikasi SSH key atau password (sshpass)
- Server tipe: `ssh`, `vmess`, atau `both`
- Setiap server punya harga, limit IP, BW, dan max akun sendiri
- Fallback otomatis IP/PORT jika kosong setelah restore

### Telegram Bot (Python / aiogram 3.x)
- `/start` → menu inline lengkap
- Buat akun SSH & VMess langsung dari bot — pilih server sesuai protokol
- Trial gratis SSH & VMess — 1x/hari per user
- Sistem saldo — potong otomatis saat beli/renew
- Perpanjang akun SSH & VMess dari bot
- Akun expired otomatis hilang dari tampilan + tombol inline
- Notifikasi otomatis 20 jam sebelum expired
- Info server: harga SSH & VMess, quota BW, limit IP, total akun
- Riwayat transaksi & cek saldo
- Broadcast teks & stiker ke semua user terdaftar
- **Admin panel**: topup, kurangi saldo, hapus akun SSH/VMess, cek user, history transaksi, online VMess monitor, kelola VMess (renew/enable/disable)

### Backup & Restore
- **Backup real-time** — tiap akun dibuat/diubah/dihapus, file `.conf` langsung dikirim ke Telegram admin
- **Backup harian otomatis** jam 02:00 — full backup dikompres `.tar.gz` → kirim ke Telegram
- Backup mencakup: akun SSH+VMess, saldo, data user bot, server, config, SSL, banner, file kredit
- Backup server: conf akun SSH+VMess per server + xray config.json
- **Restore otomatis** — pilih mode restore saat install, domain & token bisa diganti di tempat
- Notifikasi Telegram ke admin saat restore selesai (dikirim bot saat startup setelah reboot)
- Auto hapus backup > 7 hari

### Update Otomatis
- Notifikasi update di menu utama jika ada versi baru
- Update via menu **[6] Update** — tidak perlu command manual
- Cek update background setiap hari jam 06:00

### WebSocket & SSL
- WebSocket WS (port 80) + WSS (port 443)
- VMess WS + gRPC via nginx SSL unified
- Catch-all host header — support bug host / SNI
- Let's Encrypt Wildcard SSL via Cloudflare DNS
- Auto renew certificate harian jam 03:00

### Services
- OpenSSH multi-port (22, 500, 40000)
- Dropbear (109, 143)
- Nginx (reverse proxy WS + VMess)
- Xray-core (VMess WS + gRPC, Stats API)
- BadVPN UDPGW (port 7300)
- UDP Custom (1-65535 via TPROXY)
- WebSocket Proxy (ThreadPool, optimized)

---

## Instalasi

```bash
bash <(curl -s https://raw.githubusercontent.com/ZenXNF/ZV-Manager/main/zv.sh)
```

**Requirement:**
- Ubuntu 24.04 LTS
- Akses root
- Koneksi internet
- Minimum RAM: 512MB (rekomendasi 1GB)

---

## Restore dari Backup

```bash
bash <(curl -s https://raw.githubusercontent.com/ZenXNF/ZV-Manager/main/zv.sh)
```

Pilih **[2] Restore dari Backup** → masukkan path file `.tar.gz` → ikuti prompt.

- Domain bisa diubah saat restore
- Bot Token & Admin ID bisa diganti saat restore
- Setelah reboot, bot otomatis kirim notif ke admin bahwa restore selesai

---

## Update

Via menu console:
```
Menu Utama → [6] Update
```

---

## Uninstall

Via menu console:
```
Menu Utama → [4] Sistem → [8] Uninstall
```

---

## Struktur Direktori

```
/etc/zv-manager/
├── core/               # License, SSL, Telegram helper, Bandwidth, Banner
├── menu/
│   ├── ssh/            # Manajemen akun SSH
│   ├── vmess/          # Manajemen akun VMess
│   ├── server/         # Manajemen server remote + deploy agent
│   ├── info/           # Statistik & info server
│   └── system/         # System settings, backup, uninstall
├── services/
│   ├── nginx/          # Nginx config (SSH WS + VMess WS/gRPC)
│   ├── xray/           # Xray-core config & install
│   ├── websocket/      # WS proxy
│   ├── badvpn/         # BadVPN UDPGW
│   ├── dropbear/       # Dropbear SSH
│   └── telegram/       # Bot Telegram (Python/aiogram 3.x)
├── cron/               # Auto task (expired, trial, notify, backup, bw-vmess, ip-limit, vmess-online)
├── utils/              # Colors, logger, helpers, remote.sh
├── accounts/
│   ├── ssh/            # Data akun SSH (.conf per user)
│   ├── vmess/          # Data akun VMess (.conf per user)
│   ├── saldo/          # Saldo per Telegram user ID
│   ├── users/          # Data user terdaftar bot
│   └── notified/       # History notif expired
├── servers/            # Data server remote (.conf + .tg.conf)
├── ssl/                # Sertifikat SSL
├── zv-agent.sh         # Agent SSH untuk remote server
└── zv-vmess-agent.sh   # Agent VMess untuk remote server
```

---

## Setup Telegram Bot

1. Buat bot di [@BotFather](https://t.me/BotFather)
2. Buka menu: **Sistem → Setup Telegram Bot**
3. Masukkan Bot Token → verifikasi otomatis
4. Masukkan Telegram User ID kamu (cek di [@userinfobot](https://t.me/userinfobot))
5. Bot langsung aktif

---

## Setup Wildcard SSL

1. Arahkan `*.domain.com` ke IP VPS di Cloudflare
2. Buka menu: **Sistem → Manajemen SSL → Let's Encrypt Wildcard**
3. Masukkan domain + Cloudflare API Token
4. Sertifikat otomatis diinstall & auto renew tiap hari jam 03:00

---

## Port Default

| Service | Port |
|---|---|
| OpenSSH | 22, 500, 40000 |
| Dropbear | 109, 143 |
| WebSocket / VMess WS (HTTP) | 80 |
| WebSocket SSL / VMess WS+gRPC (TLS) | 443 |
| Xray Stats API (internal) | 10085 |
| BadVPN UDPGW | 7300 |
| UDP Custom | 1-65535 |
| WS Proxy Internal | 8880 |

---

## Cron Schedule

| Cron | Jadwal | Fungsi |
|---|---|---|
| autokill | Tiap 10 detik | Kill multi-login SSH |
| trial-cleanup | Tiap 1 menit | Hapus akun trial expired |
| ip-limit | Tiap 1 menit | Cek & kick IP limit VMess |
| bw-check | Tiap 10 detik | Deteksi sesi SSH aktif via ps |
| bw-vmess | Tiap 5 menit | Cek quota bandwidth VMess via agent |
| vmess-online | Tiap 30 detik | Update status online VMess |
| tg-notify | Tiap 1 jam | Notif Telegram expired |
| expired | 00:02 | Auto hapus akun expired (SSH + VMess) |
| license-check | 00:05 | Cek lisensi |
| backup | 02:00 | Full backup → Telegram |
| check-update | 06:00 | Cek versi terbaru |

---

## Kontak

- Telegram : [@ZenXNF](https://t.me/ZenXNF)
- GitHub   : [ZenXNF/ZV-Manager](https://github.com/ZenXNF/ZV-Manager)

---

<div align="center">

Made with ❤️ by ZenXNF

</div>
