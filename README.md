# ZV-Manager

> SSH Tunneling Manager untuk Ubuntu 24.04 LTS  
> Dibangun dari scratch, bersih, modular, dan mudah dikembangkan.

---

## ✨ Fitur

| Fitur | Status |
|---|---|
| SSH WebSocket HTTP (port 80) | ✅ |
| SSH WebSocket HTTPS (port 443) | ✅ |
| HTTP CONNECT Tunnel (HTTP Custom, HTTP Injector) | ✅ |
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
| Multi-Server Manager | ✅ |
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
wget -q https://raw.githubusercontent.com/ZenXNF/ZV-Manager/main/zv.sh && chmod +x zv.sh && bash zv.sh
```

Setelah selesai, ketik `menu` untuk membuka panel:
```bash
menu
```

---

## 📡 Port Default

| Layanan | Port |
|---|---|
| OpenSSH | 22, 500, 40000 |
| Dropbear | 109, 143 |
| WS / HTTP CONNECT HTTP | 80 |
| WS / HTTP CONNECT HTTPS | 443 |
| UDP Custom | 1-65535 |
| UDPGW (BadVPN) | 7100-7900 |

---

## 📱 Payload

**WebSocket (HTTP Injector / NapsternetV):**
```
GET / HTTP/1.1[crlf]Host: [domain/ip][crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]
```

**HTTP CONNECT (HTTP Custom / Termius):**
```
CONNECT [domain/ip]:22 HTTP/1.0[crlf][crlf]
```

---

## 🖧 Multi-Server Manager

Neva bisa jadi pusat kendali untuk banyak VPS lain.  
Masuk ke **Menu → Manajemen Server** untuk menambah, melihat, menghapus, dan connect ke server lain langsung dari Neva.

Neva sendiri juga bisa ditambahkan sebagai server (otak sekaligus tunnel).

---

## 📁 Struktur Folder

```
ZV-Manager/
├── zv.sh                   # Entry point one-liner (wget)
├── install.sh              # Installer utama
├── config.conf             # Konfigurasi global
│
├── core/
│   ├── system.sh
│   ├── domain.sh
│   └── ssl.sh
│
├── services/
│   ├── ssh/
│   ├── websocket/          # Support WS + HTTP CONNECT
│   ├── nginx/
│   ├── dropbear/
│   └── udp/
│
├── menu/
│   ├── menu.sh
│   ├── ssh/
│   ├── server/             # Multi-server manager
│   ├── system/
│   └── info/
│
├── utils/
│   ├── colors.sh
│   ├── logger.sh
│   ├── checker.sh
│   └── helpers.sh
│
└── cron/
    ├── autokill.sh
    └── expired.sh
```

---

## 📝 License

MIT License — bebas digunakan dan dimodifikasi.

---

> Made with ❤️ — ZV Team
