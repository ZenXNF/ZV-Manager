#!/usr/bin/env python3
# ============================================================
#   ZV-Manager - WebSocket & HTTP CONNECT SSH Proxy
#   Optimized: ThreadPoolExecutor (max 200) untuk VPS 512MB
#   Routing:
#     CONNECT host:PORT → SSH PORT (22/109/143/500/40000)
#     GET /vmess (WS upgrade) → Xray VMess :10001
#     GET / (WS upgrade) → SSH :22
#     SSH- banner langsung → SSH :22
# ============================================================

import socket
import select
import signal
import sys
import logging
from concurrent.futures import ThreadPoolExecutor

LISTENING_ADDR = '0.0.0.0'
LISTENING_PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8880
DEFAULT_HOST   = '127.0.0.1'
DEFAULT_PORT   = 22
XRAY_PORT      = 10001   # Xray VMess WebSocket internal
BUFLEN         = 8192
TIMEOUT        = 120
MAX_WORKERS    = 200
LISTEN_BACKLOG = 50
logging.disable(logging.CRITICAL)

# Port SSH valid — CONNECT ke port ini diteruskan ke loopback:port
SSH_PORTS = {22, 109, 143, 500, 40000}

WS_RESPONSE      = "HTTP/1.1 101 Switching Protocols\r\nContent-Length: 0\r\n\r\nHTTP/1.1 200 ZV-Manager\r\n\r\n"
CONNECT_RESPONSE = "HTTP/1.1 200 Connection Established\r\n\r\n"


def _parse_path(data: str) -> str:
    """Ambil path dari request line pertama."""
    first = data.split('\r\n')[0]
    parts = first.split()
    return parts[1] if len(parts) >= 2 else '/'


def handle_connection(client_sock):
    target = None
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

        # ── Koneksi SSH langsung (tanpa HTTP header) ─────────
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

        # ── HTTP CONNECT → SSH tunnel ─────────────────────────
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

        # ── WebSocket GET /vmess → Xray VMess ────────────────
        elif first_line.startswith('GET'):
            path = _parse_path(data)
            if path.startswith('/vmess'):
                # Forward seluruh WS upgrade request ke Xray
                target = socket.create_connection((DEFAULT_HOST, XRAY_PORT), timeout=10)
                target.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                target.sendall(raw)
                _relay(client_sock, target, leftover)
            else:
                # WebSocket biasa → SSH
                target = socket.create_connection((DEFAULT_HOST, DEFAULT_PORT), timeout=10)
                target.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                client_sock.sendall(WS_RESPONSE.encode())
                _relay(client_sock, target, leftover)

        # ── Fallback → SSH ────────────────────────────────────
        else:
            target = socket.create_connection((DEFAULT_HOST, DEFAULT_PORT), timeout=10)
            target.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            client_sock.sendall(WS_RESPONSE.encode())
            _relay(client_sock, target, leftover)

    except Exception:
        pass
    finally:
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
    ports_str = ', '.join(str(p) for p in sorted(SSH_PORTS))
    print(f"[ZV] Proxy :{LISTENING_PORT} → SSH [{ports_str}] | VMess :{XRAY_PORT} (max {MAX_WORKERS} threads)")

    def _stop(sig, frame):
        print("\n[ZV] Proxy stopped.")
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
