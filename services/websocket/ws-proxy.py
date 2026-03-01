#!/usr/bin/env python3
# ============================================================
#   ZV-Manager - WebSocket & HTTP CONNECT SSH Proxy
#   Compatible: Python 3.x (Ubuntu 24.04)
#   Support:
#     - HTTP CONNECT (HTTP Custom, HTTP Injector, NapsternetV)
#     - WebSocket Upgrade (WS mode)
#     - Direct SSH over SSL (HTTP Custom easyPro mode)
# ============================================================

import socket
import threading
import select
import signal
import sys

LISTENING_ADDR = '0.0.0.0'
LISTENING_PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 80
DEFAULT_HOST   = '127.0.0.1'
DEFAULT_PORT   = 22
BUFLEN         = 4096 * 4
TIMEOUT        = 600

WS_RESPONSE = (
    "HTTP/1.1 101 Switching Protocols\r\n"
    "Content-Length: 0\r\n"
    "\r\n"
    "HTTP/1.1 200 ZV-Manager\r\n"
    "\r\n"
)
CONNECT_RESPONSE = "HTTP/1.1 200 Connection Established\r\n\r\n"


class ConnectionHandler(threading.Thread):
    def __init__(self, client_sock, addr):
        threading.Thread.__init__(self)
        self.client        = client_sock
        self.addr          = addr
        self.target        = None
        self.client_closed = False
        self.target_closed = True
        self.daemon        = True

    def run(self):
        try:
            self.handle()
        except Exception:
            pass
        finally:
            self._close()

    def handle(self):
        self.client.settimeout(30)
        raw = b''
        try:
            while b'\r\n\r\n' not in raw:
                chunk = self.client.recv(BUFLEN)
                if not chunk:
                    return
                raw += chunk
                # Deteksi Direct SSH over SSL
                # HTTP Custom (easyPro) kirim SSH banner langsung tanpa HTTP headers
                if raw.startswith(b'SSH-'):
                    break
                if len(raw) > BUFLEN:
                    break
        except Exception:
            return

        self.client.settimeout(None)

        # --- Mode: Direct SSH over SSL ---
        # Client kirim SSH banner langsung (tanpa CONNECT/WebSocket request)
        if raw.startswith(b'SSH-'):
            self._handle_direct_ssh(raw)
            return

        # Pisah header dan leftover data
        header_end  = raw.find(b'\r\n\r\n') + 4
        headers_raw = raw[:header_end]
        leftover    = raw[header_end:]
        data        = headers_raw.decode('utf-8', errors='ignore')
        first_line  = data.split('\r\n')[0]

        # --- Mode: HTTP CONNECT ---
        if first_line.upper().startswith('CONNECT'):
            self._handle_connect(first_line, leftover)

        # --- Mode: WebSocket Upgrade ---
        elif 'upgrade: websocket' in data.lower():
            self._handle_websocket(data, leftover)

        # --- Mode: Request lain → treat as WebSocket ---
        else:
            self._handle_websocket(data, leftover)

    def _handle_direct_ssh(self, client_banner):
        """Handle Direct SSH over SSL — client kirim SSH banner langsung"""
        try:
            self.target = socket.create_connection((DEFAULT_HOST, DEFAULT_PORT), timeout=10)
            self.target.settimeout(None)
            self.target.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            self.target_closed = False

            # Ambil SSH banner dari server
            server_banner = self.target.recv(BUFLEN)
            # Kirim banner server ke client
            self.client.sendall(server_banner)
            # Forward banner client ke server
            self.target.sendall(client_banner)
            # Relay dua arah
            self._relay()
        except Exception:
            pass

    def _handle_connect(self, first_line, leftover=b''):
        """Handle HTTP CONNECT tunneling"""
        try:
            parts  = first_line.split()
            target = parts[1] if len(parts) >= 2 else ''
            if ':' in target:
                host, port_str = target.rsplit(':', 1)
                try:
                    port = int(port_str)
                except ValueError:
                    port = DEFAULT_PORT
            else:
                host = target
                port = DEFAULT_PORT

            if host not in ('127.0.0.1', 'localhost'):
                host = DEFAULT_HOST
                port = DEFAULT_PORT

            self.target = socket.create_connection((host, port), timeout=10)
            self.target.settimeout(None)
            self.target.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            self.target_closed = False

            self.client.sendall(CONNECT_RESPONSE.encode())
            self._relay(leftover)

        except Exception:
            try:
                self.client.sendall(b"HTTP/1.1 502 Bad Gateway\r\n\r\n")
            except Exception:
                pass

    def _handle_websocket(self, data, leftover=b''):
        """Handle WebSocket Upgrade"""
        target_host, target_port = self._parse_xrealhost(data)
        if target_host not in ('127.0.0.1', 'localhost'):
            target_host = DEFAULT_HOST
            target_port = DEFAULT_PORT

        self.target = socket.create_connection((target_host, target_port), timeout=10)
        self.target.settimeout(None)
        self.target.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        self.target_closed = False

        self.client.sendall(WS_RESPONSE.encode())
        self._relay(leftover)

    def _parse_xrealhost(self, data):
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

    def _relay(self, leftover=b''):
        """Relay data dua arah antara client dan SSH target"""
        if leftover:
            try:
                self.target.sendall(leftover)
            except Exception:
                return

        socs = [self.client, self.target]
        idle = 0
        while True:
            idle += 1
            try:
                readable, _, exceptional = select.select(socs, [], socs, 3)
            except Exception:
                break
            if exceptional:
                break
            if readable:
                for sock in readable:
                    try:
                        data = sock.recv(BUFLEN)
                        if not data:
                            return
                        dest = self.target if sock is self.client else self.client
                        dest.sendall(data)
                        idle = 0
                    except Exception:
                        return
            if idle >= TIMEOUT:
                break

    def _close(self):
        for sock, attr in [(self.client, 'client_closed'), (self.target, 'target_closed')]:
            if sock and not getattr(self, attr):
                try:
                    sock.shutdown(socket.SHUT_RDWR)
                    sock.close()
                except Exception:
                    pass
                setattr(self, attr, True)


class ProxyServer:
    def __init__(self, host, port):
        self.host    = host
        self.port    = port
        self.sock    = None

    def start(self):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.settimeout(2)
        self.sock.bind((self.host, self.port))
        self.sock.listen(512)

        print(f"[ZV-Manager] Proxy berjalan di {self.host}:{self.port}")
        print(f"[ZV-Manager] Support: HTTP CONNECT + WebSocket + Direct SSH over SSL")
        print(f"[ZV-Manager] Forward ke SSH {DEFAULT_HOST}:{DEFAULT_PORT}")

        while True:
            try:
                client, addr = self.sock.accept()
                client.setblocking(True)
                client.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                ConnectionHandler(client, addr).start()
            except socket.timeout:
                continue
            except Exception:
                break


def signal_handler(sig, frame):
    print("\n[ZV-Manager] Proxy dihentikan.")
    sys.exit(0)


if __name__ == '__main__':
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    ProxyServer(LISTENING_ADDR, LISTENING_PORT).start()
