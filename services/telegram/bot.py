#!/usr/bin/env python3
# ============================================================
#   ZV-Manager - Telegram Bot
#   Python 3 + aiogram 3.x
#   Menggantikan bot.sh / handlers.sh / helpers.sh / keyboards.sh
# ============================================================

import asyncio
import logging
import os
import re
import subprocess
import time
import random
import string
from collections import deque
from datetime import datetime
from functools import lru_cache
from pathlib import Path

from aiogram import Bot, Dispatcher, F
from aiogram.filters import Command
from aiogram.types import (
    Message, CallbackQuery,
    InlineKeyboardMarkup, InlineKeyboardButton
)
from aiogram.utils.keyboard import InlineKeyboardBuilder

# ============================================================
# Config paths
# ============================================================
BASE_DIR     = "/etc/zv-manager"
ACCOUNT_DIR  = f"{BASE_DIR}/accounts/ssh"
SALDO_DIR    = f"{BASE_DIR}/accounts/saldo"
USERS_DIR    = f"{BASE_DIR}/accounts/users"
TRIAL_DIR    = f"{BASE_DIR}/accounts/trial"
NOTIFY_DIR   = f"{BASE_DIR}/accounts/notified"
SERVER_DIR   = f"{BASE_DIR}/servers"
TG_CONF      = f"{BASE_DIR}/telegram.conf"
LOG_FILE     = "/var/log/zv-manager/install.log"
IPVPS_FILE   = f"{BASE_DIR}/accounts/ipvps"

# State disimpan di memory (dict) — lebih cepat dari file
user_states: dict[int, dict] = {}

# Cache jumlah akun per server IP (60 detik)
_account_cache: dict[str, tuple[int, float]] = {}
# Cache server conf (5 menit)
_srv_conf_cache: dict[str, tuple[dict, float]] = {}
_tg_conf_cache:  dict[str, tuple[dict, float]] = {}

logging.basicConfig(level=logging.WARNING,
    format="[%(asctime)s] %(levelname)s %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S")
# Matikan log verbose dari aiogram & aiohttp (hemat RAM + CPU)
logging.getLogger("aiogram").setLevel(logging.WARNING)
logging.getLogger("aiohttp").setLevel(logging.WARNING)
log = logging.getLogger(__name__)
log.setLevel(logging.INFO)

def backup_realtime(username: str, action: str = "update"):
    """Panggil backup-realtime.sh di background — tidak blocking bot."""
    import subprocess
    script = "/etc/zv-manager/cron/backup-realtime.sh"
    if os.path.exists(script):
        subprocess.Popen(
            ["/bin/bash", script, username, action],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )

# ============================================================
# Load telegram config
# ============================================================
def load_tg_conf() -> dict:
    conf = {}
    try:
        with open(TG_CONF) as f:
            for line in f:
                line = line.strip()
                if "=" in line and not line.startswith("#"):
                    k, _, v = line.partition("=")
                    # Strip spasi dan tanda kutip (single/double)
                    conf[k.strip()] = v.strip().strip('"').strip("'")
    except Exception:
        pass
    return conf

TG = load_tg_conf()
TOKEN    = TG.get("TG_TOKEN", "")
# Safe parse ADMIN_ID — strip kutip, ambil digit saja
_admin_raw = TG.get("TG_ADMIN_ID", "0").strip().strip('"').strip("'")
ADMIN_ID = int(_admin_raw) if _admin_raw.isdigit() else 0

# ============================================================
# Helpers
# ============================================================
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
            # Estimasi 150 byte/baris, ambil lebih banyak buat jaga-jaga
            block = min(size, n * 150)
            f.seek(-block, 2)
            raw = f.read().decode("utf-8", errors="ignore")
        lines = raw.splitlines()
        # Baris pertama mungkin terpotong, buang
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

# ============================================================
# Saldo
# ============================================================
def saldo_get(uid: int) -> int:
    f = f"{SALDO_DIR}/{uid}.saldo"
    try:
        val = Path(f).read_text().strip()
        val = val.replace("SALDO=", "")
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

# ============================================================
# State management (in-memory)
# ============================================================
def state_set(uid: int, key: str, val: str):
    if uid not in user_states:
        user_states[uid] = {}
    user_states[uid][key] = val

def state_get(uid: int, key: str) -> str:
    return user_states.get(uid, {}).get(key, "")

def state_clear(uid: int):
    user_states.pop(uid, None)

# ============================================================
# Server config helpers
# ============================================================
def _read_conf_file(path: str) -> dict:
    """Baca file conf key=value, return dict. Auto strip tanda kutip."""
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
        "TG_HARGA_HARI": "0",
        "TG_HARGA_BULAN": "0",
        "TG_QUOTA": "Unlimited",
        "TG_LIMIT_IP": "2",
        "TG_MAX_AKUN": "500",
        "TG_BW_PER_HARI": "5",
    }
    overrides = _read_conf_file(f"{SERVER_DIR}/{sname}.tg.conf")
    defaults.update(overrides)
    _tg_conf_cache[sname] = (defaults, now)
    return defaults

_server_list_cache: tuple[list, float] = ([], 0.0)

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
        if now - ts < 60:
            return cnt

    lip = local_ip()
    count = 0
    if srv_ip == lip:
        try:
            for f in Path(ACCOUNT_DIR).glob("*.conf"):
                content = f.read_text()
                if "IS_TRIAL=1" not in content:
                    count += 1
        except Exception:
            pass
    else:
        try:
            for sconf in Path(SERVER_DIR).glob("*.conf"):
                if sconf.name.endswith(".tg.conf"):
                    continue
                sc = {}
                with open(sconf) as fh:
                    for line in fh:
                        if "=" in line:
                            k, _, v = line.strip().partition("=")
                            sc[k] = v
                if sc.get("IP", "").strip() != srv_ip:
                    continue
                result = subprocess.run(
                    ["sshpass", "-p", sc.get("PASS",""),
                     "ssh", "-o", "StrictHostKeyChecking=no",
                     "-o", "ConnectTimeout=8", "-o", "BatchMode=no",
                     "-p", sc.get("PORT","22"),
                     f"{sc.get('USER','')}@{srv_ip}",
                     "zv-agent list"],
                    capture_output=True, text=True, timeout=12
                )
                raw = result.stdout.strip()
                if raw and raw != "LIST-EMPTY":
                    count = raw.count("|")
                break
        except Exception:
            pass

    _account_cache[srv_ip] = (count, now)
    return count

def load_account_conf(username: str) -> dict:
    return _read_conf_file(f"{ACCOUNT_DIR}/{username}.conf")

def save_account_conf(username: str, data: dict):
    f = f"{ACCOUNT_DIR}/{username}.conf"
    with open(f, "w") as fh:
        for k, v in data.items():
            fh.write(f"{k}={v}\n")

# ============================================================
# User registry
# ============================================================
def register_user(uid: int, fname: str):
    os.makedirs(USERS_DIR, exist_ok=True)
    f = f"{USERS_DIR}/{uid}.user"
    if not os.path.exists(f):
        joined = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        with open(f, "w") as fh:
            fh.write(f"UID={uid}\nNAME={fname}\nJOINED={joined}\n")
        zv_log(f"NEW_USER: uid={uid} name={fname}")
    else:
        # Update nama
        lines = []
        with open(f) as fh:
            for line in fh:
                if line.startswith("NAME="):
                    lines.append(f"NAME={fname}\n")
                else:
                    lines.append(line)
        with open(f, "w") as fh:
            fh.writelines(lines)

def load_user_info(uid: int) -> dict:
    return _read_conf_file(f"{USERS_DIR}/{uid}.user")

# ============================================================
# Trial helpers
# ============================================================
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

# ============================================================
# Admin notify
# ============================================================
async def notify_admin(bot: Bot, tipe: str, fname: str, uid: int,
                        username: str, sname: str, days_or_gb, total: int):
    if not ADMIN_ID or uid == ADMIN_ID:
        return
    icons = {"BELI": "🛒", "RENEW": "🔄", "BW": "📶"}
    labels = {"BELI": "Pembelian Baru", "RENEW": "Perpanjang Akun", "BW": "Tambah Kuota"}
    icon = icons.get(tipe, "💡")
    label = labels.get(tipe, "Transaksi")
    extra = f"\n📶 Tambah   : {days_or_gb} GB" if tipe == "BW" else f"\n📅 Durasi   : {days_or_gb} hari"
    text = (
        f"{icon} <b>{label}</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"👤 User     : {fname} (<code>{uid}</code>)\n"
        f"🖥️ Akun     : <code>{username}</code>\n"
        f"🌐 Server   : {sname}{extra}\n"
        f"💸 Total    : Rp{fmt(total)}\n"
        f"━━━━━━━━━━━━━━━━━━━"
    )
    try:
        await bot.send_message(ADMIN_ID, text, parse_mode="HTML")
    except Exception:
        pass

# ============================================================
# Keyboards
# ============================================================
def kb_home() -> InlineKeyboardMarkup:
    b = InlineKeyboardBuilder()
    b.row(
        InlineKeyboardButton(text="⚡ Buat Akun",       callback_data="m_buat"),
        InlineKeyboardButton(text="🎁 Coba Gratis",     callback_data="m_trial")
    )
    b.row(
        InlineKeyboardButton(text="📋 Akun Saya",       callback_data="m_akun"),
        InlineKeyboardButton(text="🔄 Perpanjang",       callback_data="m_perpanjang")
    )
    b.row(
        InlineKeyboardButton(text="📋 Riwayat Saldo",   callback_data="m_saldo_history"),
        InlineKeyboardButton(text="📶 Tambah Kuota",    callback_data="m_tambah_bw")
    )
    return b.as_markup()

def kb_home_admin() -> InlineKeyboardMarkup:
    b = InlineKeyboardBuilder()
    b.row(
        InlineKeyboardButton(text="⚡ Buat Akun",       callback_data="m_buat"),
        InlineKeyboardButton(text="🎁 Coba Gratis",     callback_data="m_trial")
    )
    b.row(
        InlineKeyboardButton(text="📋 Akun Saya",       callback_data="m_akun"),
        InlineKeyboardButton(text="🔄 Perpanjang",       callback_data="m_perpanjang")
    )
    b.row(
        InlineKeyboardButton(text="📋 Riwayat Saldo",   callback_data="m_saldo_history"),
        InlineKeyboardButton(text="🔧 Admin",           callback_data="m_admin")
    )
    return b.as_markup()

def kb_for_user(uid: int) -> InlineKeyboardMarkup:
    return kb_home_admin() if uid == ADMIN_ID else kb_home()

def kb_home_btn() -> InlineKeyboardMarkup:
    b = InlineKeyboardBuilder()
    b.button(text="🏠 Menu Utama", callback_data="home")
    return b.as_markup()

def kb_back(cb: str = "home") -> InlineKeyboardMarkup:
    b = InlineKeyboardBuilder()
    b.button(text="↩ Kembali", callback_data=cb)
    return b.as_markup()

