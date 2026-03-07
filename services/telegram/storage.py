#!/usr/bin/env python3
# ============================================================
#   ZV-Manager Bot - Storage & Data Access
# ============================================================

import os
import subprocess
import time
from datetime import datetime
from pathlib import Path

from config import (
    ACCOUNT_DIR, SALDO_DIR, USERS_DIR, TRIAL_DIR,
    SERVER_DIR, log
)
from utils import zv_log, local_ip

# ── In-memory state ──────────────────────────────────────────
user_states: dict[int, dict] = {}

# ── Cache ────────────────────────────────────────────────────
_account_cache:     dict[str, tuple[int, float]] = {}
_srv_conf_cache:    dict[str, tuple[dict, float]] = {}
_tg_conf_cache:     dict[str, tuple[dict, float]] = {}
_server_list_cache: tuple[list, float]            = ([], 0.0)


# ── State management ─────────────────────────────────────────
def state_set(uid: int, key: str, val: str):
    user_states.setdefault(uid, {})[key] = val

def state_get(uid: int, key: str) -> str:
    return user_states.get(uid, {}).get(key, "")

def state_clear(uid: int):
    user_states.pop(uid, None)


# ── Saldo ────────────────────────────────────────────────────
def saldo_get(uid: int) -> int:
    f = f"{SALDO_DIR}/{uid}.saldo"
    try:
        val = Path(f).read_text().strip().replace("SALDO=", "")
        return int(val)
    except Exception:
        return 0

def saldo_set(uid: int, amount: int):
    os.makedirs(SALDO_DIR, exist_ok=True)
    with open(f"{SALDO_DIR}/{uid}.saldo", "w") as f:
        f.write(str(max(0, amount)))

def saldo_add(uid: int, amount: int) -> int:
    new = saldo_get(uid) + amount
    saldo_set(uid, new)
    return new

def saldo_deduct(uid: int, amount: int) -> bool:
    cur = saldo_get(uid)
    if cur < amount:
        return False
    saldo_set(uid, cur - amount)
    return True


# ── Conf file reader ─────────────────────────────────────────
def _read_conf_file(path: str) -> dict:
    """Baca key=value conf, auto strip tanda kutip."""
    conf = {}
    try:
        with open(path) as fh:
            for line in fh:
                line = line.strip()
                if line and "=" in line and not line.startswith("#"):
                    k, _, v = line.partition("=")
                    conf[k.strip()] = v.strip().strip('"').strip("'")
    except Exception:
        pass
    return conf


# ── Server conf ──────────────────────────────────────────────
def load_server_conf(sname: str) -> dict:
    now = time.time()
    if sname in _srv_conf_cache:
        val, ts = _srv_conf_cache[sname]
        if now - ts < 300:
            return val
    conf = _read_conf_file(f"{SERVER_DIR}/{sname}.conf")
    _srv_conf_cache[sname] = (conf, now)
    return conf

def load_tg_server_conf(sname: str) -> dict:
    now = time.time()
    if sname in _tg_conf_cache:
        val, ts = _tg_conf_cache[sname]
        if now - ts < 300:
            return val
    defaults = {
        "TG_SERVER_LABEL": sname,
        "TG_HARGA_HARI":   "0",
        "TG_HARGA_BULAN":  "0",
        "TG_QUOTA":        "Unlimited",
        "TG_LIMIT_IP":     "2",
        "TG_MAX_AKUN":     "500",
        "TG_BW_PER_HARI":  "5",
    }
    defaults.update(_read_conf_file(f"{SERVER_DIR}/{sname}.tg.conf"))
    _tg_conf_cache[sname] = (defaults, now)
    return defaults

def get_server_list() -> list[dict]:
    global _server_list_cache
    now = time.time()
    servers, ts = _server_list_cache
    if now - ts < 300:
        return servers
    result = []
    try:
        for f in sorted(Path(SERVER_DIR).glob("*.conf")):
            if f.name.endswith(".tg.conf"):
                continue
            conf = _read_conf_file(str(f))
            if conf.get("NAME"):
                result.append(conf)
    except Exception:
        pass
    _server_list_cache = (result, now)
    return result

def count_accounts(srv_ip: str) -> int:
    global _account_cache
    now = time.time()
    if srv_ip in _account_cache:
        cnt, ts = _account_cache[srv_ip]
        if now - ts < 120:
            return cnt
    lip   = local_ip()
    count = 0
    if srv_ip == lip:
        try:
            for f in Path(ACCOUNT_DIR).glob("*.conf"):
                if "IS_TRIAL=1" not in f.read_text():
                    count += 1
        except Exception:
            pass
    else:
        try:
            for sconf in Path(SERVER_DIR).glob("*.conf"):
                if sconf.name.endswith(".tg.conf"):
                    continue
                sc = _read_conf_file(str(sconf))
                if sc.get("IP", "").strip() != srv_ip:
                    continue
                result = subprocess.run(
                    ["sshpass", "-p", sc.get("PASS", ""),
                     "ssh", "-o", "StrictHostKeyChecking=no",
                     "-o", "ConnectTimeout=3", "-o", "BatchMode=no",
                     "-p", sc.get("PORT", "22"),
                     f"{sc.get('USER', '')}@{srv_ip}", "zv-agent list"],
                    capture_output=True, text=True, timeout=6
                )
                raw = result.stdout.strip()
                if raw and raw != "LIST-EMPTY":
                    count = raw.count("|")
                break
        except Exception:
            pass
    _account_cache[srv_ip] = (count, now)
    return count


# ── Account conf ─────────────────────────────────────────────
def load_account_conf(username: str) -> dict:
    return _read_conf_file(f"{ACCOUNT_DIR}/{username}.conf")

def save_account_conf(username: str, data: dict):
    with open(f"{ACCOUNT_DIR}/{username}.conf", "w") as fh:
        for k, v in data.items():
            fh.write(f"{k}={v}\n")


# ── User registry ────────────────────────────────────────────
def register_user(uid: int, fname: str):
    os.makedirs(USERS_DIR, exist_ok=True)
    f = f"{USERS_DIR}/{uid}.user"
    if not os.path.exists(f):
        joined = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        with open(f, "w") as fh:
            fh.write(f"UID={uid}\nNAME={fname}\nJOINED={joined}\n")
        zv_log(f"NEW_USER: uid={uid} name={fname}")
    else:
        lines = []
        with open(f) as fh:
            for line in fh:
                lines.append(f"NAME={fname}\n" if line.startswith("NAME=") else line)
        with open(f, "w") as fh:
            fh.writelines(lines)

def load_user_info(uid: int) -> dict:
    return _read_conf_file(f"{USERS_DIR}/{uid}.user")


# ── Trial helpers ────────────────────────────────────────────
def already_trial(uid: int, sname: str) -> bool:
    f = f"{TRIAL_DIR}/{uid}_{sname}.ts"
    try:
        last = int(Path(f).read_text().strip())
        return (time.time() - last) < 86400
    except Exception:
        return False

def mark_trial(uid: int, sname: str):
    os.makedirs(TRIAL_DIR, exist_ok=True)
    with open(f"{TRIAL_DIR}/{uid}_{sname}.ts", "w") as f:
        f.write(str(int(time.time())))
