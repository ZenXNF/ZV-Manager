#!/usr/bin/env python3
# ============================================================
#   ZV-Manager - WebSocket SSH Proxy
#   Compatible: Python 3.x (Ubuntu 24.04)
#   Rewritten from legacy Python2 scripts
# ============================================================

import socket
import threading
import select
import signal
import sys
import time

# --- Konfigurasi ---
LISTENING_ADDR = '0.0.0.0'
LISTENING_PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 80
DEFAULT_HOST   = '127.0.0.1'
DEFAULT_PORT   = 22
BUFLEN         = 4096 * 4
TIMEOUT        = 60

# Response WebSocket HTTP 101
WS_RESPONSE = (
    "HTTP/1.1 101 Switching Protocols\r\n"
    "Content-Length: 0\r\n"
    "\r\n"
    "HTTP/1.1 200 ZV-Manager WS\r\n"
    "\r\n"
)


class ConnectionHandler(threading.Thread):
    def __init__(self, client_sock, addr):
        threading.Thread.__init__(self)
        self.client      = client_sock
        self.addr        = addr
        self.target      = None
        self.client_closed = False
        self.target_closed = True
        self.daemon      = True

    def run(self):
        try:
            self.handle()
        except Exception:
            pass
        finally:
            self._close()

    def handle(self):
        # Terima HTTP request dari client
        data = self.client.recv(BUFLEN).decode('utf-8', errors='ignore')

        # Cari X-Real-Host header (opsional, untuk custom target)
        target_host, target_port = self._parse_target(data)

        # Hanya boleh connect ke localhost (keamanan)
        if target_host not in ('127.0.0.1', 'localhost'):
            target_host = DEFAULT_HOST
            target_port = DEFAULT_PORT

        # Connect ke SSH
        self.target = socket.create_connection((target_host, target_port))
        self.target_closed = False

        # Kirim response HTTP 101
        self.client.sendall(WS_RESPONSE.encode())

        # Mulai relay data dua arah
        self._relay()

    def _parse_target(self, data):
        host = DEFAULT_HOST
        port = DEFAULT_PORT

        for line in data.split('\r\n'):
            if line.lower().startswith('x-real-host:'):
                val = line.split(':', 1)[1].strip()
                if ':' in val:
                    h, p = val.rsplit(':', 1)
                    host = h.strip()
                    try:
                        port = int(p.strip())
                    except ValueError:
                        port = DEFAULT_PORT
                else:
                    host = val
        return host, port

    def _relay(self):
        socs = [self.client, self.target]
        idle = 0

        while True:
            idle += 1
            readable, _, exceptional = select.select(socs, [], socs, 3)

            if exceptional:
                break

            if readable:
                for sock in readable:
                    try:
                        data = sock.recv(BUFLEN)
                        if not data:
                            return
                        if sock is self.target:
                            self.client.sendall(data)
                        else:
                            self.target.sendall(data)
                        idle = 0
                    except Exception:
                        return
            
            if idle >= TIMEOUT:
                break

    def _close(self):
        for sock, flag_attr in [(self.client, 'client_closed'), (self.target, 'target_closed')]:
            if sock and not getattr(self, flag_attr):
                try:
                    sock.shutdown(socket.SHUT_RDWR)
                    sock.close()
                except Exception:
                    pass
                setattr(self, flag_attr, True)


class ProxyServer:
    def __init__(self, host, port):
        self.host    = host
        self.port    = port
        self.running = False
        self.sock    = None

    def start(self):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.settimeout(2)
        self.sock.bind((self.host, self.port))
        self.sock.listen(512)
        self.running = True

        print(f"[ZV-Manager] WebSocket Proxy berjalan di {self.host}:{self.port}")
        print(f"[ZV-Manager] Forward ke SSH {DEFAULT_HOST}:{DEFAULT_PORT}")

        while self.running:
            try:
                client, addr = self.sock.accept()
                client.setblocking(True)
                handler = ConnectionHandler(client, addr)
                handler.start()
            except socket.timeout:
                continue
            except Exception:
                break

    def stop(self):
        self.running = False
        if self.sock:
            self.sock.close()


def signal_handler(sig, frame):
    print("\n[ZV-Manager] Proxy dihentikan.")
    sys.exit(0)


if __name__ == '__main__':
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    server = ProxyServer(LISTENING_ADDR, LISTENING_PORT)
    server.start()