def kb_confirm(cb_yes: str) -> InlineKeyboardMarkup:
    b = InlineKeyboardBuilder()
    b.row(
        InlineKeyboardButton(text="✅ Konfirmasi", callback_data=cb_yes),
        InlineKeyboardButton(text="❌ Batal",       callback_data="home")
    )
    return b.as_markup()

def kb_server_list(prefix: str, page: int = 0) -> InlineKeyboardMarkup:
    servers = get_server_list()
    per_page = 6
    start = page * per_page
    chunk = servers[start:start + per_page]
    b = InlineKeyboardBuilder()
    for s in chunk:
        name = s.get("NAME", "")
        b.button(text=name, callback_data=f"{prefix}_{name}")
    b.adjust(2)
    nav = []
    if page > 0:
        nav.append(InlineKeyboardButton(text="◀ Sebelumnya", callback_data=f"page_{prefix}_{page-1}"))
    if start + per_page < len(servers):
        nav.append(InlineKeyboardButton(text="Berikutnya ▶", callback_data=f"page_{prefix}_{page+1}"))
    if nav:
        b.row(*nav)
    b.row(InlineKeyboardButton(text="↩ Kembali", callback_data="home"))
    return b.as_markup()

def kb_admin_panel() -> InlineKeyboardMarkup:
    b = InlineKeyboardBuilder()
    b.row(
        InlineKeyboardButton(text="💰 Top Up Saldo",       callback_data="adm_topup"),
        InlineKeyboardButton(text="➖ Kurangi Saldo",       callback_data="adm_kurangi")
    )
    b.row(
        InlineKeyboardButton(text="🗑️ Hapus Akun",         callback_data="adm_hapus_akun"),
        InlineKeyboardButton(text="📢 Broadcast",           callback_data="m_broadcast")
    )
    b.row(
        InlineKeyboardButton(text="👥 Daftar User",         callback_data="adm_daftar_user"),
        InlineKeyboardButton(text="🔍 Cek User",            callback_data="adm_cek_user")
    )
    b.row(
        InlineKeyboardButton(text="📊 History Transaksi",   callback_data="adm_history"),
        InlineKeyboardButton(text="🏠 Menu Utama",          callback_data="home")
    )
    return b.as_markup()

# ============================================================
# Text builders
# ============================================================
def text_home(fname: str, uid: int) -> str:
    servers = get_server_list()
    saldo = saldo_get(uid)
    return (
        f"⚡ <b>ZV-Manager SSH Tunnel</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"🖥️ Server   : {len(servers)} server\n"
        f"🆔 User ID  : <code>{uid}</code>\n"
        f"💰 Saldo    : Rp{fmt(saldo)}\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"🔹 SSH Tunnel / Premium\n"
        f"🔹 Support Bug Host / SNI\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"Halo, {fname}! Pilih menu 👇"
    )

def text_server_list(title: str) -> str:
    servers = get_server_list()
    out = f"<b>{title}</b>\n\n"
    if not servers:
        return out + "❌ Belum ada server.\n\nPilih server:"
    for s in servers:
        name = s.get("NAME", "")
        ip   = s.get("IP", "")
        tg   = load_tg_server_conf(name)
        cnt  = count_accounts(ip)
        hh   = f"Rp{fmt(tg['TG_HARGA_HARI'])}" if tg["TG_HARGA_HARI"] != "0" else "Hubungi admin"
        hb   = f"Rp{fmt(tg['TG_HARGA_BULAN'])}" if tg["TG_HARGA_BULAN"] != "0" else "Hubungi admin"
        bw_hr = int(tg.get("TG_BW_PER_HARI", "5") or "5")
        bw_30 = bw_hr * 30
        kuota = f"{bw_hr} GB/hari · {bw_30} GB/30hr" if bw_hr > 0 else "Unlimited"
        out += (
            f"🌐 <b>{tg['TG_SERVER_LABEL']}</b>\n"
            f"💰 Harga/hari  : {hh}\n"
            f"📅 Harga/30hr  : {hb}\n"
            f"📶 Kuota       : {kuota}\n"
            f"🔢 Limit IP    : {tg['TG_LIMIT_IP']} IP/akun\n"
            f"👥 Total Akun  : {cnt}/{tg['TG_MAX_AKUN']}\n\n"
        )
    return out + "Pilih server:"

def text_akun_info(tipe: str, username: str, password: str, domain: str,
                    exp_display: str, limit: str, server_label: str,
                    days: int = 0, total: int = 0) -> str:
    if tipe == "TRIAL":
        header = "🎁 <b>Akun Trial SSH — 30 Menit</b>"
    else:
        header = "🛒 <b>Akun SSH Berhasil Dibuat</b>"

    harga_line = f"\n💸 Dibayar   : <b>Rp{fmt(total)}</b>" if tipe == "BELI" else ""

    return (
        f"{header}\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"👤 Username : <code>{username}</code>\n"
        f"🔑 Password : <code>{password}</code>\n"
        f"🌐 Host     : <code>{domain}</code>\n"
        f"🖥 Server   : {server_label}\n"
        f"📅 Expired  : {exp_display}\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"📡 <b>Port Tersedia</b>\n"
        f"  OpenSSH  : <code>22, 500, 40000</code>\n"
        f"  Dropbear : <code>109, 143</code>\n"
        f"  BadVPN   : <code>7300</code>\n"
        f"  WS / WSS / UDP Custom\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"🔗 <b>Format HTTP Custom</b>\n"
        f"  <code>{domain}:80@{username}:{password}</code>\n"
        f"  <code>{domain}:443@{username}:{password}</code>\n"
        f"  <code>{domain}:1-65535@{username}:{password}</code>"
        f"{harga_line}"
    )

# ============================================================
# Bot & Dispatcher
# ============================================================
bot = Bot(token=TOKEN)
dp  = Dispatcher()

# Throttle sederhana: cegah spam klik (in-memory)
_last_action: dict[int, float] = {}

def _throttle(uid: int, seconds: float = 0.8) -> bool:
    """Return True kalau boleh jalan, False kalau masih cooldown."""
    now = time.time()
    last = _last_action.get(uid, 0.0)
    if now - last < seconds:
        return False
    _last_action[uid] = now
    return True

# ============================================================
# /start
# ============================================================
@dp.message(Command("start"))
async def cmd_start(msg: Message):
    uid   = msg.from_user.id
    fname = msg.from_user.first_name or "User"
    state_clear(uid)
    register_user(uid, fname)
    await msg.answer(text_home(fname, uid), parse_mode="HTML",
                     reply_markup=kb_for_user(uid))

# ============================================================
# Callback: home
# ============================================================
@dp.message(Command("testbroadcast"))
async def cmd_testbroadcast(msg: Message):
    """Debug: cek apakah bot bisa kirim pesan."""
    uid = msg.from_user.id
    if uid != ADMIN_ID:
        await msg.answer("❌ Admin only."); return
    try:
        await msg.bot.send_message(uid,
            "✅ Bot bisa kirim pesan ke kamu! Broadcast seharusnya berfungsi.",
            parse_mode="HTML")
        uids: set[int] = set()
        if Path(USERS_DIR).exists():
            for f in Path(USERS_DIR).glob("*.user"):
                try: uids.add(int(f.stem))
                except: pass
        if Path(ACCOUNT_DIR).exists():
            for f in Path(ACCOUNT_DIR).glob("*.conf"):
                ac = load_account_conf(f.stem)
                tid = ac.get("TG_USER_ID","").strip()
                if tid.isdigit(): uids.add(int(tid))
        uids.discard(uid)
        ids_preview = str(list(uids)[:5])
        lines = [
            "🔍 <b>Debug Broadcast</b>",
            "━━━━━━━━━━━━━━━━━━━",
            "✅ Bot OK kirim ke admin",
            f"👥 User lain: {len(uids)}",
            f"IDs contoh: {ids_preview}",
            f"USERS_DIR: {USERS_DIR}",
            f"ACCOUNT_DIR: {ACCOUNT_DIR}",
            "━━━━━━━━━━━━━━━━━━━",
            "Kalau user 0, belum ada yang /start ke bot.",
        ]
        await msg.answer("\n".join(lines), parse_mode="HTML")
    except Exception as e:
        await msg.answer(f"❌ Error: {e}")

@dp.callback_query(F.data == "home")
async def cb_home(cb: CallbackQuery):
    uid   = cb.from_user.id
    fname = cb.from_user.first_name or "User"
    if not _throttle(uid):
        await cb.answer("⏳"); return
    state_clear(uid)
    await cb.message.edit_text(text_home(fname, uid), parse_mode="HTML",
                                reply_markup=kb_for_user(uid))
    await cb.answer()

# ============================================================
# Callback: Buat Akun & Trial menu
# ============================================================
@dp.callback_query(F.data == "m_buat")
async def cb_menu_buat(cb: CallbackQuery):
    await cb.message.edit_text("⚡ <b>Buat Akun</b>\n\nPilih protokol:", parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
            InlineKeyboardButton(text="SSH", callback_data="proto_buat_ssh"),
            InlineKeyboardButton(text="↩ Kembali", callback_data="home")
        ]]))
    await cb.answer()

@dp.callback_query(F.data == "m_trial")
async def cb_menu_trial(cb: CallbackQuery):
    await cb.message.edit_text("🎁 <b>Coba Gratis</b>\n\nPilih protokol:", parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
            InlineKeyboardButton(text="SSH", callback_data="proto_trial_ssh"),
            InlineKeyboardButton(text="↩ Kembali", callback_data="home")
        ]]))
    await cb.answer()

@dp.callback_query(F.data == "proto_buat_ssh")
async def cb_proto_buat_ssh(cb: CallbackQuery):
    if not get_server_list():
        await cb.message.edit_text("❌ Belum ada server.")
        await cb.answer(); return
    await cb.message.edit_text(text_server_list("Buat Akun SSH"), parse_mode="HTML",
                                reply_markup=kb_server_list("s_buat"))
    await cb.answer()

@dp.callback_query(F.data == "proto_trial_ssh")
async def cb_proto_trial_ssh(cb: CallbackQuery):
    if not get_server_list():
        await cb.message.edit_text("❌ Belum ada server.")
        await cb.answer(); return
    await cb.message.edit_text(text_server_list("Trial SSH Gratis"), parse_mode="HTML",
                                reply_markup=kb_server_list("s_trial"))
    await cb.answer()

# Pagination server list
@dp.callback_query(F.data.startswith("page_"))
async def cb_page(cb: CallbackQuery):
    # page_s_buat_1 atau page_s_trial_0
    parts = cb.data.split("_")
    page  = int(parts[-1])
    prefix = "_".join(parts[1:-1])
    title = "Buat Akun SSH" if prefix == "s_buat" else "Trial SSH Gratis"
    await cb.message.edit_text(text_server_list(title), parse_mode="HTML",
                                reply_markup=kb_server_list(prefix, page))
    await cb.answer()

