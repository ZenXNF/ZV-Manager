#!/usr/bin/env python3
# ============================================================
#   ZV-Manager - WebSocket & HTTP CONNECT SSH Proxy
#   Port 8880 : plain TCP (dari nginx:18443 yang sudah TLS)
#   Port 8881 : TLS langsung (dari nginx ssl_preread bug SNI)
#   Routing (sama untuk keduanya setelah TLS):
#     CONNECT host:PORT → SSH PORT (22/109/143/500/40000)
#     GET /vmess (WS upgrade) → Xray VMess :10001
#     GET / (WS upgrade) → SSH :22
#     GET biasa (browser) → nginx :8080
#     SSH banner langsung → SSH :22
# ============================================================
import socket
import select
import signal
import ssl
import sys
import os
import json
import glob
import threading
import logging
from concurrent.futures import ThreadPoolExecutor

LISTENING_ADDR = '0.0.0.0'
LISTENING_PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8880
TLS_PORT       = 8881
SSL_CERT       = '/etc/zv-manager/ssl/cert.pem'
SSL_KEY        = '/etc/zv-manager/ssl/key.pem'
DEFAULT_HOST   = '127.0.0.1'
DEFAULT_PORT   = 22
XRAY_PORT      = 10001
XRAY_VLESS_PORT = 10004
NGINX_PORT     = 8080
BUFLEN         = 8192
TIMEOUT        = 120
MAX_WORKERS    = 200
LISTEN_BACKLOG = 50
VMESS_ACTIVE_FILE = '/tmp/zv-vmess-active.json'
VLESS_ACTIVE_FILE = '/tmp/zv-vless-active.json'
ZV_SERVERS_DIR    = '/etc/zv-manager/servers'

logging.disable(logging.CRITICAL)
DEBUG = False

SSH_PORTS = {22, 109, 143, 500, 40000}

WS_RESPONSE      = "HTTP/1.1 101 Switching Protocols\r\nContent-Length: 0\r\n\r\nHTTP/1.1 200 ZV-Manager\r\n\r\n"
CONNECT_RESPONSE = "HTTP/1.1 200 Connection Established\r\n\r\n"

# ── VMess IP tracking (thread-safe) ──────────────────────────
_vmess_lock    = threading.Lock()
_vmess_active  = {}   # {client_ip: active_connection_count}

# ── VLESS IP tracking (thread-safe) ──────────────────────────
_vless_lock    = threading.Lock()
_vless_active  = {}   # {client_ip: active_connection_count}

def _vmess_get_limit():
    """Baca TG_LIMIT_IP_VMESS dari semua server tg.conf, ambil nilai terkecil (paling ketat)"""
    limit = 2  # default
    try:
        for f in glob.glob(f'{ZV_SERVERS_DIR}/*.tg.conf'):
            for line in open(f):
                if line.startswith('TG_LIMIT_IP_VMESS='):
                    v = line.split('=',1)[1].strip().strip('"\'')
                    try: limit = min(limit, int(v))
                    except ValueError: pass
    except Exception:
        pass
    return limit

def _vmess_register(client_ip):
    """Tambah koneksi aktif untuk IP ini. Return True jika diizinkan, False jika melebihi limit."""
    limit = _vmess_get_limit()
    with _vmess_lock:
        current_ips = set(ip for ip, cnt in _vmess_active.items() if cnt > 0)
        # Izinkan jika IP sudah terdaftar (multiple conn dari IP sama) atau jumlah unique IP belum >= limit
        if client_ip not in current_ips and len(current_ips) >= limit:
            return False
        _vmess_active[client_ip] = _vmess_active.get(client_ip, 0) + 1
        _vmess_save()
        return True

def _vmess_unregister(client_ip):
    """Kurangi koneksi aktif untuk IP ini."""
    with _vmess_lock:
        if client_ip in _vmess_active:
            _vmess_active[client_ip] -= 1
            if _vmess_active[client_ip] <= 0:
                del _vmess_active[client_ip]
        _vmess_save()

