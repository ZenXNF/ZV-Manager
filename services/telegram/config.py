#!/usr/bin/env python3
# ============================================================
#   ZV-Manager Bot - Config & Constants
# ============================================================

import logging
from pathlib import Path

# ── Directory paths ─────────────────────────────────────────
BASE_DIR    = "/etc/zv-manager"
ACCOUNT_DIR  = f"{BASE_DIR}/accounts/ssh"
VMESS_DIR    = f"{BASE_DIR}/accounts/vmess"
SALDO_DIR   = f"{BASE_DIR}/accounts/saldo"
USERS_DIR   = f"{BASE_DIR}/accounts/users"
TRIAL_DIR   = f"{BASE_DIR}/accounts/trial"
NOTIFY_DIR  = f"{BASE_DIR}/accounts/notified"
SERVER_DIR  = f"{BASE_DIR}/servers"
TG_CONF     = f"{BASE_DIR}/telegram.conf"
LOG_FILE    = "/var/log/zv-manager/install.log"
IPVPS_FILE  = f"{BASE_DIR}/accounts/ipvps"

# ── Logging setup ────────────────────────────────────────────
logging.basicConfig(
    level=logging.WARNING,
    format="[%(asctime)s] %(levelname)s %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)
logging.getLogger("aiogram").setLevel(logging.WARNING)
logging.getLogger("aiohttp").setLevel(logging.WARNING)
log = logging.getLogger("zvbot")
log.setLevel(logging.INFO)

# ── Load telegram.conf ───────────────────────────────────────
def load_tg_conf() -> dict:
    conf = {}
    try:
        with open(TG_CONF) as f:
            for line in f:
                line = line.strip()
                if "=" in line and not line.startswith("#"):
                    k, _, v = line.partition("=")
                    conf[k.strip()] = v.strip().strip('"').strip("'")
    except Exception:
        pass
    return conf

TG       = load_tg_conf()
TOKEN    = TG.get("TG_TOKEN", "")
_admin_raw = TG.get("TG_ADMIN_ID", "0").strip().strip('"').strip("'")
ADMIN_ID = int(_admin_raw) if _admin_raw.isdigit() else 0
