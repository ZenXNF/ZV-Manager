<div align="center">

<img src="https://readme-typing-svg.demolab.com?font=JetBrains+Mono&size=26&duration=2500&pause=800&color=00E5FF&center=true&vCenter=true&width=750&lines=ZV-Manager+%E2%80%94+SSH+%26+VMess+Panel;Multi+Server+%7C+Brain+Architecture;Telegram+Bot+%7C+Auto+Billing;Backup+Otomatis+%7C+Broadcast;Optimized+for+512MB+RAM" alt="ZV-Manager" />

<br/>

![Version](https://img.shields.io/badge/version-1.2.0-00e5ff?style=for-the-badge&logo=github)
![Platform](https://img.shields.io/badge/Ubuntu-24.04%20LTS-orange?style=for-the-badge&logo=ubuntu)
![Telegram](https://img.shields.io/badge/Telegram-@ZenXNF-blue?style=for-the-badge&logo=telegram)
![RAM](https://img.shields.io/badge/RAM-512MB%20ready-purple?style=for-the-badge)

</div>

---

## Overview

ZV-Manager adalah panel manajemen **SSH Tunnel + VMess** berbasis console untuk Ubuntu 24.04. Dirancang untuk kebutuhan jualan VPN/SSH dengan arsitektur **Brain VPS** — satu server pusat mengelola banyak remote VPS via agent ringan. Dilengkapi bot Telegram otomatis, sistem saldo, backup real-time, dan multi-protokol (SSH + VMess/Xray).

---

## Fitur

### SSH Management
- Tambah, hapus, edit, renew akun SSH
- Lock / unlock akun
- Auto delete akun expired (berdasarkan EXPIRED_TS, tepat waktu)
- Auto kill multi-login via `pgrep sshd` — real-time tiap 10 detik
- Trial gratis otomatis (batas 1x per hari per user)
- Bandwidth tracking via iptables per akun

### VMess Management (Xray-core)
- Tambah, hapus, edit, renew akun VMess
- Enable / disable akun (suspend sementara)
- Trial VMess 30 menit otomatis
- Monitor bandwidth per akun via Xray Stats API
- Auto disable saat bandwidth habis + notif Telegram
- Notif 80% bandwidth hampir habis
- **IP limit enforcement** via ws-proxy — koneksi IP ke-2 ditolak langsung real-time
- URL VMess: WS HTTP (80), WS TLS (443), gRPC TLS (443)

### Multi Server (Brain Architecture)
- Kelola banyak VPS dari 1 panel (brain/otak)
- Remote SSH via `zv-agent` (SSH) dan `zv-vmess-agent` (VMess)
- Auto deploy agent saat tambah server baru
- Dukungan autentikasi SSH key atau password (sshpass)
- Server tipe: `ssh`, `vmess`, atau `both`
- Setiap server punya harga, limit IP, BW, dan max akun sendiri

### Telegram Bot (Python / aiogram 3.x)
- `/start` → menu inline lengkap
- Buat akun SSH & VMess langsung dari bot — pilih server sesuai protokol
- Trial gratis SSH & VMess — 1x/hari per user
- Sistem saldo — potong otomatis saat beli/renew
- Perpanjang akun SSH & VMess dari bot
- Notifikasi otomatis 20 jam sebelum expired
- Info server: harga SSH & VMess, quota BW, limit IP, total akun
- Riwayat transaksi & cek saldo
- Broadcast teks & stiker ke semua user terdaftar
- **Admin panel**: topup manual, kurangi saldo, hapus akun, cek user, history transaksi

### Backup & Restore
- **Backup real-time** — tiap akun dibuat/diubah/dihapus, file `.conf` langsung dikirim ke Telegram admin
- **Backup harian otomatis** jam 02:00 — full backup dikompres `.zvbak` → kirim ke Telegram
- Backup mencakup: akun SSH+VMess, saldo, data user bot, server, config, SSL
- Restore 1 perintah dari menu install
- Auto hapus backup > 7 hari

### Update Otomatis
- Notifikasi update di menu utama dengan progress bar gradient
- Update via menu **[6] Update** — tidak perlu command manual
- Cek update background setiap hari jam 06:00

### WebSocket & SSL
- WebSocket WS (port 80) + WSS (port 443)
- VMess WS + gRPC via nginx SSL unified
- Catch-all host header — support bug host / SNI
- Let's Encrypt Wildcard SSL via Cloudflare DNS
- Auto renew certificate harian

### Services
- OpenSSH multi-port (22, 500, 40000)
- Dropbear (109, 143)
- Nginx (reverse proxy WS + VMess)
- Xray-core (VMess WS + gRPC, Stats API)
- BadVPN UDPGW (port 7300)
- UDP Custom (1-65535 via TPROXY)
- WebSocket Proxy (ThreadPool + IP tracking)

### Tampilan
- Menu console dengan **gradient RGB true-color** (16M warna)
- Progress bar **%** saat install/update
- Spinner animasi untuk speedtest & proses panjang
- Info server lengkap di header (OS, ISP, City, RAM, CPU, Uptime)

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
│   ├── vmess/          # Manajemen akun VMess
│   ├── server/         # Manajemen server remote + deploy agent
│   ├── info/           # Statistik, info server, speedtest
│   └── system/         # System settings, backup
├── services/
│   ├── nginx/          # Nginx config (SSH WS + VMess WS/gRPC)
│   ├── xray/           # Xray-core config & install
│   ├── websocket/      # WS proxy + IP limit tracking
│   ├── badvpn/         # BadVPN UDPGW
│   ├── dropbear/       # Dropbear SSH
│   └── telegram/       # Bot Telegram (Python/aiogram 3.x)
├── cron/               # Auto task (expired, trial, notify, backup, bw-vmess, ip-limit)
├── utils/              # Colors (gradient), logger, helpers, remote.sh
├── accounts/
│   ├── ssh/            # Data akun SSH (.conf per user)
│   ├── vmess/          # Data akun VMess (.conf per user)
│   ├── saldo/          # Saldo per Telegram user ID
│   └── users/          # Data user terdaftar bot
├── servers/            # Data server remote (.conf + .tg.conf)
├── ssl/                # Sertifikat SSL
├── zv-agent.sh         # Agent SSH untuk remote server
└── zv-vmess-agent.sh   # Agent VMess untuk remote server
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
4. Sertifikat otomatis diinstall & auto renew

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
| autokill | Tiap 10 detik | Kill multi-login SSH via pgrep |
| trial-cleanup | Tiap 1 menit | Hapus akun trial expired |
| ip-limit | Tiap 1 menit | Cek & kick IP limit SSH |
| bw-check | Tiap 10 detik | Cek quota bandwidth SSH |
| bw-vmess | Tiap 5 menit | Cek quota bandwidth VMess |
| tg-notify | Tiap 1 jam | Notif Telegram akan expired |
| expired | Tiap 5 menit | Auto hapus akun expired (SSH + VMess) |
| license-check | 00:05 | Cek lisensi |
| backup | 02:00 | Full backup → Telegram |
| check-update | 06:00 | Cek versi terbaru |

---

## Changelog

### v1.2.0
- **Gradient RGB true-color** di menu console (16M warna, smooth interpolation)
- **Progress bar %** dengan animasi saat install & update
- **Spinner animasi** di speedtest & proses panjang
- **VMess IP limit** via ws-proxy (reject langsung real-time, tidak perlu autokill)
- **Speedtest menu** via librespeed-cli (ping, download, upload, jitter)
- **Banner SSH gradient** — warna per karakter via `<font color="#hex">`
- **Fix expired SSH** — pakai EXPIRED_TS (timestamp) bukan date string, tidak lagi hapus di hari beli
- **Fix autokill SSH** — pakai `pgrep sshd` bukan session file, akurat per koneksi
- **Fix bw-vmess double count** — tambah `--reset` di statsquery
- **Fix zv-vmess-agent** — auto restart Xray setelah rebuild config
- **Fix del-vmess** — rebuild Xray config setelah hapus, UUID tidak tersisa
- Hapus Tripay dari semua komponen (topup manual admin only)
- Header menu: tambah ISP, City, total akun, uptime

### v1.1.0
- **VMess multi-server** — `zv-vmess-agent` untuk kelola VMess di remote VPS
- Server tipe SSH / VMess / Both — filter otomatis di bot dan menu
- Bot: buat/renew/hapus VMess sesuai server tipe
- Admin panel bot: ⚡ Kelola VMess
- Cron expired & bw-vmess via agent (lokal/remote)
- Auto deploy `zv-agent` + `zv-vmess-agent` saat tambah server

### v1.0.4
- Rilis perdana
- SSH Management lengkap (tambah, hapus, edit, renew, lock, unlock)
- Multi-server via zv-agent
- Telegram bot (aiogram 3.x) — beli, renew, trial, saldo, broadcast
- Sistem backup real-time + harian otomatis
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
