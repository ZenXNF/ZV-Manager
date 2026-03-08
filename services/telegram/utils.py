#!/usr/bin/env python3
# ============================================================
#   ZV-Manager Bot - Utility Functions
# ============================================================

import os
import subprocess
from datetime import datetime
from pathlib import Path

from config import LOG_FILE, IPVPS_FILE, log


def zv_log(msg: str):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
    with open(LOG_FILE, "a") as f:
        f.write(f"[{ts}] {msg}\n")


def tail_log(n: int = 500) -> list[str]:
    """Baca n baris terakhir log secara efisien tanpa load seluruh file."""
    try:
        with open(LOG_FILE, "rb") as f:
            f.seek(0, 2)
            size = f.tell()
            if size == 0:
                return []
            block = min(size, n * 150)
            f.seek(-block, 2)
            raw = f.read().decode("utf-8", errors="ignore")
        lines = raw.splitlines()
        if block < size:
            lines = lines[1:]
        return lines[-n:]
    except Exception:
        return []


def fmt(n) -> str:
    """Format angka: 100000 → 100.000"""
    try:
        n = int(n)
    except Exception:
        return "0"
    return f"{n:,}".replace(",", ".")


def fmt_bytes(b) -> str:
    try:
        b = int(b)
    except Exception:
        return "0 B"
    if b >= 1024**3:
        return f"{b/1024**3:.1f} GB"
    if b >= 1024**2:
        return f"{b/1024**2:.1f} MB"
    if b >= 1024:
        return f"{b/1024:.1f} KB"
    return f"{b} B"


def wib_now() -> str:
    return datetime.now().strftime("%d %b %Y %H:%M WIB")


def ts_to_wib(ts: int) -> str:
    try:
        return datetime.fromtimestamp(ts).strftime("%d %b %Y %H:%M WIB")
    except Exception:
        return "-"


def local_ip() -> str:
    try:
        return Path(IPVPS_FILE).read_text().strip()
    except Exception:
        return ""


def backup_realtime(username: str, action: str = "update"):
    """Panggil backup-realtime.sh di background — tidak blocking bot."""
    script = "/etc/zv-manager/cron/backup-realtime.sh"
    if os.path.exists(script):
        subprocess.Popen(
            ["/bin/bash", script, username, action],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )

def backup_realtime_vmess(username: str, action: str = "update"):
    """Backup real-time untuk akun VMess."""
    script = "/etc/zv-manager/cron/backup-realtime.sh"
    if os.path.exists(script):
        subprocess.Popen(
            ["/bin/bash", script, username, action, "vmess"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