# ============================================================
# Callback: Pilih server — Buat akun
# ============================================================
@dp.callback_query(F.data.startswith("s_buat_"))
async def cb_s_buat(cb: CallbackQuery):
    sname = cb.data[len("s_buat_"):]
    uid   = cb.from_user.id
    fname = cb.from_user.first_name or "User"
    sconf = load_server_conf(sname)
    if not sconf:
        await cb.answer("❌ Server tidak ditemukan"); return
    tg = load_tg_server_conf(sname)
    ip = sconf.get("IP", "")
    if count_accounts(ip) >= int(tg["TG_MAX_AKUN"]):
        await cb.answer("❌ Server penuh!"); return
    await cb.answer()
    state_clear(uid)
    state_set(uid, "STATE",  "await_user")
    state_set(uid, "SERVER", sname)
    state_set(uid, "FNAME",  fname)
    await cb.message.answer(
        f"Server : <b>{tg['TG_SERVER_LABEL']}</b>\n\n"
        f"Ketik username yang kamu inginkan.\n"
        f"Hanya huruf kecil dan angka, minimal 3 karakter.",
        parse_mode="HTML"
    )

# ============================================================
# Callback: Pilih server — Trial
# ============================================================
@dp.callback_query(F.data.startswith("s_trial_"))
async def cb_s_trial(cb: CallbackQuery):
    sname = cb.data[len("s_trial_"):]
    uid   = cb.from_user.id
    fname = cb.from_user.first_name or "User"
    await cb.answer()

    if already_trial(uid, sname):
        await cb.message.answer(
            "⚠️ Kamu sudah trial di server ini dalam 24 jam terakhir.\n"
            "Coba server lain atau tunggu 24 jam."
        ); return

    sconf = load_server_conf(sname)
    if not sconf:
        await cb.message.answer("❌ Server tidak ditemukan."); return

    tg   = load_tg_server_conf(sname)
    ip   = sconf.get("IP", "")
    lip  = local_ip()
    domain = sconf.get("DOMAIN") or ip

    if count_accounts(ip) >= int(tg["TG_MAX_AKUN"]):
        await cb.message.answer(f"❌ Server <b>{tg['TG_SERVER_LABEL']}</b> penuh.", parse_mode="HTML")
        return

    suffix   = "".join(random.choices(string.digits, k=4))
    username = f"Trial{suffix}"
    password = "ZenXNF"
    now_ts   = int(time.time())
    exp_ts   = now_ts + 1800
    exp_display = ts_to_wib(exp_ts)
    exp_date = datetime.fromtimestamp(exp_ts).strftime("%Y-%m-%d")

    if ip == lip:
        subprocess.run(["useradd", "-e", exp_date, "-s", "/bin/false", "-M", username],
                       capture_output=True)
        subprocess.run(["chpasswd"], input=f"{username}:{password}", text=True,
                       capture_output=True)
        os.makedirs(ACCOUNT_DIR, exist_ok=True)
        save_account_conf(username, {
            "USERNAME": username, "PASSWORD": password,
            "LIMIT": tg["TG_LIMIT_IP"], "EXPIRED": exp_date,
            "EXPIRED_TS": str(exp_ts), "CREATED": datetime.now().strftime("%Y-%m-%d"),
            "IS_TRIAL": "1", "TG_USER_ID": str(uid),
            "SERVER": sname, "DOMAIN": domain
        })
    else:
        result = subprocess.run(
            ["sshpass", "-p", sconf.get("PASS",""),
             "ssh", "-o", "StrictHostKeyChecking=no",
             "-o", "ConnectTimeout=10", "-o", "BatchMode=no",
             "-p", sconf.get("PORT","22"),
             f"{sconf.get('USER','')}@{ip}",
             f"zv-agent add {username} {password} {tg['TG_LIMIT_IP']} 1"],
            capture_output=True, text=True, timeout=15
        )
        if not result.stdout.startswith("ADD-OK"):
            await cb.message.answer("❌ Gagal membuat akun trial."); return

    mark_trial(uid, sname)
    zv_log(f"TRIAL: {uid} server={sname} user={username}")
    await cb.message.answer(
        text_akun_info("TRIAL", username, password, domain,
                       exp_display, tg["TG_LIMIT_IP"], tg["TG_SERVER_LABEL"]),
        parse_mode="HTML", reply_markup=kb_home_btn()
    )

# ============================================================
# Callback: Akun Saya
# ============================================================
@dp.callback_query(F.data == "m_akun")
async def cb_akun_saya(cb: CallbackQuery):
    uid = cb.from_user.id
    await cb.answer()
    now_ts = int(time.time())
    out = "📋 <b>Akun Kamu</b>\n━━━━━━━━━━━━━━━━━━━\n"
    found = False

    try:
        for f in Path(ACCOUNT_DIR).glob("*.conf"):
            ac = load_account_conf(f.stem)
            if str(ac.get("TG_USER_ID","")).strip() != str(uid):
                continue
            uname  = ac.get("USERNAME","")
            passwd = ac.get("PASSWORD","")
            exp_ts_raw = ac.get("EXPIRED_TS","")
            is_trial = ac.get("IS_TRIAL","0") == "1"
            sname  = ac.get("SERVER","")
            # domain dari server conf
            sc = load_server_conf(sname)
            domain = sc.get("DOMAIN") or sc.get("IP") or ac.get("DOMAIN","")

            if not uname:
                continue

            if exp_ts_raw and exp_ts_raw.isdigit():
                exp_ts = int(exp_ts_raw)
                sisa   = exp_ts - now_ts
                exp_display = ts_to_wib(exp_ts)
                if sisa <= 0:
                    status = "❌ Expired"; sisa_label = "Sudah habis"
                elif sisa < 3600:
                    status = "⚠️ Aktif"; sisa_label = "Kurang dari 1 jam"
                elif sisa < 86400:
                    status = "⚠️ Aktif"; sisa_label = f"{sisa//3600} jam lagi"
                else:
                    status = "✅ Aktif"; sisa_label = f"{sisa//86400} hari lagi"
            else:
                exp_display = ac.get("EXPIRED","-")
                status = "✅ Aktif"; sisa_label = "-"

            tipe = "Trial" if is_trial else "Premium"
            found = True
            out += (
                f"\n👤 <b>{uname}</b> <i>({tipe})</i>\n"
                f"🌐 Host    : <code>{domain}</code>\n"
                f"🔑 Pass    : <code>{passwd}</code>\n"
                f"⏳ Expired : {exp_display}\n"
                f"📊 Status  : {status} · {sisa_label}\n"
                f"━━━━━━━━━━━━━━━━━━━"
            )
    except Exception as e:
        log.error(f"akun_saya error: {e}")

    if not found:
        out += "\nKamu belum punya akun aktif.\n\nTekan <b>Buat Akun</b> untuk membeli."

    await cb.message.edit_text(out, parse_mode="HTML", reply_markup=kb_home_btn())

# ============================================================
# Callback: Perpanjang
# ============================================================
@dp.callback_query(F.data == "m_perpanjang")
async def cb_perpanjang(cb: CallbackQuery):
    uid = cb.from_user.id
    await cb.answer()
    akun_list = []
    try:
        for f in Path(ACCOUNT_DIR).glob("*.conf"):
            ac = load_account_conf(f.stem)
            if str(ac.get("TG_USER_ID","")).strip() != str(uid):
                continue
            if ac.get("IS_TRIAL","0") == "1":
                continue
            uname = ac.get("USERNAME","")
            if uname:
                akun_list.append(uname)
    except Exception:
        pass

    if not akun_list:
        await cb.message.edit_text(
            "📋 <b>Perpanjang Akun</b>\n\nKamu belum punya akun premium yang bisa diperpanjang.",
            parse_mode="HTML", reply_markup=kb_home_btn()
        ); return

    b = InlineKeyboardBuilder()
    for i in range(0, len(akun_list), 2):
        row = [InlineKeyboardButton(text=akun_list[i], callback_data=f"renew_{akun_list[i]}")]
        if i+1 < len(akun_list):
            row.append(InlineKeyboardButton(text=akun_list[i+1], callback_data=f"renew_{akun_list[i+1]}"))
        b.row(*row)
    b.row(InlineKeyboardButton(text="↩ Kembali", callback_data="home"))
    await cb.message.edit_text("🔄 <b>Perpanjang Akun</b>\n\nPilih akun yang ingin diperpanjang:",
                                parse_mode="HTML", reply_markup=b.as_markup())

@dp.callback_query(F.data.startswith("renew_"))
async def cb_renew_akun(cb: CallbackQuery):
    username = cb.data[len("renew_"):]
    uid      = cb.from_user.id
    fname    = cb.from_user.first_name or "User"
    await cb.answer()

    ac = load_account_conf(username)
    if not ac:
        await cb.message.edit_text("❌ Akun tidak ditemukan.", reply_markup=kb_home_btn())
        return
    if str(ac.get("TG_USER_ID","")).strip() != str(uid):
        await cb.message.edit_text("❌ Akun ini bukan milikmu.", reply_markup=kb_home_btn())
        return

    sname = ac.get("SERVER","")
    tg    = load_tg_server_conf(sname)
    harga = int(tg["TG_HARGA_HARI"])
    hh    = f"Rp{fmt(harga)}/hari" if harga > 0 else "Gratis"
    exp_ts_raw = ac.get("EXPIRED_TS","")
    exp_display = ts_to_wib(int(exp_ts_raw)) if exp_ts_raw.isdigit() else ac.get("EXPIRED","-")

    state_clear(uid)
    state_set(uid, "STATE",    "renew_days")
    state_set(uid, "USERNAME", username)
    state_set(uid, "SERVER",   sname)
    state_set(uid, "FNAME",    fname)

    await cb.message.edit_text(
        f"🔄 <b>Perpanjang Akun</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"👤 Username : <code>{username}</code>\n"
        f"🌐 Server   : {tg['TG_SERVER_LABEL']}\n"
        f"⏳ Expired  : {exp_display}\n"
        f"💰 Harga    : {hh}\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"Berapa hari ingin diperpanjang? (1-365)",
        parse_mode="HTML",
        reply_markup=kb_back("m_perpanjang")
    )

