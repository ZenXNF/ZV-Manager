# ZV-Manager

> SSH Tunneling Manager untuk Ubuntu 24.04 LTS  
> Dibangun dari scratch, bersih, modular, dan mudah dikembangkan.

---

## ✨ Fitur

| Fitur | Status |
|---|---|
| SSH WebSocket HTTP (port 80) | ✅ |
| SSH WebSocket HTTPS (port 443) | ✅ |
| UDP Custom (port 1-65535) | ✅ |
| Dropbear (port 109, 143) | ✅ |
| Nginx SSL Reverse Proxy | ✅ |
| Manajemen User SSH (add/del/list/renew) | ✅ |
| Auto-Kill Multi-Login | ✅ |
| Auto-Delete Expired User | ✅ |
| Lock / Unlock User | ✅ |
| BBR TCP Congestion Control | ✅ |
| Blokir Torrent (iptables) | ✅ |
| Auto Reboot Scheduler | ✅ |
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

```bash
git clone https://github.com/yourusername/ZV-Manager.git
cd ZV-Manager
chmod +x install.sh
./install.sh
```

Setelah instalasi selesai, ketik `menu` untuk membuka panel:

```bash
menu
```

---

## 📁 Struktur Folder

```
ZV-Manager/
├── install.sh              # Entry point instalasi
├── config.conf             # Konfigurasi global (port, timezone, dll)
│
├── core/                   # Setup inti sistem
│   ├── system.sh           # Update OS, dependencies, BBR
│   ├── domain.sh           # Setup domain / IP
│   └── ssl.sh              # SSL (self-signed / Let's Encrypt)
│
├── services/               # Setiap layanan berdiri sendiri
│   ├── ssh/                # OpenSSH setup
│   ├── websocket/          # WebSocket Python3 proxy
│   ├── nginx/              # Nginx reverse proxy
│   ├── dropbear/           # Dropbear SSH
│   └── udp/                # UDP Custom + BadVPN fallback
│
├── menu/                   # CLI interactive menu
│   ├── menu.sh             # Menu utama
│   ├── ssh/                # User management SSH
│   ├── system/             # System & service management
│   └── info/               # Info server
│
├── utils/                  # Helper functions
│   ├── colors.sh
│   ├── logger.sh
│   ├── checker.sh
│   └── helpers.sh
│
└── cron/                   # Cron jobs
    ├── autokill.sh         # Auto-kill multi-login
    └── expired.sh          # Auto-delete expired users
```

---

## ⚙️ Konfigurasi

Edit `config.conf` sebelum instalasi untuk mengubah port default:

```bash
# SSH Ports
SSH_PORT=22
SSH_PORT_2=500
SSH_PORT_3=40000

# WebSocket
WS_PORT=80
WSS_PORT=443

# Dropbear
DROPBEAR_PORT=109
DROPBEAR_PORT_2=143
```

---

## 📡 Port Default

| Layanan | Port |
|---|---|
| OpenSSH | 22, 500, 40000 |
| Dropbear | 109, 143 |
| WebSocket HTTP | 80 |
| WebSocket HTTPS | 443 |
| UDP Custom | 1-65535 |
| UDPGW (BadVPN) | 7100-7900 |
| Nginx Web | 81 |

---

## 📱 Payload HTTP Injector / NapsternetV

```
GET / HTTP/1.1[crlf]Host: [domain/ip][crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]
```

---

## 📝 License

MIT License — bebas digunakan dan dimodifikasi.

---

> Made with ❤️ — ZV Team