def _vmess_save():
    """Simpan state ke file (harus dipanggil dalam _vmess_lock)."""
    try:
        with open(VMESS_ACTIVE_FILE, 'w') as fp:
            json.dump(_vmess_active, fp)
    except Exception:
        pass

def _vless_get_limit():
    """Baca TG_LIMIT_IP_VLESS dari server tg.conf."""
    limit = 2
    try:
        for f in glob.glob(f'{ZV_SERVERS_DIR}/*.tg.conf'):
            for line in open(f):
                if line.startswith('TG_LIMIT_IP_VLESS='):
                    v = line.split('=',1)[1].strip().strip('"\'')
                    try: limit = min(limit, int(v))
                    except ValueError: pass
    except Exception:
        pass
    return limit

def _vless_register(client_ip):
    limit = _vless_get_limit()
    with _vless_lock:
        current_ips = set(ip for ip, cnt in _vless_active.items() if cnt > 0)
        if client_ip not in current_ips and len(current_ips) >= limit:
            return False
        _vless_active[client_ip] = _vless_active.get(client_ip, 0) + 1
        _vless_save()
        return True

def _vless_unregister(client_ip):
    with _vless_lock:
        if client_ip in _vless_active:
            _vless_active[client_ip] -= 1
            if _vless_active[client_ip] <= 0:
                del _vless_active[client_ip]
        _vless_save()

def _vless_save():
    try:
        with open(VLESS_ACTIVE_FILE, 'w') as fp:
            json.dump(_vless_active, fp)
    except Exception:
        pass

def _read_proxy_protocol(sock) -> tuple:
    """
    Baca PROXY protocol v1 header dari socket jika ada.
    Return: (src_ip, leftover_bytes)
    leftover_bytes = data yang sudah dibaca tapi bukan PROXY header
    """
    try:
        # Baca 6 byte pertama untuk cek apakah PROXY header
        peek = b''
        while len(peek) < 6:
            c = sock.recv(1)
            if not c:
                return ('', peek)
            peek += c

        if not peek.startswith(b'PROXY '):
            # Bukan PROXY protocol, kembalikan data
            return ('', peek)

        # Baca sisa sampai \r\n
        line = peek
        while len(line) < 108:
            c = sock.recv(1)
            if not c:
                break
            line += c
            if line.endswith(b'\r\n'):
                break

        text = line.decode('ascii', errors='ignore').strip()
        parts = text.split()
        if len(parts) >= 3 and parts[2] not in ('UNKNOWN',):
            return (parts[2], b'')
    except Exception:
        pass
    return ('', b'')

def _parse_real_ip(data: str, fallback: str) -> str:
    """Ambil IP asli dari X-Real-IP atau X-Forwarded-For header."""
    for line in data.split('\r\n'):
        l = line.lower()
        if l.startswith('x-real-ip:'):
            ip = line.split(':', 1)[1].strip()
            if ip:
                return ip
        elif l.startswith('x-forwarded-for:'):
            ip = line.split(':', 1)[1].split(',')[0].strip()
            if ip:
                return ip
    return fallback

def _parse_path(data: str) -> str:
    first = data.split('\r\n')[0]
    parts = first.split()
    return parts[1] if len(parts) >= 2 else '/'

