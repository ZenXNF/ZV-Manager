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
    ACCOUNT_DIR, VMESS_DIR, SALDO_DIR, USERS_DIR, TRIAL_DIR,
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
        "TG_HARGA_VMESS_HARI": "0",
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
                # Merge tg.conf jika ada
                tg_f = Path(SERVER_DIR) / f"{conf['NAME']}.tg.conf"
                if tg_f.exists():
                    conf.update(_read_conf_file(str(tg_f)))
                result.append(conf)
    except Exception:
        pass
    _server_list_cache = (result, now)
    return result

def get_server_list_by_type(stype: str) -> list[dict]:
    """Filter server berdasarkan tipe: 'ssh', 'vmess', atau 'both'.
    stype='ssh'   → return server dengan SERVER_TYPE ssh atau both
    stype='vmess' → return server dengan SERVER_TYPE vmess atau both
    """
    result = []
    for s in get_server_list():
        t = s.get("TG_SERVER_TYPE", s.get("SERVER_TYPE", "both"))
        if t == "both" or t == stype:
            result.append(s)
    return result

def count_accounts(srv_ip: str) -> int:
    """Backward compat — hitung SSH saja."""
    return count_ssh_accounts(srv_ip)

# Cache pisah per proto: key = "ssh:IP" atau "vmess:IP"

def _get_cached(key: str):
    if key in _account_cache:
        cnt, ts = _account_cache[key]
        if time.time() - ts < 120:
            return cnt
    return None

def _set_cached(key: str, cnt: int):
    _account_cache[key] = (cnt, time.time())

def count_ssh_accounts(srv_ip: str) -> int:
    key = f"ssh:{srv_ip}"
    cached = _get_cached(key)
    if cached is not None:
        return cached
    lip   = local_ip()
    if not srv_ip:
        srv_ip = lip
    count = 0
    now_ts = int(time.time())
    if srv_ip == lip:
        try:
            for f in Path(ACCOUNT_DIR).glob("*.conf"):
                txt = f.read_text()
                if "IS_TRIAL=1" in txt or 'IS_TRIAL="1"' in txt:
                    continue
                # Skip expired
                ac = _read_conf_file(str(f))
                exp = ac.get("EXPIRED_TS", "")
                if exp and str(exp).strip().isdigit() and int(exp) < now_ts:
                    continue
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
    _set_cached(key, count)
    return count

def count_vmess_accounts(srv_ip: str) -> int:
    key = f"vmess:{srv_ip}"
    cached = _get_cached(key)
    if cached is not None:
        return cached
    lip   = local_ip()
    if not srv_ip:
        srv_ip = lip
    count = 0
    now_ts = int(time.time())
    if srv_ip == lip:
        try:
            for f in Path(VMESS_DIR).glob("*.conf"):
                txt = f.read_text()
                if "IS_TRIAL=1" in txt or 'IS_TRIAL="1"' in txt:
                    continue
                # Skip expired
                vc = _read_conf_file(str(f))
                exp = vc.get("EXPIRED_TS", "")
                if exp and str(exp).strip().isdigit() and int(exp) < now_ts:
                    continue
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
                     f"{sc.get('USER', '')}@{srv_ip}", "zv-vmess-agent list"],
                    capture_output=True, text=True, timeout=6
                )
                raw = result.stdout.strip()
                if raw and raw != "LIST-EMPTY":
                    count = raw.count("|")
                break
        except Exception:
            pass
    _set_cached(key, count)
    return count

def invalidate_account_cache(srv_ip: str = None, proto: str = None):
    """Paksa refresh counter akun. Panggil setelah beli/hapus akun."""
    global _account_cache
    if srv_ip and proto:
        _account_cache.pop(f"{proto}:{srv_ip}", None)
    elif srv_ip:
        _account_cache.pop(f"ssh:{srv_ip}", None)
        _account_cache.pop(f"vmess:{srv_ip}", None)
    else:
        _account_cache.clear()


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


# ── VMess helpers ────────────────────────────────────────────────────────
def load_vmess_conf(username: str) -> dict:
    from config import VMESS_DIR
    return _read_conf_file(f"{VMESS_DIR}/{username}.conf")

def save_vmess_conf(username: str, data: dict) -> None:
    from config import VMESS_DIR
    import os
    os.makedirs(VMESS_DIR, exist_ok=True)
    path = f"{VMESS_DIR}/{username}.conf"
    with open(path, "w") as f:
        for k, v in data.items():
            f.write(f'{k}="{v}"\n')

def already_trial_vmess(uid: int, sname: str) -> bool:
    """Cek apakah user sudah trial VMess di server ini dalam 24 jam."""
    marker = Path(TRIAL_DIR) / f"vmess_{uid}_{sname}"
    if not marker.exists():
        return False
    return (time.time() - marker.stat().st_mtime) < 86400

def mark_trial_vmess(uid: int, sname: str) -> None:
    Path(TRIAL_DIR).mkdir(parents=True, exist_ok=True)
    (Path(TRIAL_DIR) / f"vmess_{uid}_{sname}").touch()
