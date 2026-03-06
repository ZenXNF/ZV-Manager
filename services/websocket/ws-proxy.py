#!/usr/bin/env python3
# ============================================================
#   ZV-Manager - WebSocket & HTTP CONNECT SSH Proxy
#   Optimized: ThreadPoolExecutor (max 200) untuk VPS 512MB
#   + Username tracking dari URL path untuk monitor online
# ============================================================

import socket
import select
import signal
import sys
import logging
import threading
import os
from concurrent.futures import ThreadPoolExecutor

LISTENING_ADDR = '0.0.0.0'
LISTENING_PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 80
DEFAULT_HOST   = '127.0.0.1'
DEFAULT_PORT   = 22
BUFLEN         = 8192
TIMEOUT        = 120
MAX_WORKERS    = 200
LISTEN_BACKLOG = 50
ONLINE_FILE    = '/tmp/zv-ws-online'

logging.disable(logging.CRITICAL)

WS_RESPONSE      = "HTTP/1.1 101 Switching Protocols\r\nContent-Length: 0\r\n\r\nHTTP/1.1 200 ZV-Manager\r\n\r\n"
CONNECT_RESPONSE = "HTTP/1.1 200 Connection Established\r\n\r\n"

# ── Username tracker (thread-safe) ───────────────────────
_lock    = threading.Lock()
_counter = {}   # username -> jumlah koneksi aktif

def _track_add(username: str):
    if not username:
        return
    with _lock:
        _counter[username] = _counter.get(username, 0) + 1
        _write_online()

def _track_remove(username: str):
    if not username:
        return
    with _lock:
        if username in _counter:
            _counter[username] -= 1
            if _counter[username] <= 0:
                del _counter[username]
        _write_online()

def _write_online():
    """Tulis username aktif ke file — dibaca monitor-online.sh"""
    try:
        tmp = ONLINE_FILE + '.tmp'
        with open(tmp, 'w') as f:
            for u, c in _counter.items():
                if c > 0:
                    f.write(f"{u}:{c}\n")
        os.replace(tmp, ONLINE_FILE)
    except Exception:
        pass

def _parse_username(data: str) -> str:
    """Ambil username dari URL path, misal GET /zenxuuser HTTP/1.1"""
    try:
        first = data.split('\r\n')[0]
        parts = first.split()
        if len(parts) >= 2:
            path = parts[1].lstrip('/')
            # Ambil bagian pertama sebelum / berikutnya
            username = path.split('/')[0].split('?')[0].strip()
            # Validasi: huruf kecil/angka, minimal 2 karakter
            if username and len(username) >= 2 and username.replace('-','').replace('_','').isalnum():
                return username
    except Exception:
        pass
    return ''


def handle_connection(client_sock):
    target   = None
    username = ''
    try:
        client_sock.settimeout(30)
        raw = b''
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
        first_line  = data.split('\r\n')[0]

        if first_line.upper().startswith('CONNECT'):
            parts  = first_line.split()
            tgt    = parts[1] if len(parts) >= 2 else ''
            host, port = (tgt.rsplit(':', 1) if ':' in tgt else (tgt, str(DEFAULT_PORT)))
            try: port = int(port)
            except ValueError: port = DEFAULT_PORT
            if host not in ('127.0.0.1', 'localhost'):
                host, port = DEFAULT_HOST, DEFAULT_PORT
            target = socket.create_connection((host, port), timeout=10)
            target.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            client_sock.sendall(CONNECT_RESPONSE.encode())
            _relay(client_sock, target, leftover)
        else:
            # WebSocket / fallback — parse username dari URL
            username = _parse_username(data)
            _track_add(username)
            target = socket.create_connection((DEFAULT_HOST, DEFAULT_PORT), timeout=10)
            target.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            client_sock.sendall(WS_RESPONSE.encode())
            _relay(client_sock, target, leftover)

    except Exception:
        pass
    finally:
        _track_remove(username)
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


def main():
    executor = ThreadPoolExecutor(max_workers=MAX_WORKERS)
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.settimeout(2)
    srv.bind((LISTENING_ADDR, LISTENING_PORT))
    srv.listen(LISTEN_BACKLOG)
    print(f"[ZV] Proxy :{LISTENING_PORT} → SSH {DEFAULT_HOST}:{DEFAULT_PORT} (max {MAX_WORKERS} threads)")

    # Bersihkan file online saat start
    try:
        open(ONLINE_FILE, 'w').close()
    except Exception:
        pass

    def _stop(sig, frame):
        print("\n[ZV] Proxy stopped.")
        try: open(ONLINE_FILE, 'w').close()
        except Exception: pass
        executor.shutdown(wait=False)
        srv.close()
        sys.exit(0)

    signal.signal(signal.SIGINT,  _stop)
    signal.signal(signal.SIGTERM, _stop)

    while True:
        try:
            client, _ = srv.accept()
            client.setblocking(True)
            client.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            executor.submit(handle_connection, client)
        except socket.timeout:
            continue
        except Exception:
            break


if __name__ == '__main__':
    main()