def handle_connection(client_sock, client_ip='unknown'):
    target = None
    vmess_registered = False
    vmess_real_ip = None
    vless_registered = False
    vless_real_ip = None
    try:
        client_sock.settimeout(30)

        # Baca PROXY protocol header jika ada (dari nginx stream proxy_protocol on)
        proxy_ip, proxy_leftover = _read_proxy_protocol(client_sock)
        if DEBUG: print(f"[ZV] PROXY proto: ip={proxy_ip!r} leftover={proxy_leftover[:20]!r}", flush=True)
        if proxy_ip:
            client_ip = proxy_ip

        raw = proxy_leftover  # Data yang sudah dibaca sebelum header HTTP
        try:
            while b'\r\n\r\n' not in raw:
                chunk = client_sock.recv(BUFLEN)
                if not chunk:
                    return
                raw += chunk
                if raw.startswith(b'SSH-'):
                    break
                if len(raw) > BUFLEN:
                    break
        except Exception:
            return
        client_sock.settimeout(None)

        # ── SSH banner langsung ──────────────────────────────
        if raw.startswith(b'SSH-'):
            target = socket.create_connection((DEFAULT_HOST, DEFAULT_PORT), timeout=10)
            target.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            banner = target.recv(BUFLEN)
            client_sock.sendall(banner)
            target.sendall(raw)
            _relay(client_sock, target)
            return

        header_end  = raw.find(b'\r\n\r\n') + 4
        headers_raw = raw[:header_end]
        leftover    = raw[header_end:]
        data        = headers_raw.decode('utf-8', errors='ignore')
        first_line  = data.split('\r\n')[0].upper()

        # ── CONNECT → SSH tunnel ─────────────────────────────
        if first_line.startswith('CONNECT'):
            parts = first_line.split()
            tgt   = parts[1] if len(parts) >= 2 else ''
            if ':' in tgt:
                _, p = tgt.rsplit(':', 1)
                try:
                    p = int(p)
                except ValueError:
                    p = DEFAULT_PORT
            else:
                p = DEFAULT_PORT
            target_port = p if p in SSH_PORTS else DEFAULT_PORT
            target = socket.create_connection((DEFAULT_HOST, target_port), timeout=10)
            target.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            client_sock.sendall(CONNECT_RESPONSE.encode())
            _relay(client_sock, target, leftover)

        # ── GET → VMess WS / SSH WS / browser ───────────────
        elif first_line.startswith('GET'):
            path = _parse_path(data)
            is_ws = 'upgrade' in data.lower() and 'websocket' in data.lower()
            if path.startswith('/vmess') and is_ws:
                # Ambil IP asli dari header (nginx forward X-Real-IP)
                real_ip = _parse_real_ip(data, client_ip)
                if DEBUG: print(f"[ZV] VMess conn client_ip={client_ip} real_ip={real_ip}", flush=True)
                # Cek dan register VMess IP limit
                if not _vmess_register(real_ip):
                    if DEBUG: print(f"[ZV] VMess REJECTED {real_ip}", flush=True)
                    try:
                        client_sock.sendall(b'HTTP/1.1 429 Too Many Connections\r\n\r\n')
                    except Exception:
                        pass
                    return
                vmess_registered = True
                vmess_real_ip = real_ip
                target = socket.create_connection((DEFAULT_HOST, XRAY_PORT), timeout=10)
                target.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                target.sendall(raw)
                _relay(client_sock, target, leftover)
            elif path.startswith('/vless') and is_ws:
                real_ip = _parse_real_ip(data, client_ip)
                if DEBUG: print(f"[ZV] VLESS conn client_ip={client_ip} real_ip={real_ip}", flush=True)
                if not _vless_register(real_ip):
                    if DEBUG: print(f"[ZV] VLESS REJECTED {real_ip}", flush=True)
                    try:
                        client_sock.sendall(b'HTTP/1.1 429 Too Many Connections\r\n\r\n')
                    except Exception:
                        pass
                    return
                vless_registered = True
                vless_real_ip = real_ip
                target = socket.create_connection((DEFAULT_HOST, XRAY_VLESS_PORT), timeout=10)
                target.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                target.sendall(raw)
                _relay(client_sock, target, leftover)
            elif is_ws:
                target = socket.create_connection((DEFAULT_HOST, DEFAULT_PORT), timeout=10)
                target.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                client_sock.sendall(WS_RESPONSE.encode())
                _relay(client_sock, target, leftover)
            else:
                # Browser biasa → nginx status/api page
                target = socket.create_connection((DEFAULT_HOST, NGINX_PORT), timeout=10)
                target.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                target.sendall(raw)
                _relay(client_sock, target, leftover)

        # ── Fallback → SSH ───────────────────────────────────
        else:
            target = socket.create_connection((DEFAULT_HOST, DEFAULT_PORT), timeout=10)
            target.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            client_sock.sendall(WS_RESPONSE.encode())
            _relay(client_sock, target, leftover)

    except Exception as e:
        if DEBUG: print(f"[ZV] ERR client={client_ip}: {e}", flush=True)
        pass
    finally:
        if vmess_registered and vmess_real_ip:
            _vmess_unregister(vmess_real_ip)
        if vless_registered and vless_real_ip:
            _vless_unregister(vless_real_ip)
        for s in (client_sock, target):
            if s:
                try: s.close()
                except Exception: pass

