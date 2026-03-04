<div align="center">

<!-- Animated SVG header -->
<img src="https://readme-typing-svg.demolab.com?font=JetBrains+Mono&size=28&duration=3000&pause=1000&color=00E5FF&center=true&vCenter=true&width=600&lines=ZV-Manager+SSH+Tunnel;Auto+Deploy+%7C+Multi+Server;Telegram+Bot+%7C+Full+Panel" alt="ZV-Manager" />

<br/>

![Version](https://img.shields.io/badge/version-1.0.0-00e5ff?style=for-the-badge&logo=github)
![Platform](https://img.shields.io/badge/platform-Ubuntu%2024.04-orange?style=for-the-badge&logo=ubuntu)
![License](https://img.shields.io/badge/license-MIT-green?style=for-the-badge)
![Telegram](https://img.shields.io/badge/Telegram-@ZenXNF-blue?style=for-the-badge&logo=telegram)

</div>

---

## Overview

ZV-Manager adalah panel manajemen SSH Tunnel berbasis console untuk Ubuntu 24.04. Dirancang untuk kebutuhan jualan VPN/SSH dengan fitur lengkap mulai dari manajemen akun, multi-server, hingga bot Telegram otomatis.

---

## Fitur

### SSH Management
- Tambah, hapus, edit, renew akun SSH
- Lock / unlock akun
- Monitor akun online real-time
- Auto delete akun expired (cron harian)
- Auto kill multi-login (cron per menit)

### Multi Server
- Kelola banyak VPS dari 1 panel (otak)
- Remote via `zv-agent` (lightweight, tanpa menu)
- Dukungan SSH key atau password (sshpass)

### Telegram Bot
- `/start` → menu inline lengkap
- Buat akun SSH langsung dari Telegram
- Trial gratis 30 menit (1x/hari)
- Sistem saldo — potong otomatis saat beli
- Notifikasi otomatis 20 jam sebelum expired
- Info server: harga, quota, limit IP, total akun

### WebSocket & SSL
- WebSocket WS (port 80) + WSS (port 443)
- Catch-all host header — support bug host / SNI
- Let's Encrypt Wildcard SSL via Cloudflare DNS
- Auto renew certificate

### Services
- OpenSSH multi-port (22, 500, 40000)
- Dropbear (109, 143)
- Nginx (reverse proxy WS)
- Stunnel4 (SSL termination)
- BadVPN UDPGW (port 7300)
- UDP Custom (1-65535)

### Panel
- Sistem lisensi (grace period, auto uninstall)
- Edit server banner dari menu
- Edit banner tampil di NetMod / HTTP Custom
- Backup & manajemen saldo via console

---

## Instalasi

```bash
wget -q https://raw.githubusercontent.com/ZenXNF/ZV-Manager/main/zv.sh && bash zv.sh
```

**Requirement:**
- Ubuntu 24.04 LTS
- Akses root
- Koneksi internet

---

## Update

```bash
wget -q https://raw.githubusercontent.com/ZenXNF/ZV-Manager/main/update.sh && bash update.sh
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
├── core/           # License, SSL, Telegram helper, Banner
├── menu/
│   ├── ssh/        # Manajemen akun SSH
│   ├── server/     # Manajemen server
│   └── system/     # System settings
├── services/
│   ├── nginx/      # Nginx config
│   ├── websocket/  # WS proxy + Stunnel
│   ├── badvpn/     # BadVPN UDPGW
│   ├── dropbear/   # Dropbear SSH
│   └── telegram/   # Bot Telegram
├── cron/           # Auto task (expired, trial, notify)
├── utils/          # Colors, logger, helpers
├── accounts/ssh/   # Data akun (.conf per user)
├── accounts/saldo/ # Saldo per Telegram user ID
└── servers/        # Data server remote
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

---

## Kontak

- Telegram : [@ZenXNF](https://t.me/ZenXNF)
- GitHub   : [ZenXNF/ZV-Manager](https://github.com/ZenXNF/ZV-Manager)

---

<div align="center">

Made with ❤️ by ZenXNF

</div>
