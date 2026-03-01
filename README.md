# ZV-Manager

> SSH Tunneling Manager untuk Ubuntu 24.04 LTS  
> Dibangun dari scratch, bersih, modular, dan mudah dikembangkan.

---

## ✨ Fitur

| Fitur | Status |
|---|---|
| SSH WebSocket HTTP (port 80) | ✅ |
| SSH WebSocket HTTPS (port 443) | ✅ |
| HTTP CONNECT Tunnel (HTTP Custom, HTTP Injector, NapsternetV) | ✅ |
| UDP Custom ePro Dev (port 1-65535) | ✅ |
| Dropbear (port 109, 143) | ✅ |
| Nginx SSL Stream + Reverse Proxy | ✅ |
| Manajemen User SSH (add/del/list/renew/lock/unlock) | ✅ |
| Verifikasi koneksi saat tambah server | ✅ |
| Auto-Kill Multi-Login | ✅ |
| Auto-Delete Expired User | ✅ |
| BBR TCP Congestion Control | ✅ |
| Blokir Torrent (iptables) | ✅ |
| Auto Reboot Scheduler | ✅ |
| Multi-Server Manager | ✅ |
| SSH Banner plain text | ✅ |
| Menu CLI Interaktif | ✅ |

---

## 🖥️ Requirement

| | |
|---|---|
| **OS** | Ubuntu 24.04 LTS |
| **Arsitektur** | x86_64 |
| **RAM** | Minimal 512MB |
| **Akses** | Root |
| **Virtualisasi** | KVM / VMware / HyperV (bukan OpenVZ) |

---

## 🚀 Instalasi

Cukup **2 langkah**:

**Langkah 1 — Update sistem:**
```bash
apt update && apt upgrade -y
```

**Langkah 2 — Pasang ZV-Manager:**
```bash
wget -q https://raw.githubusercontent.com/ZenXNF/ZV-Manager/main/zv.sh && bash zv.sh
```

Setelah selesai, ketik `menu` untuk membuka panel:
```bash
menu
```

---

## 🔄 Update

Untuk update ZV-Manager ke versi terbaru tanpa reinstall:

```bash
wget -q https://raw.githubusercontent.com/ZenXNF/ZV-Manager/main/update.sh && bash update.sh
```

Yang diperbarui otomatis:
- Script terbaru dari GitHub disalin ke `/etc/zv-manager/`
- Config nginx, websocket, SSH, dropbear, UDP di-reapply
- Semua service direstart

Yang **tidak tersentuh** saat update:
- Akun SSH yang sudah dibuat (`/etc/zv-manager/accounts/`)
- Daftar server (`/etc/zv-manager/servers/`)
- Sertifikat SSL (`/etc/zv-manager/ssl/`)
- File domain/IP (`/etc/zv-manager/domain`)

---

## 📡 Port Default

| Layanan | Port |
|---|---|
| OpenSSH | 22, 500, 40000 |
| Dropbear | 109, 143 |
| WS HTTP / HTTP CONNECT | 80 |
| WSS HTTPS / HTTP CONNECT SSL | 443 |
| UDP Custom (ePro Dev) | 1-65535 |

---

## 🔧 Arsitektur Teknis

### WebSocket & HTTP CONNECT (Port 443)

Nginx menggunakan modul `stream{}` (bukan `http{}`) untuk port 443, sehingga bekerja di level TCP murni. Ini yang memungkinkan HTTP CONNECT request melewati nginx tanpa mendapat `400 Bad Request`.

```
Client
  │
  ├─ Port 80  → Nginx http{} → 127.0.0.1:8880 → ws-proxy.py
  │
  └─ Port 443 → Nginx stream{} (SSL termination) → 127.0.0.1:8880 → ws-proxy.py
                                                           │
                                                  HTTP CONNECT → SSH :22
                                                  WebSocket    → SSH :22
```

### UDP Custom

Binary UDP Custom dari **ePro Dev** ([http-custom/udp-custom](https://github.com/http-custom/udp-custom)) bekerja dengan memasang rule **iptables TPROXY** yang menginterceptasi semua UDP traffic port **1-65535**. Port `36712` di `config.json` adalah internal listener binary, bukan port yang diisi di aplikasi tunneling.

Di aplikasi (HTTP Custom, dsb.) isi port UDP: **1-65535**

### Multi-Server Manager

Satu VPS (Neva) bisa jadi pusat kendali untuk banyak VPS lain. Data server disimpan di `/etc/zv-manager/servers/nama.conf`. Saat tambah server, koneksi SSH akan diverifikasi terlebih dahulu — jika gagal, server tidak akan disimpan.

> **Catatan:** Menu SSH (buat/hapus akun) hanya bisa diakses setelah minimal 1 server ditambahkan.

---

## 📱 Payload Aplikasi

**WebSocket (HTTP Injector / NapsternetV):**
```
GET / HTTP/1.1[crlf]Host: [domain/ip][crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]
```

**HTTP CONNECT (HTTP Custom):**
```
CONNECT [domain/ip]:443 HTTP/1.0[crlf][crlf]
```

---

## 📁 Struktur Folder

```
ZV-Manager/
├── zv.sh                   # Entry point instalasi (wget one-liner)
├── install.sh              # Installer utama
├── update.sh               # Script updater (aman, tidak hapus akun/server)
├── uninstall.sh            # Uninstaller
├── config.conf             # Konfigurasi global (port, versi, dll)
│
├── core/
│   ├── system.sh           # Install dependencies, swap, BBR, iptables
│   ├── domain.sh           # Ambil IP publik otomatis
│   └── ssl.sh              # Generate sertifikat self-signed otomatis
│
├── services/
│   ├── ssh/                # OpenSSH — port 22, 500, 40000
│   ├── websocket/          # ws-proxy.py (HTTP CONNECT + WebSocket)
│   ├── nginx/              # stream{} port 443 + http{} port 80 & 81
│   ├── dropbear/           # Dropbear — port 109, 143
│   └── udp/                # UDP Custom ePro Dev — 1-65535 via TPROXY
│
├── menu/
│   ├── menu.sh             # Main menu (auto-launch saat SSH login)
│   ├── ssh/                # Kelola akun SSH (add/del/list/renew/lock/unlock)
│   ├── server/             # Multi-server manager (add/list/connect/del)
│   ├── system/             # Restart, status service, clear cache, auto-reboot
│   └── info/               # Info server (IP, OS, RAM, disk, uptime, port)
│
├── utils/
│   ├── colors.sh           # Definisi warna ANSI
│   ├── logger.sh           # print_ok / print_error / print_info / timer
│   ├── checker.sh          # Cek OS, arsitektur, virtualisasi, internet
│   └── helpers.sh          # Helper functions (expired_date, user_exists, dll)
│
└── cron/
    ├── autokill.sh         # Auto-kill sesi melebihi limit (tiap 1 menit)
    └── expired.sh          # Auto-hapus user expired (tiap hari jam 00:02)
```

---

## 📝 License

MIT License — bebas digunakan dan dimodifikasi.

---

> Made with ❤️ — ZV Team