@dp.callback_query(F.data == "konfirm_renew")
async def cb_konfirm_renew(cb: CallbackQuery):
    uid = cb.from_user.id
    if state_get(uid, "STATE") != "renew_confirm":
        await cb.answer("⚠️ Sesi habis, mulai ulang"); state_clear(uid); return
    await cb.answer("⏳ Memperpanjang akun...")

    username = state_get(uid, "USERNAME")
    sname    = state_get(uid, "SERVER")
    days     = int(state_get(uid, "DAYS") or "0")
    fname    = state_get(uid, "FNAME")

    tg    = load_tg_server_conf(sname)
    harga = int(tg["TG_HARGA_HARI"])
    total = harga * days

    if harga > 0 and total > 0:
        if not saldo_deduct(uid, total):
            await cb.message.edit_text("❌ Saldo tidak cukup. Hubungi admin untuk top up.")
            state_clear(uid); return

    ac = load_account_conf(username)
    now_ts   = int(time.time())
    old_exp  = int(ac.get("EXPIRED_TS", "0") or "0")
    base_ts  = old_exp if old_exp > now_ts else now_ts
    new_exp_ts   = base_ts + days * 86400
    new_exp_date = datetime.fromtimestamp(new_exp_ts).strftime("%Y-%m-%d")
    new_exp_disp = ts_to_wib(new_exp_ts)

    ac["EXPIRED"]    = new_exp_date
    ac["EXPIRED_TS"] = str(new_exp_ts)
    save_account_conf(username, ac)
    subprocess.run(["chage", "-E", new_exp_date, username], capture_output=True)

    try:
        Path(f"{NOTIFY_DIR}/{username}.notified").unlink(missing_ok=True)
    except Exception:
        pass

    state_clear(uid)
    zv_log(f"RENEW: {uid} user={username} days={days} total={total}")
    await notify_admin(bot, "RENEW", fname, uid, username, tg["TG_SERVER_LABEL"], days, total)
    backup_realtime(username, "renew")

    await cb.message.edit_text("✅ Akun berhasil diperpanjang!")
    await cb.message.answer(
        f"🔄 <b>Perpanjang Berhasil</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"👤 Username  : <code>{username}</code>\n"
        f"📅 Tambah    : {days} hari\n"
        f"⏳ Expired   : {new_exp_disp}\n"
        f"💸 Dibayar   : Rp{fmt(total)}\n"
        f"💰 Sisa Saldo: Rp{fmt(saldo_get(uid))}\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"Akun kamu sudah aktif sampai {new_exp_disp}!",
        parse_mode="HTML"
    )

# ============================================================
# Callback: Tambah Kuota
# ============================================================
@dp.callback_query(F.data == "m_tambah_bw")
async def cb_tambah_bw(cb: CallbackQuery):
    uid = cb.from_user.id
    await cb.answer()
    akun_list = []
    try:
        for f in Path(ACCOUNT_DIR).glob("*.conf"):
            ac = load_account_conf(f.stem)
            if str(ac.get("TG_USER_ID","")).strip() != str(uid): continue
            if ac.get("IS_TRIAL","0") == "1": continue
            if not ac.get("BW_QUOTA_BYTES","0") or ac.get("BW_QUOTA_BYTES","0") == "0": continue
            uname = ac.get("USERNAME","")
            if uname: akun_list.append(uname)
    except Exception: pass

    if not akun_list:
        await cb.message.edit_text(
            "📶 <b>Tambah Kuota</b>\n\nTidak ada akun yang mendukung fitur kuota.",
            parse_mode="HTML", reply_markup=kb_home_btn()
        ); return

    b = InlineKeyboardBuilder()
    for i in range(0, len(akun_list), 2):
        row = [InlineKeyboardButton(text=akun_list[i], callback_data=f"bw_akun_{akun_list[i]}")]
        if i+1 < len(akun_list):
            row.append(InlineKeyboardButton(text=akun_list[i+1], callback_data=f"bw_akun_{akun_list[i+1]}"))
        b.row(*row)
    b.row(InlineKeyboardButton(text="↩ Kembali", callback_data="m_akun"))
    await cb.message.edit_text("➕ <b>Tambah Kuota</b>\n\nPilih akun:",
                                parse_mode="HTML", reply_markup=b.as_markup())

