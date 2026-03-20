<div align="center">

<img src="https://readme-typing-svg.demolab.com?font=JetBrains+Mono&size=26&duration=2500&pause=800&color=00E5FF&center=true&vCenter=true&width=750&lines=ZV-Manager+%E2%80%94+SSH+%26+VMess+%26+VLESS;Multi+Server+%7C+Brain+Architecture;Telegram+Bot+%7C+Auto+Billing;Backup+Otomatis+%7C+Broadcast;Optimized+for+512MB+RAM" alt="ZV-Manager" />

<br/>

![Platform](https://img.shields.io/badge/Ubuntu-24.04%20LTS-orange?style=for-the-badge&logo=ubuntu)
![Telegram](https://img.shields.io/badge/Telegram-@ZenXNF-blue?style=for-the-badge&logo=telegram)
![RAM](https://img.shields.io/badge/RAM-512MB%20ready-purple?style=for-the-badge)

</div>

---

## Overview

ZV-Manager adalah panel manajemen **SSH Tunnel + VMess + VLESS** berbasis console untuk Ubuntu 24.04. Dirancang untuk kebutuhan jualan VPN/SSH dengan arsitektur **Brain VPS** — satu server pusat mengelola banyak remote VPS via agent ringan. Dilengkapi bot Telegram otomatis, sistem saldo, backup harian, dan multi-protokol (SSH + VMess + VLESS via Xray-core).

---

## Fitur

### SSH Management
- Tambah, hapus, edit, renew akun SSH
- Lock / unlock akun
- Auto delete akun expired berdasarkan `EXPIRED_TS` — tepat waktu
- Auto kill multi-login via `pgrep sshd` — real-time tiap 10 detik
- Trial gratis otomatis (batas 1x per user per server)
- Bandwidth tracking via iptables per akun

### VMess Management (Xray-core)
- Tambah, hapus, edit, renew akun VMess
- Enable / disable akun
- Trial VMess 30 menit otomatis
- Monitor bandwidth per akun via Xray Stats API
- Auto disable saat bandwidth habis + notif Telegram
- IP limit enforcement via ws-proxy — real-time
- URL: WS HTTP (80), WS TLS (443), gRPC TLS (443)

### VLESS Management (Xray-core)
- Tambah, hapus, edit, renew akun VLESS
- Enable / disable akun
- Trial VLESS 30 menit otomatis
- Monitor bandwidth per akun via Xray Stats API
- IP limit enforcement via ws-proxy — terpisah dari VMess
- URL: WS HTTP (80), WS TLS (443), gRPC TLS (8443)

### Multi Server (Brain Architecture)
- Kelola banyak VPS dari 1 panel (otak)
- Remote via `zv-agent` (SSH), `zv-vmess-agent` (VMess), `zv-vless-agent` (VLESS)
- Auto deploy agent saat tambah server baru
- Dukungan autentikasi password atau SSH key
- Server tipe: `ssh`, `vmess`, `vless`, `both` (SSH+VMess), `all` (SSH+VMess+VLESS)
- Setiap server punya harga, limit IP, BW, dan max akun sendiri per protokol

### Telegram Bot (Python / aiogram 3.x)
- `/start` → menu inline lengkap
- Buat akun SSH, VMess, VLESS langsung dari bot
- Trial gratis SSH, VMess, VLESS — 1x per user per server
- Sistem saldo — potong otomatis saat beli/renew
- Perpanjang akun SSH, VMess, VLESS dari bot
- Notifikasi otomatis sebelum expired
- Riwayat transaksi & cek saldo
- Broadcast teks ke semua user terdaftar
- **Admin panel**: topup manual, kurangi saldo, hapus akun, cek user, history transaksi

### Backup & Restore
- **Backup harian otomatis** jam 02:00 — full backup `.zvbak` → kirim ke Telegram
- Backup mencakup: akun SSH+VMess+VLESS, saldo, user bot, server, config, SSL
- Format: `zv-panel-TANGGAL.zvbak` (otak) + `zv-server-NAMA-TANGGAL.zvbak` (tunneling)
- Restore dari menu install — recreate semua akun otomatis
- Saat restore, IP server tersimpan di backup — hanya tanya password
- Auto hapus backup lama > 7 hari

### Halaman Web Status
- Status semua server real-time, update tiap 5 menit
- Default tidak aktif — install manual via menu
- Support domain custom + Let's Encrypt SSL
- Saat restore, web status aktif otomatis jika sebelumnya aktif

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
Menu Utama → [7] Update Script
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
├── core/               # License, SSL, Telegram helper, Bandwidth, Banner, VLESS helper
├── menu/
│   ├── ssh/            # Manajemen akun SSH
│   ├── vmess/          # Manajemen akun VMess
│   ├── vless/          # Manajemen akun VLESS
│   ├── server/         # Manajemen server remote + deploy agent
│   ├── info/           # Statistik & info server
│   └── system/         # System settings, backup, Telegram, SSL, Web Status
├── services/
│   ├── nginx/          # Nginx config (SSH WS + VMess/VLESS WS/gRPC)
│   ├── xray/           # Xray-core config & install (VMess + VLESS)
│   ├── websocket/      # WS proxy + IP limit tracking (VMess & VLESS)
│   ├── badvpn/         # BadVPN UDPGW
│   ├── dropbear/       # Dropbear SSH
│   └── telegram/       # Bot Telegram (Python/aiogram 3.x)
├── cron/               # Auto task (expired, bw, notify, backup, ip-limit)
├── utils/              # Colors, logger, helpers, remote.sh
├── accounts/
│   ├── ssh/            # Data akun SSH
│   ├── vmess/          # Data akun VMess
│   ├── vless/          # Data akun VLESS
│   ├── saldo/          # Saldo per Telegram user ID
│   └── users/          # Data user bot
├── servers/            # Data server remote (.conf + .tg.conf)
├── ssl/                # Sertifikat SSL
├── zv-agent.sh         # Agent SSH
├── zv-vmess-agent.sh   # Agent VMess
└── zv-vless-agent.sh   # Agent VLESS
```

---

## Setup Telegram Bot

1. Buat bot di [@BotFather](https://t.me/BotFather)
2. Buka menu: **Sistem → Setup Telegram Bot**
3. Masukkan Bot Token → verifikasi otomatis
4. Masukkan Telegram User ID (cek di [@userinfobot](https://t.me/userinfobot))
5. Bot langsung aktif

---

## Port Default

| Service | Port |
|---|---|
| OpenSSH | 22, 500, 40000 |
| Dropbear | 109, 143 |
| WS / VMess+VLESS (HTTP) | 80 |
| WS SSL / VMess+VLESS (TLS) | 443 |
| Xray VMess WS (internal) | 10001 |
| Xray VMess gRPC (internal) | 10002 |
| Xray VLESS WS (internal) | 10004 |
| Xray VLESS gRPC (internal) | 10005 |
| Xray Stats API (internal) | 10085 |
| BadVPN UDPGW | 7300 |
| UDP Custom | 1-65535 |

---

## Cron Schedule

| Cron | Jadwal | Fungsi |
|---|---|---|
| autokill | Tiap 10 detik | Kill multi-login SSH |
| trial-cleanup | Tiap 1 menit | Hapus akun trial expired |
| ip-limit | Tiap 1 menit | Cek & kick IP limit SSH |
| bw-check | Tiap 10 detik | Cek quota bandwidth SSH |
| bw-vmess | Tiap 5 menit | Cek quota bandwidth VMess |
| bw-vless | Tiap 5 menit | Cek quota bandwidth VLESS |
| tg-notify | Tiap 1 jam | Notif Telegram akan expired |
| expired | Tiap 5 menit | Auto hapus akun expired (SSH+VMess+VLESS) |
| worker-check | Tiap 5 menit | Monitor status server worker |
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