def _relay(client, target, leftover=b''):
    if leftover:
        try: target.sendall(leftover)
        except Exception: return
    socs = [client, target]
    idle = 0
    while True:
        idle += 1
        try:
            readable, _, exc = select.select(socs, [], socs, 3)
        except Exception:
            break
        if exc:
            break
        if readable:
            for sock in readable:
                try:
                    data = sock.recv(BUFLEN)
                    if not data:
                        return
                    dest = target if sock is client else client
                    dest.sendall(data)
                    idle = 0
                except Exception:
                    return
        if idle >= TIMEOUT:
            break

def _make_server(addr, port):
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.settimeout(2)
    srv.bind((addr, port))
    srv.listen(LISTEN_BACKLOG)
    return srv

def main():
    executor = ThreadPoolExecutor(max_workers=MAX_WORKERS)

    # Plain server (dari nginx:18443 yang sudah TLS terminate)
    plain_srv = _make_server(LISTENING_ADDR, LISTENING_PORT)

    # TLS server (dari nginx ssl_preread bug SNI — belum di-terminate)
    tls_ctx = None
    tls_srv = None
    if os.path.exists(SSL_CERT) and os.path.exists(SSL_KEY):
        try:
            tls_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            tls_ctx.load_cert_chain(SSL_CERT, SSL_KEY)
            tls_srv = _make_server(LISTENING_ADDR, TLS_PORT)
        except Exception as e:
            print(f"[ZV] TLS setup gagal: {e} — port {TLS_PORT} tidak aktif")
    else:
        print(f"[ZV] SSL cert tidak ditemukan — port {TLS_PORT} tidak aktif")

    ports_str = ', '.join(str(p) for p in sorted(SSH_PORTS))
    tls_info  = f" | TLS :{TLS_PORT}" if tls_srv else ""
    print(f"[ZV] Proxy :{LISTENING_PORT} → SSH [{ports_str}] | VMess :{XRAY_PORT} (max {MAX_WORKERS} threads){tls_info}")

    servers = [plain_srv]
    if tls_srv:
        servers.append(tls_srv)

    def _stop(sig, frame):
        print("\n[ZV] Proxy stopped.")
        executor.shutdown(wait=False)
        for s in servers:
            try: s.close()
            except Exception: pass
        sys.exit(0)

    signal.signal(signal.SIGINT,  _stop)
    signal.signal(signal.SIGTERM, _stop)

    while True:
        try:
            readable, _, _ = select.select(servers, [], [], 2)
        except Exception:
            break
        for srv in readable:
            try:
                client, addr = srv.accept()
                client_ip = addr[0] if addr else 'unknown'
                client.setblocking(True)
                client.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                # Wrap TLS jika dari tls_srv
                if tls_srv and srv is tls_srv:
                    try:
                        client = tls_ctx.wrap_socket(client, server_side=True)
                    except ssl.SSLError:
                        try: client.close()
                        except Exception: pass
                        continue
                executor.submit(handle_connection, client, client_ip)
            except socket.timeout:
                continue
            except Exception:
                continue

if __name__ == '__main__':
    main()