@dp.callback_query(F.data.startswith("bw_akun_"))
async def cb_bw_akun(cb: CallbackQuery):
    username = cb.data[len("bw_akun_"):]
    uid = cb.from_user.id
    await cb.answer()
    ac = load_account_conf(username)
    if not ac:
        await cb.message.edit_text("❌ Akun tidak ditemukan.", reply_markup=kb_home_btn()); return
    if str(ac.get("TG_USER_ID","")).strip() != str(uid):
        await cb.answer("❌ Bukan akun kamu"); return

    sname = ac.get("SERVER","")
    tg    = load_tg_server_conf(sname)
    harga_hari  = int(tg["TG_HARGA_HARI"] or "0")
    bw_per_hari = int(tg.get("TG_BW_PER_HARI","5") or "5")
    harga_per_gb = (harga_hari // bw_per_hari) if bw_per_hari > 0 else 0

    bw_quota = int(ac.get("BW_QUOTA_BYTES","0") or "0")
    bw_used  = int(ac.get("BW_USED_BYTES","0") or "0")
    bw_blocked = ac.get("BW_BLOCKED","0") == "1"
    pct = int(bw_used * 100 / bw_quota) if bw_quota > 0 else 0
    bar_filled = pct // 10
    bar = "█" * bar_filled + "░" * (10 - bar_filled)

    status_str = "🚫 Diblokir (BW habis)" if bw_blocked else "✅ Aktif"
    p1 = harga_per_gb * 1; p5 = harga_per_gb * 5; p10 = harga_per_gb * 10

    state_clear(uid)
    state_set(uid, "STATE",    "bw_pilih_paket")
    state_set(uid, "USERNAME", username)
    state_set(uid, "SERVER",   sname)

    b = InlineKeyboardBuilder()
    b.row(
        InlineKeyboardButton(text=f"➕ 1 GB — Rp{fmt(p1)}", callback_data=f"bw_beli_1_{username}"),
        InlineKeyboardButton(text=f"➕ 5 GB — Rp{fmt(p5)}", callback_data=f"bw_beli_5_{username}")
    )
    b.row(InlineKeyboardButton(text=f"➕ 10 GB — Rp{fmt(p10)}", callback_data=f"bw_beli_10_{username}"))
    b.row(InlineKeyboardButton(text="↩ Kembali", callback_data="m_tambah_bw"))

    await cb.message.edit_text(
        f"➕ <b>Tambah Kuota</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"👤 Username : <code>{username}</code>\n"
        f"📶 Terpakai : {fmt_bytes(bw_used)} / {fmt_bytes(bw_quota)}\n"
        f"[{bar}] {pct}%\n"
        f"📊 Status   : {status_str}\n"
        f"💰 Saldo    : Rp{fmt(saldo_get(uid))}\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"Pilih paket tambahan:",
        parse_mode="HTML", reply_markup=b.as_markup()
    )

@dp.callback_query(F.data.startswith("bw_beli_"))
async def cb_bw_beli(cb: CallbackQuery):
    # bw_beli_1_username
    parts    = cb.data.split("_", 3)
    gb       = int(parts[2])
    username = parts[3]
    uid      = cb.from_user.id
    await cb.answer()

    ac = load_account_conf(username)
    sname = ac.get("SERVER","")
    tg    = load_tg_server_conf(sname)
    harga_hari  = int(tg["TG_HARGA_HARI"] or "0")
    bw_per_hari = int(tg.get("TG_BW_PER_HARI","5") or "5")
    harga_per_gb = (harga_hari // bw_per_hari) if bw_per_hari > 0 else 0
    total = harga_per_gb * gb
    saldo = saldo_get(uid)

    if total > 0 and saldo < total:
        await cb.message.edit_text(
            f"❌ Saldo tidak cukup.\nSaldo  : Rp{fmt(saldo)}\nButuh  : Rp{fmt(total)}\n\nHubungi admin untuk top up.",
            reply_markup=kb_home_btn()
        )
        state_clear(uid); return

    state_set(uid, "STATE",    "bw_confirm")
    state_set(uid, "USERNAME", username)
    state_set(uid, "SERVER",   sname)
    state_set(uid, "BW_GB",    str(gb))
    state_set(uid, "BW_TOTAL", str(total))

    await cb.message.edit_text(
        f"➕ <b>Konfirmasi Tambah Kuota</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"👤 Username    : <code>{username}</code>\n"
        f"📶 Tambah Kuota : {gb} GB\n"
        f"💸 Total       : Rp{fmt(total)}\n"
        f"💰 Saldo       : Rp{fmt(saldo)}\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"Lanjutkan?",
        parse_mode="HTML", reply_markup=kb_confirm("bw_konfirm")
    )

@dp.callback_query(F.data == "bw_konfirm")
async def cb_konfirm_bw(cb: CallbackQuery):
    uid = cb.from_user.id
    if state_get(uid, "STATE") != "bw_confirm":
        await cb.answer("⚠️ Sesi habis"); state_clear(uid); return
    await cb.answer("⏳ Memproses...")

    username = state_get(uid, "USERNAME")
    gb       = int(state_get(uid, "BW_GB") or "0")
    total    = int(state_get(uid, "BW_TOTAL") or "0")
    sname    = state_get(uid, "SERVER")

    if total > 0:
        if not saldo_deduct(uid, total):
            await cb.message.edit_text("❌ Saldo tidak cukup."); state_clear(uid); return

    add_bytes = gb * 1024 * 1024 * 1024
    ac = load_account_conf(username)
    old_quota = int(ac.get("BW_QUOTA_BYTES","0") or "0")
    old_used  = int(ac.get("BW_USED_BYTES","0") or "0")
    ac["BW_QUOTA_BYTES"] = str(old_quota + add_bytes)
    ac["BW_BLOCKED"]     = "0"
    save_account_conf(username, ac)

    # Sync iptables via shell
    subprocess.run(["/bin/bash", "-c",
        f"source /etc/zv-manager/core/bandwidth.sh && _bw_unblock {username}"],
        capture_output=True)

    state_clear(uid)
    zv_log(f"BW_BELI: {uid} user={username} gb={gb} total={total}")

    new_quota = int(ac["BW_QUOTA_BYTES"])
    await cb.message.edit_text("✅ Kuota ditambahkan!")
    await cb.message.answer(
        f"➕ <b>Kuota Berhasil Ditambahkan</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"👤 Username     : <code>{username}</code>\n"
        f"📶 Ditambah     : {gb} GB\n"
        f"📊 Total Kuota  : {fmt_bytes(new_quota)}\n"
        f"📈 Terpakai     : {fmt_bytes(old_used)}\n"
        f"💸 Dibayar      : Rp{fmt(total)}\n"
        f"💰 Sisa Saldo   : Rp{fmt(saldo_get(uid))}\n"
        f"━━━━━━━━━━━━━━━━━━━\nKoneksi sudah aktif kembali!",
        parse_mode="HTML"
    )

# ============================================================
# Callback: Riwayat Saldo
# ============================================================
@dp.callback_query(F.data == "m_saldo_history")
async def cb_saldo_history(cb: CallbackQuery):
    uid = cb.from_user.id
    await cb.answer()
    saldo = saldo_get(uid)
    entries = []
    total_bulan = 0
    bulan_ini = datetime.now().strftime("%Y-%m")
    uid_str = str(uid)

    # tail_log: baca dari akhir file — jauh lebih cepat
    for line in tail_log(300):
        if "] TOPUP:" not in line: continue
        if f"target={uid_str} " not in line: continue
        ts_m = re.search(r"^\[([^\]]+)\]", line)
        am_m = re.search(r"amount=(\d+)", line)
        if not ts_m or not am_m: continue
        ts = ts_m.group(1); amount = int(am_m.group(1))
        entries.append((ts, amount))
        if ts[:7] == bulan_ini:
            total_bulan += amount

    bulan_label = datetime.now().strftime("%B %Y")
    msg = (
        f"💰 <b>Riwayat Saldo</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"💳 Saldo sekarang : Rp{fmt(saldo)}\n"
        f"📅 Total topup {bulan_label} : Rp{fmt(total_bulan)}\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
    )
    if not entries:
        msg += "Belum ada riwayat top up."
    else:
        for ts, amount in entries[-10:]:
            msg += f"💰 +Rp{fmt(amount)}\n   <i>{ts}</i>\n─────────────────\n"

    msg += "━━━━━━━━━━━━━━━━━━━"
    b = InlineKeyboardBuilder()
    b.row(
        InlineKeyboardButton(text="📝 Riwayat Transaksi", callback_data="m_history"),
        InlineKeyboardButton(text="🏠 Menu Utama", callback_data="home")
    )
    await cb.message.edit_text(msg, parse_mode="HTML", reply_markup=b.as_markup())

# ============================================================
# Callback: Riwayat Transaksi
# ============================================================
@dp.callback_query(F.data == "m_history")
async def cb_history(cb: CallbackQuery):
    uid = cb.from_user.id
    await cb.answer()
    entries = []
    uid_str = str(uid)

    for line in tail_log(500):
        if f"] BELI: {uid_str} " in line:
            try:
                ts    = re.search(r"^\[([^\]]+)\]", line).group(1)
                user  = re.search(r"user=(\S+)", line).group(1)
                days  = re.search(r"days=(\d+)", line).group(1)
                total = re.search(r"total=(\d+)", line).group(1)
                entries.append(f"🛒 Buat Akun <code>{user}</code>\n   {days} hari — Rp{fmt(total)}\n   <i>{ts}</i>")
            except Exception: pass
        elif f"] RENEW: {uid_str} " in line:
            try:
                ts    = re.search(r"^\[([^\]]+)\]", line).group(1)
                user  = re.search(r"user=(\S+)", line).group(1)
                days  = re.search(r"days=(\d+)", line).group(1)
                total = re.search(r"total=(\d+)", line).group(1)
                entries.append(f"🔄 Perpanjang <code>{user}</code>\n   +{days} hari — Rp{fmt(total)}\n   <i>{ts}</i>")
            except Exception: pass
        elif f"] BW_BELI: {uid_str} " in line:
            try:
                ts    = re.search(r"^\[([^\]]+)\]", line).group(1)
                user  = re.search(r"user=(\S+)", line).group(1)
                gb    = re.search(r"gb=(\d+)", line).group(1)
                total = re.search(r"total=(\d+)", line).group(1)
                entries.append(f"📶 Tambah Kuota <code>{user}</code>\n   +{gb} GB — Rp{fmt(total)}\n   <i>{ts}</i>")
            except Exception: pass

    if not entries:
        await cb.message.edit_text(
            "📝 <b>Riwayat Transaksi</b>\n\nBelum ada transaksi.",
            parse_mode="HTML", reply_markup=kb_home_btn()
        ); return

    msg = f"📝 <b>Riwayat Transaksi</b> ({len(entries)} total)\n━━━━━━━━━━━━━━━━━━━\n"
    for i, e in enumerate(entries[-10:]):
        msg += e + "\n"
        if i < len(entries[-10:]) - 1:
            msg += "─────────────────\n"
    msg += f"━━━━━━━━━━━━━━━━━━━\n💳 Saldo saat ini: Rp{fmt(saldo_get(uid))}"

    await cb.message.edit_text(msg, parse_mode="HTML", reply_markup=kb_home_btn())

# ============================================================
# Callback: Konfirmasi buat akun
# ============================================================
@dp.callback_query(F.data == "konfirm")
async def cb_konfirm(cb: CallbackQuery):
    uid = cb.from_user.id
    if state_get(uid, "STATE") != "await_confirm":
        await cb.answer("⚠️ Sesi habis, mulai ulang"); state_clear(uid); return
    await cb.answer("⏳ Membuat akun...")

    sname    = state_get(uid, "SERVER")
    username = state_get(uid, "USERNAME")
    password = state_get(uid, "PASSWORD")
    days     = int(state_get(uid, "DAYS") or "1")
    fname    = state_get(uid, "FNAME")

    sconf = load_server_conf(sname)
    tg    = load_tg_server_conf(sname)
    ip    = sconf.get("IP","")
    lip   = local_ip()
    domain = sconf.get("DOMAIN") or ip

    harga  = int(tg["TG_HARGA_HARI"])
    total  = harga * days
    now_ts = int(time.time())
    exp_ts = now_ts + days * 86400
    exp_date    = datetime.fromtimestamp(exp_ts).strftime("%Y-%m-%d")
    exp_display = ts_to_wib(exp_ts)

    if harga > 0 and total > 0:
        if not saldo_deduct(uid, total):
            await cb.message.edit_text("❌ Saldo tidak cukup. Hubungi admin.")
            state_clear(uid); return

    if ip == lip:
        subprocess.run(["useradd", "-e", exp_date, "-s", "/bin/false", "-M", username],
                       capture_output=True)
        subprocess.run(["chpasswd"], input=f"{username}:{password}", text=True,
                       capture_output=True)
        bw_per_hari   = int(tg.get("TG_BW_PER_HARI","5") or "5")
        bw_quota_bytes = days * bw_per_hari * 1024 * 1024 * 1024
        os.makedirs(ACCOUNT_DIR, exist_ok=True)
        save_account_conf(username, {
            "USERNAME": username, "PASSWORD": password,
            "LIMIT": tg["TG_LIMIT_IP"], "EXPIRED": exp_date,
            "EXPIRED_TS": str(exp_ts), "CREATED": datetime.now().strftime("%Y-%m-%d"),
            "IS_TRIAL": "0", "TG_USER_ID": str(uid),
            "SERVER": sname, "DOMAIN": domain,
            "BW_QUOTA_BYTES": str(bw_quota_bytes),
            "BW_USED_BYTES": "0", "BW_BLOCKED": "0"
        })
        subprocess.run(["/bin/bash", "-c",
            f"source /etc/zv-manager/core/bandwidth.sh && _bw_init_user {username}"],
            capture_output=True)
    else:
        result = subprocess.run(
            ["sshpass", "-p", sconf.get("PASS",""),
             "ssh", "-o", "StrictHostKeyChecking=no",
             "-o", "ConnectTimeout=10", "-o", "BatchMode=no",
             "-p", sconf.get("PORT","22"),
             f"{sconf.get('USER','')}@{ip}",
             f"zv-agent add {username} {password} {tg['TG_LIMIT_IP']} {days}"],
            capture_output=True, text=True, timeout=15
        )
        if not result.stdout.startswith("ADD-OK"):
            if total > 0:
                saldo_add(uid, total)  # refund
            await cb.message.edit_text("❌ Gagal membuat akun. Saldo dikembalikan.")
            state_clear(uid); return

    state_clear(uid)
    zv_log(f"BELI: {uid} server={sname} user={username} days={days} total={total}")
    await notify_admin(bot, "BELI", fname, uid, username, tg["TG_SERVER_LABEL"], days, total)
    backup_realtime(username, "create")
    await cb.message.edit_text("✅ Akun sedang dibuat...")
    await cb.message.answer(
        text_akun_info("BELI", username, password, domain, exp_display,
                       tg["TG_LIMIT_IP"], tg["TG_SERVER_LABEL"], days, total),
        parse_mode="HTML", reply_markup=kb_home_btn()
    )

# ============================================================
# Callback: Admin Panel
# ============================================================
@dp.callback_query(F.data == "m_admin")
async def cb_admin_panel(cb: CallbackQuery):
    uid = cb.from_user.id
    if uid != ADMIN_ID:
        await cb.answer("❌ Akses ditolak"); return
    await cb.answer()

    total_user = len(list(Path(USERS_DIR).glob("*.user"))) if Path(USERS_DIR).exists() else 0
    total_akun = len(list(Path(ACCOUNT_DIR).glob("*.conf"))) if Path(ACCOUNT_DIR).exists() else 0

    await cb.message.edit_text(
        f"🔧 <b>Admin Panel</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"👥 User terdaftar : {total_user} user\n"
        f"🖥️ Total akun SSH : {total_akun} akun\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"💰 <b>Top Up Saldo</b> — Tambah saldo ke user\n"
        f"➖ <b>Kurangi Saldo</b> — Potong saldo dari user\n"
        f"🗑️ <b>Hapus Akun</b> — Hapus akun SSH dari bot\n"
        f"📢 <b>Broadcast</b> — Kirim pesan ke semua user\n"
        f"👥 <b>Daftar User</b> — Lihat semua user terdaftar\n"
        f"🔍 <b>Cek User</b> — Cek saldo & akun milik user\n"
        f"📊 <b>History Transaksi</b> — Log semua transaksi\n"
        f"━━━━━━━━━━━━━━━━━━━",
        parse_mode="HTML", reply_markup=kb_admin_panel()
    )

@dp.callback_query(F.data == "m_broadcast")
async def cb_broadcast(cb: CallbackQuery):
    uid = cb.from_user.id
    if uid != ADMIN_ID:
        await cb.answer("❌ Akses ditolak"); return
    await cb.answer()
    state_clear(uid)
    await cb.message.edit_text(
        "📢 <b>Broadcast</b>\n━━━━━━━━━━━━━━━━━━━\n"
        "Pilih jenis broadcast:",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[
            [InlineKeyboardButton(text="✉️ Teks / HTML", callback_data="bc_teks")],
            [InlineKeyboardButton(text="🎭 Stiker", callback_data="bc_stiker")],
            [InlineKeyboardButton(text="❌ Batal", callback_data="home")],
        ])
    )

@dp.callback_query(F.data == "bc_teks")
async def cb_bc_teks(cb: CallbackQuery):
    uid = cb.from_user.id
    if uid != ADMIN_ID:
        await cb.answer("❌ Akses ditolak"); return
    await cb.answer()
    state_clear(uid)
    state_set(uid, "STATE", "broadcast_msg")
    await cb.message.edit_text(
        "📢 <b>Broadcast Teks</b>\n━━━━━━━━━━━━━━━━━━━\n"
        "Ketik pesan yang akan dikirim ke semua user.\n"
        "Bisa pakai format HTML: <code>&lt;b&gt;bold&lt;/b&gt;</code>, <code>&lt;i&gt;italic&lt;/i&gt;</code>\n\n"
        "Ketik pesan:",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
            InlineKeyboardButton(text="❌ Batal", callback_data="home")
        ]])
    )

@dp.callback_query(F.data == "bc_stiker")
async def cb_bc_stiker(cb: CallbackQuery):
    uid = cb.from_user.id
    if uid != ADMIN_ID:
        await cb.answer("❌ Akses ditolak"); return
    await cb.answer()
    state_clear(uid)
    state_set(uid, "STATE", "broadcast_stiker")
    await cb.message.edit_text(
        "🎭 <b>Broadcast Stiker</b>\n━━━━━━━━━━━━━━━━━━━\n"
        "Kirim satu stiker yang ingin di-broadcast ke semua user.\n\n"
        "<i>Kirim stiker sekarang:</i>",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
            InlineKeyboardButton(text="❌ Batal", callback_data="home")
        ]])
    )

@dp.callback_query(F.data == "adm_topup")
async def cb_adm_topup(cb: CallbackQuery):
    uid = cb.from_user.id
    if uid != ADMIN_ID:
        await cb.answer("❌ Akses ditolak"); return
    await cb.answer()
    state_clear(uid)
    state_set(uid, "STATE", "adm_topup_uid")
    await cb.message.edit_text(
        "💰 <b>Top Up Saldo</b>\n━━━━━━━━━━━━━━━━━━━\n"
        "Ketik <b>User ID</b> yang ingin di-top up.\n\n"
        "Contoh: <code>123456789</code>\n\n"
        "💡 User ID bisa dilihat saat user kirim /start ke bot.",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
            InlineKeyboardButton(text="❌ Batal", callback_data="m_admin")
        ]])
    )

@dp.callback_query(F.data == "adm_kurangi")
async def cb_adm_kurangi(cb: CallbackQuery):
    uid = cb.from_user.id
    if uid != ADMIN_ID:
        await cb.answer("❌ Akses ditolak"); return
    await cb.answer()
    state_clear(uid)
    state_set(uid, "STATE", "adm_kurangi_uid")
    await cb.message.edit_text(
        "➖ <b>Kurangi Saldo</b>\n━━━━━━━━━━━━━━━━━━━\n"
        "Ketik <b>User ID</b> yang saldonya ingin dikurangi.\n\n"
        "Contoh: <code>123456789</code>",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
            InlineKeyboardButton(text="❌ Batal", callback_data="m_admin")
        ]])
    )

@dp.callback_query(F.data == "adm_hapus_akun")
async def cb_adm_hapus_akun(cb: CallbackQuery):
    uid = cb.from_user.id
    if uid != ADMIN_ID:
        await cb.answer("❌ Akses ditolak"); return
    await cb.answer()
    state_clear(uid)
    state_set(uid, "STATE", "adm_hapus_username")
    await cb.message.edit_text(
        "🗑️ <b>Hapus Akun SSH</b>\n━━━━━━━━━━━━━━━━━━━\n"
        "Ketik <b>username</b> akun yang ingin dihapus.\n\n"
        "Contoh: <code>user123</code>\n\n"
        "⚠️ Akun akan langsung dihapus dari sistem!",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
            InlineKeyboardButton(text="❌ Batal", callback_data="m_admin")
        ]])
    )

@dp.callback_query(F.data == "adm_daftar_user")
async def cb_adm_daftar_user(cb: CallbackQuery):
    uid = cb.from_user.id
    if uid != ADMIN_ID:
        await cb.answer("❌ Akses ditolak"); return
    await cb.answer()

    users = []
    if Path(USERS_DIR).exists():
        for f in Path(USERS_DIR).glob("*.user"):
            info = load_user_info(int(f.stem))
            if info.get("UID"):
                users.append(info)

    if not users:
        await cb.message.edit_text("👥 <b>Daftar User</b>\n\nBelum ada user terdaftar.",
                                    parse_mode="HTML", reply_markup=kb_admin_panel())
        return

    msg = f"👥 <b>Daftar User Terdaftar</b> ({len(users)} total)\n━━━━━━━━━━━━━━━━━━━\n"
    for u in users[-20:]:
        saldo = saldo_get(int(u.get("UID","0")))
        msg += (f"👤 <b>{u.get('NAME','-')}</b> — <code>{u.get('UID','-')}</code>\n"
                f"   💰 Rp{fmt(saldo)} | 📅 {u.get('JOINED','-')[:10]}\n")
    msg += "━━━━━━━━━━━━━━━━━━━"

    await cb.message.edit_text(msg, parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
            InlineKeyboardButton(text="↩ Kembali", callback_data="m_admin")
        ]]))

@dp.callback_query(F.data == "adm_cek_user")
async def cb_adm_cek_user(cb: CallbackQuery):
    uid = cb.from_user.id
    if uid != ADMIN_ID:
        await cb.answer("❌ Akses ditolak"); return
    await cb.answer()
    state_clear(uid)
    state_set(uid, "STATE", "adm_cek_uid")
    await cb.message.edit_text(
        "🔍 <b>Cek User</b>\n━━━━━━━━━━━━━━━━━━━\n"
        "Ketik <b>User ID</b> yang ingin dicek.\n\nContoh: <code>123456789</code>",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
            InlineKeyboardButton(text="❌ Batal", callback_data="m_admin")
        ]])
    )

@dp.callback_query(F.data == "adm_history")
async def cb_adm_history(cb: CallbackQuery):
    uid = cb.from_user.id
    if uid != ADMIN_ID:
        await cb.answer("❌ Akses ditolak"); return
    await cb.answer()

    entries = []
    for line in tail_log(200):
        for tag in ["BELI", "RENEW", "BW_BELI", "TOPUP", "KURANGI"]:
            if f"] {tag}:" in line:
                entries.append(line.strip())
                break

    if not entries:
        await cb.message.edit_text("📊 <b>History Transaksi</b>\n\nBelum ada transaksi tercatat.",
                                    parse_mode="HTML",
                                    reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
                                        InlineKeyboardButton(text="↩ Kembali", callback_data="m_admin")
                                    ]])); return

    msg = f"📊 <b>History Transaksi</b> ({len(entries)} total, 15 terakhir)\n━━━━━━━━━━━━━━━━━━━\n"
    for i, line in enumerate(entries[-15:]):
        ts_m = re.search(r"^\[([^\]]+)\]", line)
        ts   = ts_m.group(1) if ts_m else "-"
        if "] BELI:" in line:
            uid_m = re.search(r"BELI: (\S+)", line)
            user  = re.search(r"user=(\S+)", line)
            days  = re.search(r"days=(\d+)", line)
            tot   = re.search(r"total=(\d+)", line)
            srv   = re.search(r"server=(\S+)", line)
            msg += (f"🛒 <b>Beli</b> — <code>{user.group(1) if user else '?'}</code> ({srv.group(1) if srv else '?'})\n"
                    f"   {days.group(1) if days else '?'} hari · Rp{fmt(tot.group(1) if tot else 0)} · uid:{uid_m.group(1) if uid_m else '?'}\n"
                    f"   <i>{ts}</i>\n")
        elif "] RENEW:" in line:
            uid_m = re.search(r"RENEW: (\S+)", line)
            user  = re.search(r"user=(\S+)", line)
            days  = re.search(r"days=(\d+)", line)
            tot   = re.search(r"total=(\d+)", line)
            msg += (f"🔄 <b>Renew</b> — <code>{user.group(1) if user else '?'}</code>\n"
                    f"   +{days.group(1) if days else '?'} hari · Rp{fmt(tot.group(1) if tot else 0)} · uid:{uid_m.group(1) if uid_m else '?'}\n"
                    f"   <i>{ts}</i>\n")
        elif "] BW_BELI:" in line:
            uid_m = re.search(r"BW_BELI: (\S+)", line)
            user  = re.search(r"user=(\S+)", line)
            gb    = re.search(r"gb=(\d+)", line)
            tot   = re.search(r"total=(\d+)", line)
            msg += (f"📶 <b>Beli BW</b> — <code>{user.group(1) if user else '?'}</code>\n"
                    f"   +{gb.group(1) if gb else '?'} GB · Rp{fmt(tot.group(1) if tot else 0)} · uid:{uid_m.group(1) if uid_m else '?'}\n"
                    f"   <i>{ts}</i>\n")
        elif "] TOPUP:" in line:
            adm    = re.search(r"admin=(\S+)", line)
            target = re.search(r"target=(\S+)", line)
            amt    = re.search(r"amount=(\d+)", line)
            msg += (f"💰 <b>Top Up</b> — uid:{target.group(1) if target else '?'}\n"
                    f"   +Rp{fmt(amt.group(1) if amt else 0)} oleh admin:{adm.group(1) if adm else '?'}\n"
                    f"   <i>{ts}</i>\n")
        elif "] KURANGI:" in line:
            adm    = re.search(r"admin=(\S+)", line)
            target = re.search(r"target=(\S+)", line)
            amt    = re.search(r"amount=(\d+)", line)
            msg += (f"➖ <b>Kurangi</b> — uid:{target.group(1) if target else '?'}\n"
                    f"   -Rp{fmt(amt.group(1) if amt else 0)} oleh admin:{adm.group(1) if adm else '?'}\n"
                    f"   <i>{ts}</i>\n")
        if i < min(14, len(entries[-15:]) - 1):
            msg += "─────────────────\n"

    msg += "━━━━━━━━━━━━━━━━━━━"
    await cb.message.edit_text(msg, parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
            InlineKeyboardButton(text="↩ Kembali", callback_data="m_admin")
        ]]))

# ============================================================
# Message handler: multi-step input & broadcast
# ============================================================
@dp.message()
async def handle_message(msg: Message):
    uid   = msg.from_user.id
    fname = msg.from_user.first_name or "User"
    text  = msg.text or ""
    state = state_get(uid, "STATE")

    if not state:
        return

    # ---- Broadcast teks ----
    if state == "broadcast_msg":
        if uid != ADMIN_ID:
            state_clear(uid); return
        if not text:
            await msg.answer("❌ Pesan tidak boleh kosong. Ketik pesan teks:"); return
        state_clear(uid)
        await do_broadcast(msg, text)
        return

    # ---- Broadcast stiker ----
    if state == "broadcast_stiker":
        if uid != ADMIN_ID:
            state_clear(uid); return
        sticker = msg.sticker
        if not sticker:
            await msg.answer(
                "❌ Itu bukan stiker. Kirim stiker yang valid:",
                reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
                    InlineKeyboardButton(text="❌ Batal", callback_data="home")
                ]])
            ); return
        state_clear(uid)
        await do_broadcast_stiker(msg, sticker.file_id)
        return

    # ---- Admin: topup uid ----
    if state == "adm_topup_uid":
        if uid != ADMIN_ID:
            state_clear(uid); return
        if not re.match(r"^\d{5,15}$", text):
            await msg.answer("❌ User ID tidak valid. Harus angka 5-15 digit.\n\nKetik User ID:"); return
        state_set(uid, "ADM_TARGET", text)
        state_set(uid, "STATE", "adm_topup_amount")
        t_info = load_user_info(int(text))
        t_name = t_info.get("NAME", "(belum terdaftar)")
        t_saldo = saldo_get(int(text))
        await msg.answer(
            f"💰 <b>Top Up Saldo</b>\n━━━━━━━━━━━━━━━━━━━\n"
            f"🆔 User ID : <code>{text}</code>\n"
            f"👤 Nama    : {t_name}\n"
            f"💰 Saldo   : Rp{fmt(t_saldo)}\n"
            f"━━━━━━━━━━━━━━━━━━━\n"
            f"Ketik <b>jumlah</b> top up (angka):\nContoh: <code>50000</code>",
            parse_mode="HTML"
        ); return

    # ---- Admin: topup amount ----
    if state == "adm_topup_amount":
        if uid != ADMIN_ID:
            state_clear(uid); return
        if not text.isdigit() or int(text) == 0:
            await msg.answer("❌ Jumlah tidak valid.\n\nKetik jumlah top up:"); return
        target = int(state_get(uid, "ADM_TARGET") or "0")
        amount = int(text)
        state_clear(uid)
        cur = saldo_get(target)
        new = saldo_add(target, amount)
        zv_log(f"TOPUP: admin={uid} target={target} amount={amount} new={new}")
        t_info = load_user_info(target)
        t_name = t_info.get("NAME", "User")
        await msg.answer(
            f"✅ <b>Top Up Berhasil</b>\n━━━━━━━━━━━━━━━━━━━\n"
            f"🆔 User ID  : <code>{target}</code>\n"
            f"👤 Nama     : {t_name}\n"
            f"➖ Ditambah : Rp{fmt(amount)}\n"
            f"💰 Saldo    : Rp{fmt(cur)} → Rp{fmt(new)}\n"
            f"━━━━━━━━━━━━━━━━━━━",
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
                InlineKeyboardButton(text="💰 Top Up Lagi", callback_data="adm_topup"),
                InlineKeyboardButton(text="↩ Admin Panel", callback_data="m_admin")
            ]])
        )
        try:
            await bot.send_message(target,
                f"💰 <b>Saldo Kamu Bertambah!</b>\n━━━━━━━━━━━━━━━━━━━\n"
                f"💳 Ditambah : Rp{fmt(amount)}\n💰 Saldo    : Rp{fmt(new)}\n"
                f"━━━━━━━━━━━━━━━━━━━\nTerima kasih sudah top up! 🙏",
                parse_mode="HTML", reply_markup=kb_home_btn())
        except Exception: pass
        return

    # ---- Admin: kurangi uid ----
    if state == "adm_kurangi_uid":
        if uid != ADMIN_ID:
            state_clear(uid); return
        if not re.match(r"^\d{5,15}$", text):
            await msg.answer("❌ User ID tidak valid.\n\nKetik User ID:"); return
        state_set(uid, "ADM_TARGET", text)
        state_set(uid, "STATE", "adm_kurangi_amount")
        t_info = load_user_info(int(text))
        t_name = t_info.get("NAME", "(belum terdaftar)")
        t_saldo = saldo_get(int(text))
        await msg.answer(
            f"➖ <b>Kurangi Saldo</b>\n━━━━━━━━━━━━━━━━━━━\n"
            f"🆔 User ID : <code>{text}</code>\n"
            f"👤 Nama    : {t_name}\n"
            f"💰 Saldo   : Rp{fmt(t_saldo)}\n"
            f"━━━━━━━━━━━━━━━━━━━\n"
            f"Ketik <b>jumlah</b> yang ingin dikurangi:\nContoh: <code>5000</code>",
            parse_mode="HTML"
        ); return

    # ---- Admin: kurangi amount ----
    if state == "adm_kurangi_amount":
        if uid != ADMIN_ID:
            state_clear(uid); return
        if not text.isdigit() or int(text) == 0:
            await msg.answer("❌ Jumlah tidak valid.\n\nKetik jumlah yang dikurangi:"); return
        target = int(state_get(uid, "ADM_TARGET") or "0")
        amount = int(text)
        state_clear(uid)
        cur = saldo_get(target)
        if amount > cur:
            await msg.answer(
                f"❌ Saldo user tidak cukup.\n💰 Saldo saat ini : Rp{fmt(cur)}\n➖ Mau dikurangi  : Rp{fmt(amount)}",
                reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
                    InlineKeyboardButton(text="➖ Coba Lagi", callback_data="adm_kurangi"),
                    InlineKeyboardButton(text="↩ Admin Panel", callback_data="m_admin")
                ]])
            ); return
        new = cur - amount
        saldo_set(target, new)
        zv_log(f"KURANGI: admin={uid} target={target} amount={amount} new={new}")
        t_info = load_user_info(target)
        t_name = t_info.get("NAME", "User")
        await msg.answer(
            f"✅ <b>Saldo Berhasil Dikurangi</b>\n━━━━━━━━━━━━━━━━━━━\n"
            f"🆔 User ID  : <code>{target}</code>\n"
            f"👤 Nama     : {t_name}\n"
            f"➖ Dikurangi : Rp{fmt(amount)}\n"
            f"💰 Saldo    : Rp{fmt(cur)} → Rp{fmt(new)}\n"
            f"━━━━━━━━━━━━━━━━━━━",
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
                InlineKeyboardButton(text="➖ Kurangi Lagi", callback_data="adm_kurangi"),
                InlineKeyboardButton(text="↩ Admin Panel", callback_data="m_admin")
            ]])
        )
        try:
            await bot.send_message(target,
                f"⚠️ <b>Saldo Kamu Berubah</b>\n━━━━━━━━━━━━━━━━━━━\n"
                f"➖ Dikurangi : Rp{fmt(amount)}\n💰 Saldo    : Rp{fmt(new)}\n"
                f"━━━━━━━━━━━━━━━━━━━\nHubungi admin jika ada pertanyaan.",
                parse_mode="HTML", reply_markup=kb_home_btn())
        except Exception: pass
        return

    # ---- Admin: hapus akun ----
    if state == "adm_hapus_username":
        if uid != ADMIN_ID:
            state_clear(uid); return
        if not re.match(r"^[a-zA-Z0-9]{3,20}$", text):
            await msg.answer("❌ Username tidak valid.\n\nKetik username:"); return
        state_clear(uid)
        await do_hapus_akun(msg, text, uid)
        return

    # ---- Admin: cek user ----
    if state == "adm_cek_uid":
        if uid != ADMIN_ID:
            state_clear(uid); return
        if not re.match(r"^\d{5,15}$", text):
            await msg.answer("❌ User ID tidak valid.\n\nKetik User ID:"); return
        state_clear(uid)
        await do_cek_user(msg, int(text))
        return

    # ---- Buat akun: username ----
    if state == "await_user":
        if not re.match(r"^[a-zA-Z0-9]{3,20}$", text):
            await msg.answer("❌ Username tidak valid. Huruf dan angka, 3-20 karakter.\n\nKetik username:"); return
        result = subprocess.run(["id", text], capture_output=True)
        if result.returncode == 0:
            await msg.answer(f"❌ Username <b>{text}</b> sudah digunakan.\n\nKetik username lain:",
                             parse_mode="HTML"); return
        state_set(uid, "USERNAME", text)
        state_set(uid, "STATE", "await_pass")
        await msg.answer("Ketik password:\n(Minimal 4 karakter, boleh huruf besar/kecil dan angka)")
        return

    # ---- Buat akun: password ----
    if state == "await_pass":
        if len(text) < 4:
            await msg.answer("❌ Password minimal 4 karakter.\n\nKetik password:"); return
        state_set(uid, "PASSWORD", text)
        state_set(uid, "STATE", "await_days")
        await msg.answer("Berapa hari masa aktif? (1-365)")
        return

    # ---- Buat akun: days ----
    if state == "await_days":
        if not text.isdigit() or not (1 <= int(text) <= 365):
            await msg.answer("❌ Masukkan angka antara 1 sampai 365.\n\nBerapa hari masa aktif?"); return
        days     = int(text)
        sname    = state_get(uid, "SERVER")
        username = state_get(uid, "USERNAME")
        password = state_get(uid, "PASSWORD")
        tg       = load_tg_server_conf(sname)
        harga    = int(tg["TG_HARGA_HARI"])
        total    = harga * days
        saldo    = saldo_get(uid)

        state_set(uid, "DAYS",  str(days))
        state_set(uid, "STATE", "await_confirm")

        hh = f"Rp{fmt(harga)}/hari" if harga > 0 else "Gratis"
        bw_per_hari   = int(tg.get("TG_BW_PER_HARI","5") or "5")
        bw_total_gb   = days * bw_per_hari
        bw_line = f"\n📶 Kuota      : {bw_total_gb} GB" if bw_per_hari > 0 else ""

        if harga > 0 and saldo < total:
            await msg.answer(
                f"📋 <b>Konfirmasi Pesanan</b>\n━━━━━━━━━━━━━━━━━━━\n"
                f"🌐 Server     : {tg['TG_SERVER_LABEL']}\n"
                f"👤 Username   : <code>{username}</code>\n"
                f"🔑 Password   : <code>{password}</code>\n"
                f"📅 Masa Aktif : {days} hari{bw_line}\n"
                f"💰 Harga      : {hh}\n"
                f"💸 Total      : Rp{fmt(total)}\n"
                f"💳 Saldo kamu : Rp{fmt(saldo)}\n"
                f"❌ Kurang     : Rp{fmt(total - saldo)}\n"
                f"━━━━━━━━━━━━━━━━━━━\nSaldo tidak cukup. Hubungi admin untuk top up.",
                parse_mode="HTML"
            )
            state_clear(uid); return

        saldo_line = f"\n💳 Saldo kamu : Rp{fmt(saldo)}" if harga > 0 else ""
        await msg.answer(
            f"📋 <b>Konfirmasi Pesanan</b>\n━━━━━━━━━━━━━━━━━━━\n"
            f"🌐 Server     : {tg['TG_SERVER_LABEL']}\n"
            f"👤 Username   : <code>{username}</code>\n"
            f"🔑 Password   : <code>{password}</code>\n"
            f"📅 Masa Aktif : {days} hari{bw_line}\n"
            f"💰 Harga      : {hh}\n"
            f"💸 Total      : Rp{fmt(total)}{saldo_line}\n"
            f"━━━━━━━━━━━━━━━━━━━\nLanjutkan?",
            parse_mode="HTML",
            reply_markup=kb_confirm("konfirm")
        )
        return

    # ---- Perpanjang: days ----
    if state == "renew_days":
        if not text.isdigit() or not (1 <= int(text) <= 365):
            await msg.answer("❌ Masukkan angka antara 1 sampai 365.\n\nBerapa hari perpanjang?"); return
        days     = int(text)
        sname    = state_get(uid, "SERVER")
        username = state_get(uid, "USERNAME")
        tg       = load_tg_server_conf(sname)
        harga    = int(tg["TG_HARGA_HARI"])
        total    = harga * days
        saldo    = saldo_get(uid)

        state_set(uid, "DAYS",  str(days))
        state_set(uid, "STATE", "renew_confirm")

        hh = f"Rp{fmt(harga)}/hari" if harga > 0 else "Gratis"
        if harga > 0 and saldo < total:
            await msg.answer(
                f"📋 <b>Konfirmasi Perpanjang</b>\n━━━━━━━━━━━━━━━━━━━\n"
                f"👤 Username  : <code>{username}</code>\n"
                f"📅 Tambah    : {days} hari\n"
                f"💰 Harga     : {hh}\n"
                f"💸 Total     : Rp{fmt(total)}\n"
                f"💳 Saldo     : Rp{fmt(saldo)}\n"
                f"❌ Kurang    : Rp{fmt(total - saldo)}\n"
                f"━━━━━━━━━━━━━━━━━━━\nSaldo tidak cukup. Hubungi admin.",
                parse_mode="HTML"
            )
            state_clear(uid); return

        saldo_line = f"\n💳 Saldo     : Rp{fmt(saldo)}" if harga > 0 else ""
        await msg.answer(
            f"📋 <b>Konfirmasi Perpanjang</b>\n━━━━━━━━━━━━━━━━━━━\n"
            f"👤 Username  : <code>{username}</code>\n"
            f"🌐 Server    : {tg['TG_SERVER_LABEL']}\n"
            f"📅 Tambah    : {days} hari\n"
            f"💰 Harga     : {hh}\n"
            f"💸 Total     : Rp{fmt(total)}{saldo_line}\n"
            f"━━━━━━━━━━━━━━━━━━━\nLanjutkan?",
            parse_mode="HTML",
            reply_markup=kb_confirm("konfirm_renew")
        )
        return

# ============================================================
# Broadcast helper
# ============================================================
async def do_broadcast(msg: Message, text: str):
    _bot    = msg.bot
    sender  = msg.from_user.id
    uids: set[int] = set()

    # Kumpulkan dari registered users
    if Path(USERS_DIR).exists():
        for f in Path(USERS_DIR).glob("*.user"):
            try:
                uid_int = int(f.stem)
                uids.add(uid_int)
            except Exception:
                pass

    # Kumpulkan dari akun SSH (siapa tau ada user yg punya akun tapi belum /start)
    if Path(ACCOUNT_DIR).exists():
        for f in Path(ACCOUNT_DIR).glob("*.conf"):
            ac = load_account_conf(f.stem)
            tg_uid = ac.get("TG_USER_ID","").strip()
            if tg_uid.isdigit():
                uids.add(int(tg_uid))

    # Skip admin pengirim — dia sudah tau isi pesannya
    uids.discard(sender)

    if not uids:
        await msg.answer("❌ Belum ada user lain yang terdaftar."); return

    await msg.answer(f"⏳ Mengirim ke {len(uids)} user...")
    ok = 0; fail = 0; fail_reasons: list[str] = []

    for target_uid in uids:
        try:
            await _bot.send_message(target_uid, text, parse_mode="HTML")
            ok += 1
        except Exception as e:
            fail += 1
            # Ambil error lengkap termasuk tipe exception
            err_type = type(e).__name__
            err_msg  = str(e) or "(no message)"
            reason   = f"{err_type}: {err_msg}"[:80]
            fail_reasons.append(f"uid {target_uid} → {reason}")
            zv_log(f"BROADCAST FAIL uid={target_uid} type={err_type} err={err_msg}")
        await asyncio.sleep(0.05)

    zv_log(f"BROADCAST DONE total={len(uids)} ok={ok} fail={fail}")

    reason_txt = ""
    if fail_reasons:
        # Tampilkan semua error (max 5) supaya bisa debug
        lines = "\n".join(f"• <code>{r}</code>" for r in fail_reasons[:5])
        reason_txt = f"\n\n🔍 <b>Detail Error:</b>\n{lines}"

    await msg.answer(
        f"📢 <b>Broadcast Selesai</b>\n━━━━━━━━━━━━━━━━━━━\n"
        f"✅ Terkirim : {ok} user\n"
        f"❌ Gagal    : {fail} user\n"
        f"━━━━━━━━━━━━━━━━━━━"
        f"{reason_txt}",
        parse_mode="HTML"
    )

# ============================================================
# Broadcast Stiker helper
# ============================================================
async def do_broadcast_stiker(msg: Message, file_id: str):
    _bot   = msg.bot
    sender = msg.from_user.id
    uids: set[int] = set()

    if Path(USERS_DIR).exists():
        for f in Path(USERS_DIR).glob("*.user"):
            try: uids.add(int(f.stem))
            except: pass
    if Path(ACCOUNT_DIR).exists():
        for f in Path(ACCOUNT_DIR).glob("*.conf"):
            ac = load_account_conf(f.stem)
            tid = ac.get("TG_USER_ID","").strip()
            if tid.isdigit(): uids.add(int(tid))

    uids.discard(sender)

    if not uids:
        await msg.answer("❌ Belum ada user lain yang terdaftar."); return

    await msg.answer(f"⏳ Mengirim stiker ke {len(uids)} user...")
    ok = 0; fail = 0; fail_reasons: list[str] = []

    for target_uid in uids:
        try:
            await _bot.send_sticker(target_uid, file_id)
            ok += 1
        except Exception as e:
            fail += 1
            err_type = type(e).__name__
            err_msg  = str(e) or "(no message)"
            fail_reasons.append(f"uid {target_uid} → {err_type}: {err_msg[:50]}")
            zv_log(f"BROADCAST_STIKER FAIL uid={target_uid} err={e}")
        await asyncio.sleep(0.05)

    zv_log(f"BROADCAST_STIKER DONE total={len(uids)} ok={ok} fail={fail}")
    reason_txt = ""
    if fail_reasons:
        lines = "\n".join(f"• <code>{r}</code>" for r in fail_reasons[:5])
        reason_txt = f"\n\n🔍 <b>Detail Error:</b>\n{lines}"

    await msg.answer(
        f"🎭 <b>Broadcast Stiker Selesai</b>\n━━━━━━━━━━━━━━━━━━━\n"
        f"✅ Terkirim : {ok} user\n"
        f"❌ Gagal    : {fail} user\n"
        f"━━━━━━━━━━━━━━━━━━━"
        f"{reason_txt}",
        parse_mode="HTML"
    )

# ============================================================
# Admin: Hapus Akun helper
# ============================================================
async def do_hapus_akun(msg: Message, username: str, admin_uid: int):
    conf_file = f"{ACCOUNT_DIR}/{username}.conf"
    if not os.path.exists(conf_file):
        await msg.answer(f"❌ Akun <code>{username}</code> tidak ditemukan.",
                         parse_mode="HTML",
                         reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
                             InlineKeyboardButton(text="🗑️ Coba Lagi", callback_data="adm_hapus_akun"),
                             InlineKeyboardButton(text="↩ Admin Panel", callback_data="m_admin")
                         ]])); return

    ac = load_account_conf(username)
    tg_uid = ac.get("TG_USER_ID","").strip()
    sname  = ac.get("SERVER","")

    sconf = load_server_conf(sname)
    lip   = local_ip()
    srv_ip = sconf.get("IP","").strip()

    if srv_ip == lip or not srv_ip:
        subprocess.run(["pkill", "-u", username], capture_output=True)
        subprocess.run(["userdel", "-r", username], capture_output=True)
        subprocess.run(["/bin/bash", "-c",
            f"source /etc/zv-manager/core/bandwidth.sh && _bw_cleanup_user {username}"],
            capture_output=True)
    else:
        subprocess.run(
            ["sshpass", "-p", sconf.get("PASS",""),
             "ssh", "-o", "StrictHostKeyChecking=no",
             "-o", "ConnectTimeout=10", "-o", "BatchMode=no",
             "-p", sconf.get("PORT","22"),
             f"{sconf.get('USER','')}@{srv_ip}",
             f"zv-agent delete {username}"],
            capture_output=True, timeout=15
        )

    os.remove(conf_file)
    for extra in [f"{NOTIFY_DIR}/{username}.notified",
                  f"{NOTIFY_DIR}/{username}.bw_warn"]:
        try: os.remove(extra)
        except Exception: pass

    zv_log(f"ADM_HAPUS: admin={admin_uid} username={username}")
    backup_realtime(username, "delete")
    await msg.answer(
        f"✅ <b>Akun Berhasil Dihapus</b>\n━━━━━━━━━━━━━━━━━━━\n"
        f"🗑️ Username : <code>{username}</code>\n"
        f"🌐 Server   : {sname}\n"
        f"━━━━━━━━━━━━━━━━━━━",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
            InlineKeyboardButton(text="🗑️ Hapus Lagi", callback_data="adm_hapus_akun"),
            InlineKeyboardButton(text="↩ Admin Panel", callback_data="m_admin")
        ]])
    )
    if tg_uid and tg_uid.isdigit():
        try:
            await bot.send_message(int(tg_uid),
                f"⚠️ <b>Akun Kamu Dihapus</b>\n━━━━━━━━━━━━━━━━━━━\n"
                f"🗑️ Username : <code>{username}</code>\n"
                f"━━━━━━━━━━━━━━━━━━━\nHubungi admin untuk informasi lebih lanjut.",
                parse_mode="HTML", reply_markup=kb_home_btn())
        except Exception: pass

# ============================================================
# Admin: Cek User helper
# ============================================================
async def do_cek_user(msg: Message, target_uid: int):
    saldo  = saldo_get(target_uid)
    t_info = load_user_info(target_uid)
    name   = t_info.get("NAME", "(tidak terdaftar)")
    joined = t_info.get("JOINED", "-")

    now_ts = int(time.time())
    akun_info = ""
    akun_count = 0
    if Path(ACCOUNT_DIR).exists():
        for f in Path(ACCOUNT_DIR).glob("*.conf"):
            ac = load_account_conf(f.stem)
            if str(ac.get("TG_USER_ID","")).strip() != str(target_uid):
                continue
            uname    = ac.get("USERNAME","")
            is_trial = ac.get("IS_TRIAL","0") == "1"
            exp_ts_r = ac.get("EXPIRED_TS","0")
            tipe     = "Trial" if is_trial else "Premium"
            if exp_ts_r.isdigit() and int(exp_ts_r) > now_ts:
                status = "✅ Aktif"
            else:
                status = "❌ Expired"
            akun_info += f"   • <code>{uname}</code> ({tipe}) {status}\n"
            akun_count += 1

    if not akun_info:
        akun_info = "   Tidak ada akun\n"

    await msg.answer(
        f"🔍 <b>Info User</b>\n━━━━━━━━━━━━━━━━━━━\n"
        f"🆔 User ID  : <code>{target_uid}</code>\n"
        f"👤 Nama     : {name}\n"
        f"📅 Bergabung: {joined[:10]}\n"
        f"💰 Saldo    : Rp{fmt(saldo)}\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"🖥️ Akun SSH ({akun_count}):\n{akun_info}"
        f"━━━━━━━━━━━━━━━━━━━",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
            InlineKeyboardButton(text="💰 Top Up Saldo", callback_data="adm_topup"),
            InlineKeyboardButton(text="↩ Admin Panel",  callback_data="m_admin")
        ]])
    )

# ============================================================
# Main
# ============================================================
async def main():
    global TG, TOKEN, ADMIN_ID, bot
    TG       = load_tg_conf()
    TOKEN    = TG.get("TG_TOKEN","")
    ADMIN_ID = int(TG.get("TG_ADMIN_ID","0"))

    if not TOKEN:
        log.error("TG_TOKEN tidak ditemukan di telegram.conf!")
        return

    bot = Bot(token=TOKEN)
    log.info(f"ZV-Manager Bot starting... Admin: {ADMIN_ID}")
    # drop_pending_updates: buang update lama saat restart (biar ga replay)
    await dp.start_polling(
        bot,
        allowed_updates=["message", "callback_query"],
        drop_pending_updates=True,
    )

if __name__ == "__main__":
    asyncio.run(main())
