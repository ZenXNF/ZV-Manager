#!/usr/bin/env python3
# ============================================================
#   ZV-Manager Bot - User Handlers
#   /start, home, buat akun, trial, akun saya,
#   perpanjang, tambah bandwidth, riwayat, konfirmasi
# ============================================================

import asyncio
import os
import random
import re
import string
import subprocess
import time
from datetime import datetime
from pathlib import Path

from aiogram import F, Router
from aiogram.filters import Command
from aiogram.types import (
    CallbackQuery, InlineKeyboardButton,
    InlineKeyboardMarkup, Message
)
from aiogram.utils.keyboard import InlineKeyboardBuilder

from config import ACCOUNT_DIR, ADMIN_ID, NOTIFY_DIR, VMESS_DIR, log
from keyboards import (
    kb_after_buy, kb_back, kb_confirm, kb_for_user, kb_home_btn,
    kb_server_list, kb_vmess_server_list
)
from middleware import _throttle
from storage import (
    already_trial, already_trial_vmess, count_ssh_accounts, count_vmess_accounts, invalidate_account_cache,
    load_account_conf, load_server_conf, load_tg_server_conf, load_vmess_conf, local_ip,
    mark_trial, mark_trial_vmess, register_user,
    saldo_deduct, saldo_get, save_account_conf, save_vmess_conf,
    state_clear, state_get, state_set
)
from texts import text_akun_info, text_home, text_server_list, text_vmess_info, vmess_build_urls

# ── VMess remote agent helper (async, non-blocking) ──────────
async def _vmess_agent(sname: str, *args) -> str:
    """Panggil zv-vmess-agent di server lokal/remote (async, tidak block event loop)."""
    local_ip_str = local_ip()
    sconf = load_server_conf(sname) or {}
    srv_ip = sconf.get("IP", "")
    cmd_args = " ".join(str(a) for a in args)

    if srv_ip == local_ip_str or not srv_ip:
        cmd = f"zv-vmess-agent {cmd_args}"
        timeout_sec = 15
    else:
        cmd = f"source /etc/zv-manager/utils/remote.sh && remote_vmess_agent {sname} {cmd_args}"
        timeout_sec = 30

    try:
        proc = await asyncio.create_subprocess_shell(
            cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            executable="/bin/bash"
        )
        stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=timeout_sec)
        return stdout.decode().strip()
    except asyncio.TimeoutError:
        try: proc.kill()
        except Exception: pass
        return "AGENT-ERR|Timeout"
    except Exception as e:
        return f"AGENT-ERR|{e}"


from utils import backup_realtime, backup_realtime_vmess, fmt, fmt_bytes, tail_log, ts_to_wib, zv_log

router = Router()


# ── Notify admin helper ───────────────────────────────────────
async def notify_admin(bot, tipe: str, fname: str, uid: int,
                       username: str, sname: str, days_or_gb, total: int):
    if not ADMIN_ID or uid == ADMIN_ID:
        return
    icons  = {"BELI": "🛒", "RENEW": "🔄", "BW": "📶"}
    labels = {"BELI": "Pembelian Baru", "RENEW": "Perpanjang Akun", "BW": "Tambah Bandwidth"}
    icon   = icons.get(tipe, "💡")
    label  = labels.get(tipe, "Transaksi")
    extra  = f"\n📶 Tambah   : {days_or_gb} GB" if tipe == "BW" else f"\n📅 Durasi   : {days_or_gb} hari"
    text   = (
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


# ── /start ───────────────────────────────────────────────────
@router.message(Command("start"))
async def cmd_start(msg: Message):
    uid   = msg.from_user.id
    fname = msg.from_user.first_name or "User"
    state_clear(uid)
    register_user(uid, fname)
    await msg.answer(text_home(fname, uid), parse_mode="HTML",
                     reply_markup=kb_for_user(uid))


# ── /testbroadcast (admin debug) ─────────────────────────────
@router.message(Command("testbroadcast"))
async def cmd_testbroadcast(msg: Message):
    uid = msg.from_user.id
    if uid != ADMIN_ID:
        await msg.answer("❌ Admin only."); return
    try:
        await msg.bot.send_message(uid, "✅ Bot bisa kirim pesan ke kamu!", parse_mode="HTML")
        uids: set[int] = set()
        if Path(ACCOUNT_DIR).exists():
            for f in Path(ACCOUNT_DIR).glob("*.conf"):
                ac  = load_account_conf(f.stem)
                tid = ac.get("TG_USER_ID", "").strip()
                if tid.isdigit():
                    uids.add(int(tid))
        uids.discard(uid)
        await msg.answer(
            f"🔍 <b>Debug Broadcast</b>\n"
            f"━━━━━━━━━━━━━━━━━━━\n"
            f"✅ Bot OK kirim ke admin\n"
            f"👥 User lain: {len(uids)}\n"
            f"IDs contoh: {str(list(uids)[:5])}\n"
            f"━━━━━━━━━━━━━━━━━━━",
            parse_mode="HTML"
        )
    except Exception as e:
        await msg.answer(f"❌ Error: {e}")


# ── home ─────────────────────────────────────────────────────
@router.callback_query(F.data == "home")
async def cb_home(cb: CallbackQuery):
    uid   = cb.from_user.id
    fname = cb.from_user.first_name or "User"
    if not _throttle(uid):
        await cb.answer("⏳"); return
    state_clear(uid)
    await cb.message.edit_text(text_home(fname, uid), parse_mode="HTML",
                                reply_markup=kb_for_user(uid))
    await cb.answer()


# ── Buat Akun & Trial ─────────────────────────────────────────
@router.callback_query(F.data == "m_buat")
async def cb_menu_buat(cb: CallbackQuery):
    await cb.message.edit_text(
        "⚡ <b>Buat Akun</b>\n\nPilih protokol:", parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[
            [InlineKeyboardButton(text="🔑 SSH",   callback_data="proto_buat_ssh"),
             InlineKeyboardButton(text="⚡ VMESS", callback_data="proto_buat_vmess")],
            [InlineKeyboardButton(text="↩ Kembali",    callback_data="home")]
        ]))
    await cb.answer()

@router.callback_query(F.data == "m_trial")
async def cb_menu_trial(cb: CallbackQuery):
    await cb.message.edit_text(
        "🎁 <b>Coba Gratis</b>\n\nPilih protokol:", parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[
            [InlineKeyboardButton(text="🔑 SSH",   callback_data="proto_trial_ssh"),
             InlineKeyboardButton(text="⚡ VMESS", callback_data="proto_trial_vmess")],
            [InlineKeyboardButton(text="↩ Kembali",    callback_data="home")]
        ]))
    await cb.answer()

@router.callback_query(F.data == "proto_buat_ssh")
async def cb_proto_buat_ssh(cb: CallbackQuery):
    if not load_server_list_safe():
        await cb.message.edit_text("❌ Belum ada server."); await cb.answer(); return
    await cb.message.edit_text(text_server_list("Buat Akun SSH"), parse_mode="HTML",
                                reply_markup=kb_server_list("s_buat", back_cb="m_buat"))
    await cb.answer()

@router.callback_query(F.data == "proto_trial_ssh")
async def cb_proto_trial_ssh(cb: CallbackQuery):
    if not load_server_list_safe():
        await cb.message.edit_text("❌ Belum ada server."); await cb.answer(); return
    await cb.message.edit_text(text_server_list("Trial SSH Gratis"), parse_mode="HTML",
                                reply_markup=kb_server_list("s_trial", back_cb="m_trial"))
    await cb.answer()

# ── VMess — pilih server ──────────────────────────────────────
@router.callback_query(F.data == "proto_buat_vmess")
async def cb_proto_buat_vmess(cb: CallbackQuery):
    from storage import get_server_list_by_type
    if not get_server_list_by_type("vmess"):
        await cb.message.edit_text("❌ Belum ada server VMess tersedia.", reply_markup=kb_back("m_buat"))
        await cb.answer(); return
    await cb.message.edit_text(text_server_list("Buat Akun VMess", proto="vmess"), parse_mode="HTML",
                                reply_markup=kb_vmess_server_list("vs_buat", back_cb="m_buat"))
    await cb.answer()

@router.callback_query(F.data == "proto_trial_vmess")
async def cb_proto_trial_vmess(cb: CallbackQuery):
    from storage import get_server_list_by_type
    if not get_server_list_by_type("vmess"):
        await cb.message.edit_text("❌ Belum ada server VMess tersedia.", reply_markup=kb_back("m_trial"))
        await cb.answer(); return
    await cb.message.edit_text(text_server_list("Trial VMess Gratis", proto="vmess"), parse_mode="HTML",
                                reply_markup=kb_vmess_server_list("vs_trial", back_cb="m_trial"))
    await cb.answer()

# Pagination VMess
@router.callback_query(F.data.startswith("vpage_"))
async def cb_vpage(cb: CallbackQuery):
    parts  = cb.data.split("_")
    page   = int(parts[-1])
    prefix = "_".join(parts[1:-1])
    title  = "Buat Akun VMess" if prefix == "vs_buat" else "Trial VMess Gratis"
    await cb.message.edit_text(text_server_list(title), parse_mode="HTML",
                                reply_markup=kb_vmess_server_list(prefix, page))
    await cb.answer()

# ── Pilih server VMess → Trial ────────────────────────────────
@router.callback_query(F.data.startswith("vs_trial_"))
async def cb_vs_trial(cb: CallbackQuery):
    sname = cb.data[len("vs_trial_"):]
    uid   = cb.from_user.id
    await cb.answer()

    if already_trial_vmess(uid, sname):
        await cb.message.answer(
            "⚠️ Kamu sudah trial VMess di server ini dalam 24 jam terakhir.\n"
            "Coba server lain atau tunggu 24 jam."
        ); return

    from pathlib import Path as P
    import uuid as _uuid, subprocess as _sp
    sconf = load_server_conf(sname)
    if not sconf:
        await cb.message.answer("❌ Server tidak ditemukan."); return

    tg     = load_tg_server_conf(sname)
    ip     = sconf.get("IP", "")
    if not ip: ip = local_ip()
    domain = sconf.get("DOMAIN") or ip

    if count_vmess_accounts(ip) >= int(tg.get("TG_MAX_AKUN_VMESS","500")):
        await cb.message.answer(
            f"❌ Server <b>{tg['TG_SERVER_LABEL']}</b> penuh.", parse_mode="HTML"
        ); return

    suffix   = "".join(random.choices(string.digits, k=4))
    username = f"VTrial{suffix}"
    new_uuid = str(_uuid.uuid4())
    now_ts   = int(time.time())
    exp_ts   = now_ts + 1800  # 30 menit
    exp_date = datetime.fromtimestamp(exp_ts).strftime("%Y-%m-%d")
    exp_disp = ts_to_wib(exp_ts)

    # Simpan conf di brain server (untuk tracking)
    save_vmess_conf(username, {
        "USERNAME":     username,
        "UUID":         new_uuid,
        "DOMAIN":       domain,
        "EXPIRED_TS":   str(exp_ts),
        "EXPIRED_DATE": exp_date,
        "CREATED":      datetime.now().strftime("%Y-%m-%d"),
        "IS_TRIAL":     "1",
        "TG_USER_ID":   str(uid),
        "SERVER":       sname,
    })
    # Tambah ke Xray via agent (lokal/remote)
    await _vmess_agent(sname, "add", username, new_uuid, "1", "0", uid)

    invalidate_account_cache(ip or local_ip(), "vmess")
    mark_trial_vmess(uid, sname)
    zv_log(f"VMESS_TRIAL: {uid} server={sname} user={username}")
    await _send_vmess_info(cb.message, "TRIAL", username, new_uuid, domain, exp_disp,
                           tg["TG_SERVER_LABEL"], isp=sconf.get("ISP",""))


async def _send_vmess_info(msg, tipe: str, username: str, uuid: str, domain: str,
                            exp_disp: str, server_label: str,
                            days: int = 0, total: int = 0, isp: str = ""):
    """Kirim info VMess: 1 pesan lengkap dengan URL bisa di-tap untuk salin."""
    await msg.answer(
        text_vmess_info(tipe, username, uuid, domain, exp_disp, server_label,
                        days, total, isp=isp),
        parse_mode="HTML",
        reply_markup=kb_after_buy("vmess")
    )

# ── Pilih server VMess → Buat (input durasi) ──────────────────
@router.callback_query(F.data.startswith("vs_buat_"))
async def cb_vs_buat(cb: CallbackQuery):
    sname = cb.data[len("vs_buat_"):]
    uid   = cb.from_user.id
    fname = cb.from_user.first_name or "User"
    sconf = load_server_conf(sname)
    if not sconf:
        await cb.answer("❌ Server tidak ditemukan"); return
    tg    = load_tg_server_conf(sname)
    ip_vs = sconf.get("IP", "")
    if count_vmess_accounts(ip_vs) >= int(tg.get("TG_MAX_AKUN_VMESS","500")):
        await cb.answer("❌ Server penuh!"); return
    harga = int(tg.get("TG_HARGA_VMESS_HARI","0") or tg.get("TG_HARGA_HARI","0"))
    hh    = f"Rp{fmt(harga)}/hari" if harga > 0 else "Gratis"
    await cb.answer()
    state_clear(uid)
    state_set(uid, "STATE",  "vmess_await_username")
    state_set(uid, "SERVER", sname)
    state_set(uid, "FNAME",  fname)
    await cb.message.answer(
        f"⚡ <b>Buat Akun VMess</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"🌐 Server  : <b>{tg['TG_SERVER_LABEL']}</b>\n"
        f"💰 Harga   : {hh}\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"Ketik username VMess kamu:\n"
        f"• 4–16 karakter, huruf kecil/angka/strip (-)\n"
        f"• Contoh: <code>budi-vip</code>",
        parse_mode="HTML", reply_markup=kb_back("home")
    )

# ── Konfirmasi buat akun VMess ────────────────────────────────
@router.callback_query(F.data == "konfirm_vmess")
async def cb_konfirm_vmess(cb: CallbackQuery):
    uid = cb.from_user.id
    if state_get(uid, "STATE") != "vmess_confirm":
        await cb.answer("⚠️ Sesi habis, mulai ulang"); state_clear(uid); return
    await cb.answer("⏳ Membuat akun VMess...")

    import uuid as _uuid, subprocess as _sp
    sname  = state_get(uid, "SERVER")
    days   = int(state_get(uid, "DAYS") or "1")
    fname  = state_get(uid, "FNAME")
    sconf  = load_server_conf(sname)
    tg     = load_tg_server_conf(sname)
    domain = sconf.get("DOMAIN") or sconf.get("IP","")
    harga  = int(tg.get("TG_HARGA_VMESS_HARI","0") or tg.get("TG_HARGA_HARI","0"))
    total  = harga * days

    if harga > 0 and total > 0:
        if not saldo_deduct(uid, total):
            await cb.message.edit_text("❌ Saldo tidak cukup."); state_clear(uid); return

    # Pakai username custom dari state, fallback ke random
    username = state_get(uid, "USERNAME_VMESS") or                "vmess-" + "".join(random.choices(string.ascii_lowercase + string.digits, k=6))
    new_uuid = str(_uuid.uuid4())
    now_ts   = int(time.time())
    exp_ts   = now_ts + days * 86400
    exp_date = datetime.fromtimestamp(exp_ts).strftime("%Y-%m-%d")
    exp_disp = ts_to_wib(exp_ts)

    bw_per_hari = int(tg.get("TG_BW_PER_HARI_VMESS","0") or "0")
    bw_limit    = bw_per_hari * days

    # Simpan conf di brain server (untuk tracking)
    save_vmess_conf(username, {
        "USERNAME":     username,
        "UUID":         new_uuid,
        "DOMAIN":       domain,
        "EXPIRED_TS":   str(exp_ts),
        "EXPIRED_DATE": exp_date,
        "CREATED":      datetime.now().strftime("%Y-%m-%d"),
        "IS_TRIAL":     "0",
        "TG_USER_ID":   str(uid),
        "SERVER":       sname,
        "BW_LIMIT_GB":  str(bw_limit),
        "BW_USED_BYTES":"0",
        "BW_LAST_CHECK":"0",
    })
    # Tambah ke Xray via agent (lokal/remote)
    await _vmess_agent(sname, "add", username, new_uuid, days, bw_limit, uid)

    state_clear(uid)
    zv_log(f"VMESS_BELI: {uid} server={sname} user={username} days={days} total={total}")
    invalidate_account_cache(sconf.get("IP","") or local_ip(), "vmess")
    backup_realtime_vmess(username, "create")
    if ADMIN_ID and uid != ADMIN_ID:
        try:
            await cb.bot.send_message(ADMIN_ID,
                f"⚡ <b>Pembelian VMess</b>\n"
                f"━━━━━━━━━━━━━━━━━━━\n"
                f"👤 User   : {fname} (<code>{uid}</code>)\n"
                f"🖥️ Akun   : <code>{username}</code>\n"
                f"🌐 Server : {tg['TG_SERVER_LABEL']}\n"
                f"📅 Durasi : {days} hari\n"
                f"💸 Total  : Rp{fmt(total)}\n"
                f"━━━━━━━━━━━━━━━━━━━",
                parse_mode="HTML")
        except Exception: pass

    await cb.message.edit_text("✅ Akun VMess sedang dibuat...")
    await _send_vmess_info(cb.message, "BELI", username, new_uuid, domain, exp_disp,
                           tg["TG_SERVER_LABEL"], days, total, isp=sconf.get("ISP",""))

def load_server_list_safe() -> bool:
    from storage import get_server_list_by_type
    return bool(get_server_list_by_type("ssh"))

# Pagination
@router.callback_query(F.data.startswith("page_"))
async def cb_page(cb: CallbackQuery):
    parts  = cb.data.split("_")
    page   = int(parts[-1])
    prefix = "_".join(parts[1:-1])
    title  = "Buat Akun SSH" if prefix == "s_buat" else "Trial SSH Gratis"
    await cb.message.edit_text(text_server_list(title), parse_mode="HTML",
                                reply_markup=kb_server_list(prefix, page))
    await cb.answer()


# ── Pilih server → Buat akun ─────────────────────────────────
@router.callback_query(F.data.startswith("s_buat_"))
async def cb_s_buat(cb: CallbackQuery):
    sname = cb.data[len("s_buat_"):]
    uid   = cb.from_user.id
    fname = cb.from_user.first_name or "User"
    sconf = load_server_conf(sname)
    if not sconf:
        await cb.answer("❌ Server tidak ditemukan"); return
    tg = load_tg_server_conf(sname)
    ip = sconf.get("IP", "")
    if not ip: ip = local_ip()
    if count_ssh_accounts(ip) >= int(tg["TG_MAX_AKUN"]):
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


# ── Pilih server → Trial ──────────────────────────────────────
@router.callback_query(F.data.startswith("s_trial_"))
async def cb_s_trial(cb: CallbackQuery):
    sname = cb.data[len("s_trial_"):]
    uid   = cb.from_user.id
    await cb.answer()

    if already_trial(uid, sname):
        await cb.message.answer(
            "⚠️ Kamu sudah trial di server ini dalam 24 jam terakhir.\n"
            "Coba server lain atau tunggu 24 jam."
        ); return

    sconf = load_server_conf(sname)
    if not sconf:
        await cb.message.answer("❌ Server tidak ditemukan."); return

    tg     = load_tg_server_conf(sname)
    ip     = sconf.get("IP", "")
    lip    = local_ip()
    if not ip: ip = lip
    domain = sconf.get("DOMAIN") or ip

    if count_ssh_accounts(ip) >= int(tg["TG_MAX_AKUN"]):
        await cb.message.answer(
            f"❌ Server <b>{tg['TG_SERVER_LABEL']}</b> penuh.", parse_mode="HTML"
        ); return

    suffix   = "".join(random.choices(string.digits, k=4))
    username = f"Trial{suffix}"
    password = "ZenXNF"
    now_ts   = int(time.time())
    exp_ts   = now_ts + 1800
    exp_display = ts_to_wib(exp_ts)
    exp_date    = datetime.fromtimestamp(exp_ts).strftime("%Y-%m-%d")

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
            ["sshpass", "-p", sconf.get("PASS", ""),
             "ssh", "-o", "StrictHostKeyChecking=no",
             "-o", "ConnectTimeout=10", "-o", "BatchMode=no",
             "-p", sconf.get("PORT", "22"),
             f"{sconf.get('USER', '')}@{ip}",
             f"zv-agent add {username} {password} {tg['TG_LIMIT_IP']} 1"],
            capture_output=True, text=True, timeout=15
        )
        if not result.stdout.startswith("ADD-OK"):
            await cb.message.answer("❌ Gagal membuat akun trial."); return

    invalidate_account_cache(ip, "ssh")
    mark_trial(uid, sname)
    zv_log(f"TRIAL: {uid} server={sname} user={username}")
    await cb.message.answer(
        text_akun_info("TRIAL", username, password, domain,
                       exp_display, tg["TG_LIMIT_IP"], tg["TG_SERVER_LABEL"], isp=sconf.get("ISP","")),
        parse_mode="HTML", reply_markup=kb_after_buy("ssh")
    )


# ── Akun Saya — helpers ───────────────────────────────────────
_AKUN_PAGE_SIZE = 5

def _status_label(exp_ts_raw: str, now_ts: int):
    if exp_ts_raw and exp_ts_raw.isdigit():
        exp_ts = int(exp_ts_raw)
        sisa   = exp_ts - now_ts
        disp   = ts_to_wib(exp_ts)
        if sisa <= 0:
            return disp, "❌ Expired", "Sudah habis"
        elif sisa < 3600:
            return disp, "⚠️ Aktif", "&lt; 1 jam lagi"
        elif sisa < 86400:
            return disp, "⚠️ Aktif", f"{sisa//3600} jam lagi"
        else:
            return disp, "✅ Aktif", f"{sisa//86400} hari lagi"
    return "-", "✅ Aktif", "-"

def _collect_ssh_akun(uid: int) -> list:
    items = []
    now_ts = int(time.time())
    try:
        for f in sorted(Path(ACCOUNT_DIR).glob("*.conf")):
            ac = load_account_conf(f.stem)
            if str(ac.get("TG_USER_ID", "")).strip() != str(uid): continue
            if not ac.get("USERNAME"): continue
            # Skip akun expired — sudah tidak relevan untuk user
            exp_ts = ac.get("EXPIRED_TS", "")
            if exp_ts and str(exp_ts).strip().isdigit() and int(exp_ts) < now_ts:
                continue
            items.append(ac)
    except Exception: pass
    return items

def _collect_vmess_akun(uid: int) -> list:
    items = []
    now_ts = int(time.time())
    try:
        if Path(VMESS_DIR).exists():
            for vf in sorted(Path(VMESS_DIR).glob("*.conf")):
                vc = load_vmess_conf(vf.stem)
                if str(vc.get("TG_USER_ID", "")).strip() != str(uid): continue
                if not vc.get("USERNAME"): continue
                # Skip akun expired — sudah tidak relevan untuk user
                exp_ts = vc.get("EXPIRED_TS", "")
                if exp_ts and str(exp_ts).strip().isdigit() and int(exp_ts) < now_ts:
                    continue
                items.append(vc)
    except Exception: pass
    return items

def _render_ssh_page(items: list, page: int, now_ts: int, uid: int) -> tuple[str, InlineKeyboardMarkup]:
    total    = len(items)
    n_pages  = max(1, (total + _AKUN_PAGE_SIZE - 1) // _AKUN_PAGE_SIZE)
    page     = max(0, min(page, n_pages - 1))
    chunk    = items[page * _AKUN_PAGE_SIZE:(page + 1) * _AKUN_PAGE_SIZE]

    out = f"🔑 <b>Akun SSH Kamu</b>  ({total} akun)\n━━━━━━━━━━━━━━━━━━━\n"
    if not chunk:
        out += "\nBelum ada akun SSH."
    for ac in chunk:
        uname   = ac.get("USERNAME", "")
        passwd  = ac.get("PASSWORD", "")
        sname   = ac.get("SERVER", "")
        sc      = load_server_conf(sname)
        domain  = sc.get("DOMAIN") or sc.get("IP") or ac.get("DOMAIN", "")
        if not domain:
            try: domain = open("/etc/zv-manager/domain").read().strip()
            except Exception: pass
        tipe    = "Trial" if ac.get("IS_TRIAL","0") == "1" else "Premium"
        exp_d, status, sisa_l = _status_label(ac.get("EXPIRED_TS",""), now_ts)
        limit   = int(ac.get("LIMIT", "2") or "2")
        ip_now  = int(open(f"/tmp/zv-bw/{uname}.count").read().strip()
                      if __import__("os").path.exists(f"/tmp/zv-bw/{uname}.count") else "0")
        ip_warn = " ⚠️ Penuh!" if ip_now >= limit else ""
        out += (
            f"\n👤 <b>{uname}</b> <i>({tipe})</i>\n"
            f"🌐 Host    : <code>{domain}</code>\n"
            f"🔑 Pass    : <code>{passwd}</code>\n"
            f"⏳ Expired : {exp_d}\n"
            f"📊 Status  : {status} · {sisa_l}\n"
            f"📡 IP      : {ip_now}/{limit}{ip_warn}\n"
            f"━━━━━━━━━━━━━━━━━━━"
        )

    # Cek apakah user punya akun premium SSH aktif untuk perpanjang/bw
    # (expired sudah difilter di _collect_ssh_akun, jadi semua items = aktif)
    has_premium = any(
        ac.get("IS_TRIAL","0") != "1"
        for ac in items
    )

    b = InlineKeyboardBuilder()
    nav = []
    if page > 0:
        nav.append(InlineKeyboardButton(text="◀ Sebelumnya", callback_data=f"akun_ssh_{page-1}"))
    if page < n_pages - 1:
        nav.append(InlineKeyboardButton(text="Berikutnya ▶", callback_data=f"akun_ssh_{page+1}"))
    if nav: b.row(*nav)
    if has_premium:
        b.row(
            InlineKeyboardButton(text="🔄 Perpanjang", callback_data="m_perpanjang_ssh"),
            InlineKeyboardButton(text="📶 Bandwidth",  callback_data="m_tambah_bw_ssh")
        )
    b.row(InlineKeyboardButton(text="📨 Kirim Ulang Info", callback_data="kirim_ulang_ssh"))
    b.row(InlineKeyboardButton(text="🏠 Menu", callback_data="home"))
    return out, b.as_markup()

def _render_vmess_page(items: list, page: int, now_ts: int, uid: int) -> tuple[str, InlineKeyboardMarkup]:
    total    = len(items)
    n_pages  = max(1, (total + _AKUN_PAGE_SIZE - 1) // _AKUN_PAGE_SIZE)
    page     = max(0, min(page, n_pages - 1))
    chunk    = items[page * _AKUN_PAGE_SIZE:(page + 1) * _AKUN_PAGE_SIZE]

    out = f"⚡ <b>Akun VMess Kamu</b>  ({total} akun)\n━━━━━━━━━━━━━━━━━━━\n"
    if not chunk:
        out += "\nBelum ada akun VMess."
    for vc in chunk:
        vuname   = vc.get("USERNAME","")
        vuuid    = vc.get("UUID","")
        vsname   = vc.get("SERVER","")
        vtg      = load_tg_server_conf(vsname) if vsname else {}
        slabel   = vtg.get("TG_SERVER_LABEL","") or vsname or vc.get("DOMAIN","")
        tipe     = "Trial" if vc.get("IS_TRIAL","0") == "1" else "Premium"
        exp_d, status, sisa_l = _status_label(vc.get("EXPIRED_TS",""), now_ts)
        # Ambil IP aktif VMess dari online JSON
        import json as _json, os as _os
        _online_f = f"/var/www/zv-manager/api/online-{vuname}.json"
        try:
            _od = _json.loads(open(_online_f).read()) if _os.path.exists(_online_f) else {}
            ip_now_v = len(_od.get("ips", [])) if _od.get("ips") else (_od.get("online", 0))
        except Exception:
            ip_now_v = 0
        vlimit = int(load_tg_server_conf(vsname).get("TG_LIMIT_IP_VMESS", "2") if vsname else "2")
        vip_warn = " ⚠️ Penuh!" if ip_now_v >= vlimit else ""
        out += (
            f"\n⚡ <b>{vuname}</b> <i>({tipe})</i>\n"
            f"🌐 Server   : {slabel}\n"
            f"🔑 UUID     : <code>{vuuid}</code>\n"
            f"⏳ Expired  : {exp_d} · {sisa_l}\n"
            f"📊 Status   : {status}\n"
            f"📡 IP       : {ip_now_v}/{vlimit}{vip_warn}\n"
            f"━━━━━━━━━━━━━━━━━━━"
        )

    # Cek apakah user punya akun premium VMess aktif untuk perpanjang
    # (expired sudah difilter di _collect_vmess_akun, jadi semua items = aktif)
    has_premium = any(
        vc.get("IS_TRIAL","0") != "1"
        for vc in items
    )

    b = InlineKeyboardBuilder()
    nav = []
    if page > 0:
        nav.append(InlineKeyboardButton(text="◀ Sebelumnya", callback_data=f"akun_vmess_{page-1}"))
    if page < n_pages - 1:
        nav.append(InlineKeyboardButton(text="Berikutnya ▶", callback_data=f"akun_vmess_{page+1}"))
    if nav: b.row(*nav)
    if has_premium:
        b.row(
            InlineKeyboardButton(text="🔄 Perpanjang", callback_data="m_perpanjang_vmess"),
            InlineKeyboardButton(text="📶 Bandwidth",  callback_data="m_tambah_bw_vmess")
        )
    b.row(InlineKeyboardButton(text="📨 Kirim Ulang Info", callback_data="kirim_ulang_vmess"))
    b.row(InlineKeyboardButton(text="🏠 Menu", callback_data="home"))
    return out, b.as_markup()


# ── Akun Saya — entry point (pilih protokol) ──────────────────
@router.callback_query(F.data == "m_akun")
async def cb_akun_saya(cb: CallbackQuery):
    uid    = cb.from_user.id
    await cb.answer()
    n_ssh   = len(_collect_ssh_akun(uid))
    n_vmess = len(_collect_vmess_akun(uid))
    await cb.message.edit_text(
        f"📋 <b>Akun Kamu</b>\n━━━━━━━━━━━━━━━━━━━\n"
        f"🔑 SSH    : {n_ssh} akun\n"
        f"⚡ VMess  : {n_vmess} akun\n"
        f"━━━━━━━━━━━━━━━━━━━\nPilih protokol:",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[
            [InlineKeyboardButton(text=f"🔑 SSH ({n_ssh})",   callback_data="akun_proto_ssh"),
             InlineKeyboardButton(text=f"⚡ VMess ({n_vmess})", callback_data="akun_proto_vmess")],
            [InlineKeyboardButton(text="🏠 Menu Utama", callback_data="home")]
        ])
    )

@router.callback_query(F.data == "akun_proto_ssh")
async def cb_akun_proto_ssh(cb: CallbackQuery):
    uid    = cb.from_user.id
    now_ts = int(time.time())
    await cb.answer()
    items  = _collect_ssh_akun(uid)
    if not items:
        try:
            await cb.message.edit_text(
                "🔑 <b>Akun SSH Kamu</b>\n━━━━━━━━━━━━━━━━━━━\nBelum ada akun SSH.",
                parse_mode="HTML",
                reply_markup=InlineKeyboardMarkup(inline_keyboard=[
                    [InlineKeyboardButton(text="🛒 Beli Akun SSH", callback_data="proto_buat_ssh")],
                    [InlineKeyboardButton(text="↩ Kembali", callback_data="m_akun")]
                ])
            )
        except Exception: pass
        return
    out, kb = _render_ssh_page(items, 0, now_ts, uid)
    try:
        await cb.message.edit_text(out, parse_mode="HTML", reply_markup=kb)
    except Exception: pass

@router.callback_query(F.data == "akun_proto_vmess")
async def cb_akun_proto_vmess(cb: CallbackQuery):
    uid    = cb.from_user.id
    now_ts = int(time.time())
    await cb.answer()
    items  = _collect_vmess_akun(uid)
    if not items:
        try:
            await cb.message.edit_text(
                "⚡ <b>Akun VMess Kamu</b>\n━━━━━━━━━━━━━━━━━━━\nBelum ada akun VMess.",
                parse_mode="HTML",
                reply_markup=InlineKeyboardMarkup(inline_keyboard=[
                    [InlineKeyboardButton(text="🛒 Beli Akun VMess", callback_data="proto_buat_vmess")],
                    [InlineKeyboardButton(text="↩ Kembali", callback_data="m_akun")]
                ])
            )
        except Exception: pass
        return
    out, kb = _render_vmess_page(items, 0, now_ts, uid)
    try:
        await cb.message.edit_text(out, parse_mode="HTML", reply_markup=kb)
    except Exception: pass

@router.callback_query(F.data.startswith("akun_ssh_"))
async def cb_akun_ssh_page(cb: CallbackQuery):
    uid    = cb.from_user.id
    now_ts = int(time.time())
    try:
        page = int(cb.data.split("_")[-1])
    except (ValueError, IndexError):
        await cb.answer(); return
    await cb.answer()
    items  = _collect_ssh_akun(uid)
    out, kb = _render_ssh_page(items, page, now_ts, uid)
    try:
        await cb.message.edit_text(out, parse_mode="HTML", reply_markup=kb)
    except Exception: pass

@router.callback_query(F.data.startswith("akun_vmess_"))
async def cb_akun_vmess_page(cb: CallbackQuery):
    uid    = cb.from_user.id
    now_ts = int(time.time())
    try:
        page = int(cb.data.split("_")[-1])
    except (ValueError, IndexError):
        await cb.answer(); return
    await cb.answer()
    items  = _collect_vmess_akun(uid)
    out, kb = _render_vmess_page(items, page, now_ts, uid)
    try:
        await cb.message.edit_text(out, parse_mode="HTML", reply_markup=kb)
    except Exception: pass


# ── Kirim Ulang — Pilih Username (paginasi 4 per halaman) ────

_KU_PAGE_SIZE = 4

def _ku_ssh_kb(items: list, page: int) -> tuple[str, InlineKeyboardMarkup]:
    """Bangun teks + keyboard pilih username SSH premium untuk kirim ulang."""
    # Filter hanya akun premium (bukan trial)
    premium = [ac for ac in items if ac.get("IS_TRIAL","0") != "1"]
    total   = len(premium)
    n_pages = max(1, (total + _KU_PAGE_SIZE - 1) // _KU_PAGE_SIZE)
    page    = max(0, min(page, n_pages - 1))
    chunk   = premium[page * _KU_PAGE_SIZE:(page + 1) * _KU_PAGE_SIZE]

    text = (
        f"📨 <b>Kirim Ulang Info SSH</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"Pilih akun yang ingin dikirim ulang:\n"
        f"<i>({total} akun · hal. {page+1}/{n_pages})</i>"
    )
    b = InlineKeyboardBuilder()
    for ac in chunk:
        uname = ac.get("USERNAME", "")
        b.row(InlineKeyboardButton(
            text=f"🔑 {uname}",
            callback_data=f"ku_ssh_{uname}"
        ))
    nav = []
    if page > 0:
        nav.append(InlineKeyboardButton(text="◀ Sebelumnya", callback_data=f"ku_ssh_p_{page-1}"))
    if page < n_pages - 1:
        nav.append(InlineKeyboardButton(text="Berikutnya ▶", callback_data=f"ku_ssh_p_{page+1}"))
    if nav: b.row(*nav)
    b.row(InlineKeyboardButton(text="↩ Kembali", callback_data="akun_proto_ssh"))
    return text, b.as_markup()

def _ku_vmess_kb(items: list, page: int) -> tuple[str, InlineKeyboardMarkup]:
    """Bangun teks + keyboard pilih username VMess premium untuk kirim ulang."""
    # Filter hanya akun premium (bukan trial)
    premium = [vc for vc in items if vc.get("IS_TRIAL","0") != "1"]
    total   = len(premium)
    n_pages = max(1, (total + _KU_PAGE_SIZE - 1) // _KU_PAGE_SIZE)
    page    = max(0, min(page, n_pages - 1))
    chunk   = premium[page * _KU_PAGE_SIZE:(page + 1) * _KU_PAGE_SIZE]

    text = (
        f"📨 <b>Kirim Ulang Info VMess</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"Pilih akun yang ingin dikirim ulang:\n"
        f"<i>({total} akun · hal. {page+1}/{n_pages})</i>"
    )
    b = InlineKeyboardBuilder()
    for vc in chunk:
        uname = vc.get("USERNAME", "")
        b.row(InlineKeyboardButton(
            text=f"⚡ {uname}",
            callback_data=f"ku_vmess_{uname}"
        ))
    nav = []
    if page > 0:
        nav.append(InlineKeyboardButton(text="◀ Sebelumnya", callback_data=f"ku_vmess_p_{page-1}"))
    if page < n_pages - 1:
        nav.append(InlineKeyboardButton(text="Berikutnya ▶", callback_data=f"ku_vmess_p_{page+1}"))
    if nav: b.row(*nav)
    b.row(InlineKeyboardButton(text="↩ Kembali", callback_data="akun_proto_vmess"))
    return text, b.as_markup()

# ── Entry: buka halaman pilih username ───────────────────────

@router.callback_query(F.data == "kirim_ulang_ssh")
async def cb_kirim_ulang_ssh_menu(cb: CallbackQuery):
    uid   = cb.from_user.id
    await cb.answer()
    items   = _collect_ssh_akun(uid)
    premium = [ac for ac in items if ac.get("IS_TRIAL","0") != "1"]
    if not premium:
        await cb.message.edit_text(
            "❌ Tidak ada akun SSH premium aktif.",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
                InlineKeyboardButton(text="↩ Kembali", callback_data="akun_proto_ssh")
            ]])
        )
        return
    text, kb = _ku_ssh_kb(items, 0)
    await cb.message.edit_text(text, parse_mode="HTML", reply_markup=kb)

@router.callback_query(F.data == "kirim_ulang_vmess")
async def cb_kirim_ulang_vmess_menu(cb: CallbackQuery):
    uid   = cb.from_user.id
    await cb.answer()
    items   = _collect_vmess_akun(uid)
    premium = [vc for vc in items if vc.get("IS_TRIAL","0") != "1"]
    if not premium:
        await cb.message.edit_text(
            "❌ Tidak ada akun VMess premium aktif.",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
                InlineKeyboardButton(text="↩ Kembali", callback_data="akun_proto_vmess")
            ]])
        )
        return
    text, kb = _ku_vmess_kb(items, 0)
    await cb.message.edit_text(text, parse_mode="HTML", reply_markup=kb)

# ── Navigasi halaman pilih username ──────────────────────────

@router.callback_query(F.data.startswith("ku_ssh_p_"))
async def cb_ku_ssh_page(cb: CallbackQuery):
    uid  = cb.from_user.id
    await cb.answer()
    try: page = int(cb.data.split("_")[-1])
    except (ValueError, IndexError): page = 0
    items = _collect_ssh_akun(uid)
    text, kb = _ku_ssh_kb(items, page)
    await cb.message.edit_text(text, parse_mode="HTML", reply_markup=kb)

@router.callback_query(F.data.startswith("ku_vmess_p_"))
async def cb_ku_vmess_page(cb: CallbackQuery):
    uid  = cb.from_user.id
    await cb.answer()
    try: page = int(cb.data.split("_")[-1])
    except (ValueError, IndexError): page = 0
    items = _collect_vmess_akun(uid)
    text, kb = _ku_vmess_kb(items, page)
    await cb.message.edit_text(text, parse_mode="HTML", reply_markup=kb)

# ── Kirim info akun yang dipilih ─────────────────────────────

@router.callback_query(F.data.startswith("ku_ssh_") & ~F.data.startswith("ku_ssh_p_"))
async def cb_ku_ssh_send(cb: CallbackQuery):
    uid      = cb.from_user.id
    username = cb.data.removeprefix("ku_ssh_")
    await cb.answer("📨 Mengirim info akun...", show_alert=False)

    ac = load_account_conf(username)
    if not ac or str(ac.get("TG_USER_ID","")).strip() != str(uid):
        await cb.message.answer("❌ Akun tidak ditemukan.", parse_mode="HTML")
        return

    sname  = ac.get("SERVER","")
    sc     = load_server_conf(sname)
    tgsc   = load_tg_server_conf(sname)
    domain = sc.get("DOMAIN") or sc.get("IP") or ac.get("DOMAIN","")
    if not domain:
        try: domain = open("/etc/zv-manager/domain").read().strip()
        except Exception: pass
    slabel = tgsc.get("TG_SERVER_LABEL","") or sname or domain
    now_ts = int(time.time())
    exp_d, status, sisa_l = _status_label(ac.get("EXPIRED_TS",""), now_ts)
    limit  = ac.get("LIMIT","2")
    passwd = ac.get("PASSWORD","")
    bw_used   = int(ac.get("BW_USED_BYTES","0") or "0")
    bw_quota  = int(ac.get("BW_QUOTA_BYTES","0") or "0")
    bw_line   = f"\n📶 Bandwidth : {fmt_bytes(bw_used)} / {fmt_bytes(bw_quota)}" if bw_quota > 0 else ""

    text = (
        f"📋 <b>Info Akun SSH Kamu</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"👤 Username : <code>{username}</code>\n"
        f"🔑 Password : <code>{passwd}</code>\n"
        f"🌐 Host     : <code>{domain}</code>\n"
        f"🖥 Server   : {slabel}\n"
        f"📅 Expired  : {exp_d} · {sisa_l}\n"
        f"📊 Status   : {status}"
        f"{bw_line}\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"📡 <b>Port</b>\n"
        f"  SSH  : <code>22, 500, 40000</code>\n"
        f"  DB   : <code>109, 143</code>\n"
        f"  BVPN : <code>7300</code>  WS/WSS/UDP\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"🔗 <b>Format HTTP Custom</b>\n"
        f"  Port 80     : <code>{domain}:80@{username}:{passwd}</code>\n"
        f"  Port 443    : <code>{domain}:443@{username}:{passwd}</code>\n"
        f"  UDP 1-65535 : <code>{domain}:1-65535@{username}:{passwd}</code>"
    )
    try:
        await cb.message.bot.send_message(uid, text, parse_mode="HTML")
        items = _collect_ssh_akun(uid)
        ku_text, ku_kb = _ku_ssh_kb(items, 0)
        await cb.message.edit_text(
            f"✅ Info <code>{username}</code> sudah dikirim!\n\n" + ku_text,
            parse_mode="HTML", reply_markup=ku_kb
        )
    except Exception as e:
        await cb.message.answer(f"❌ Gagal kirim: {e}", parse_mode="HTML")

@router.callback_query(F.data.startswith("ku_vmess_") & ~F.data.startswith("ku_vmess_p_"))
async def cb_ku_vmess_send(cb: CallbackQuery):
    uid      = cb.from_user.id
    username = cb.data.removeprefix("ku_vmess_")
    await cb.answer("📨 Mengirim info akun...", show_alert=False)

    vc = load_vmess_conf(username)
    if not vc or str(vc.get("TG_USER_ID","")).strip() != str(uid):
        await cb.message.answer("❌ Akun tidak ditemukan.", parse_mode="HTML")
        return

    sname  = vc.get("SERVER","")
    sc     = load_server_conf(sname)
    tgsc   = load_tg_server_conf(sname)
    domain = sc.get("DOMAIN") or sc.get("IP") or vc.get("DOMAIN","")
    if not domain:
        try: domain = open("/etc/zv-manager/domain").read().strip()
        except Exception: pass
    slabel = tgsc.get("TG_SERVER_LABEL","") or sname or domain
    now_ts = int(time.time())
    exp_d, status, sisa_l = _status_label(vc.get("EXPIRED_TS",""), now_ts)
    uuid   = vc.get("UUID","")
    url_tls, url_http, url_grpc = vmess_build_urls(username, uuid, domain)

    text = (
        f"📋 <b>Info Akun VMess Kamu</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"⚡ Username : <code>{username}</code>\n"
        f"🌐 Server   : {slabel}\n"
        f"🔑 UUID     : <code>{uuid}</code>\n"
        f"📅 Expired  : {exp_d} · {sisa_l}\n"
        f"📊 Status   : {status}\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"📡 Port TLS  : 443 (WS + gRPC)\n"
        f"📡 Port HTTP : 80 (WS)\n"
        f"📎 Path WS   : /vmess\n"
        f"📎 Path gRPC : vmess-grpc\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"🔐 <b>URL VMESS TLS</b>\n"
        f"<code>{url_tls}</code>\n\n"
        f"🔓 <b>URL VMESS HTTP</b>\n"
        f"<code>{url_http}</code>\n\n"
        f"🔒 <b>URL VMESS gRPC</b>\n"
        f"<code>{url_grpc}</code>\n"
        f"━━━━━━━━━━━━━━━━━━━"
    )
    try:
        await cb.message.bot.send_message(uid, text, parse_mode="HTML")
        items = _collect_vmess_akun(uid)
        ku_text, ku_kb = _ku_vmess_kb(items, 0)
        await cb.message.edit_text(
            f"✅ Info <code>{username}</code> sudah dikirim!\n\n" + ku_text,
            parse_mode="HTML", reply_markup=ku_kb
        )
    except Exception as e:
        await cb.message.answer(f"❌ Gagal kirim: {e}", parse_mode="HTML")


# ── Perpanjang ────────────────────────────────────────────────

    """proto: 'ssh' atau 'vmess'"""
    uid       = cb.from_user.id
    akun_list = []
    await cb.answer()

    if proto in ("ssh", "all"):
        try:
            for f in sorted(Path(ACCOUNT_DIR).glob("*.conf")):
                ac = load_account_conf(f.stem)
                if str(ac.get("TG_USER_ID","")).strip() != str(uid): continue
                if ac.get("IS_TRIAL","0") == "1": continue
                uname = ac.get("USERNAME","")
                if uname: akun_list.append(("ssh", uname))
        except Exception: pass

    if proto in ("vmess", "all"):
        try:
            for vf in sorted(Path(VMESS_DIR).glob("*.conf")):
                vc = load_vmess_conf(vf.stem)
                if str(vc.get("TG_USER_ID","")).strip() != str(uid): continue
                if vc.get("IS_TRIAL","0") == "1": continue
                vuname = vc.get("USERNAME","")
                if vuname: akun_list.append(("vmess", vuname))
        except Exception: pass

    back_cb = f"akun_proto_{proto}" if proto != "all" else "m_akun"
    if not akun_list:
        await cb.message.edit_text(
            "🔄 <b>Perpanjang Akun</b>\n\nKamu belum punya akun premium.",
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[
                [InlineKeyboardButton(text="↩ Kembali", callback_data=back_cb)]
            ])
        ); return

    b = InlineKeyboardBuilder()
    row = []
    for p, uname in akun_list:
        label   = f"⚡ {uname}" if p == "vmess" else f"🔑 {uname}"
        cb_data = f"vrenew_{uname}" if p == "vmess" else f"renew_{uname}"
        row.append(InlineKeyboardButton(text=label, callback_data=cb_data))
        if len(row) == 2:
            b.row(*row); row = []
    if row: b.row(*row)
    b.row(InlineKeyboardButton(text="↩ Kembali", callback_data=back_cb))
    await cb.message.edit_text(
        "🔄 <b>Perpanjang Akun</b>\n\nPilih akun:",
        parse_mode="HTML", reply_markup=b.as_markup()
    )

@router.callback_query(F.data == "m_perpanjang_ssh")
async def cb_perpanjang_ssh(cb: CallbackQuery):
    await _show_perpanjang(cb, "ssh")

@router.callback_query(F.data == "m_perpanjang_vmess")
async def cb_perpanjang_vmess(cb: CallbackQuery):
    await _show_perpanjang(cb, "vmess")

@router.callback_query(F.data == "m_perpanjang")
async def cb_perpanjang(cb: CallbackQuery):
    await _show_perpanjang(cb, "all")

@router.callback_query(F.data.startswith("vrenew_"))
async def cb_vrenew_akun(cb: CallbackQuery):
    username = cb.data[len("vrenew_"):]
    uid      = cb.from_user.id
    fname    = cb.from_user.first_name or "User"
    await cb.answer()
    vc = load_vmess_conf(username)
    if not vc:
        await cb.message.edit_text("❌ Akun VMess tidak ditemukan.", reply_markup=kb_home_btn()); return
    if str(vc.get("TG_USER_ID","")).strip() != str(uid):
        await cb.message.edit_text("❌ Akun ini bukan milikmu.", reply_markup=kb_home_btn()); return
    sname      = vc.get("SERVER","")
    tg         = load_tg_server_conf(sname)
    harga      = int(tg.get("TG_HARGA_VMESS_HARI","0") or tg.get("TG_HARGA_HARI","0"))
    hh         = f"Rp{fmt(harga)}/hari" if harga > 0 else "Gratis"
    exp_ts_raw = vc.get("EXPIRED_TS","")
    exp_disp   = ts_to_wib(int(exp_ts_raw)) if exp_ts_raw.isdigit() else vc.get("EXPIRED_DATE","-")
    state_clear(uid)
    state_set(uid, "STATE",    "vrenew_days")
    state_set(uid, "USERNAME", username)
    state_set(uid, "SERVER",   sname)
    state_set(uid, "FNAME",    fname)
    await cb.message.edit_text(
        f"🔄 <b>Perpanjang VMess</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"⚡ Username : <code>{username}</code>\n"
        f"🌐 Server   : {tg['TG_SERVER_LABEL']}\n"
        f"⏳ Expired  : {exp_disp}\n"
        f"💰 Harga    : {hh}\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"Berapa hari ingin diperpanjang? (1-365)",
        parse_mode="HTML", reply_markup=kb_back("m_perpanjang")
    )

@router.callback_query(F.data == "konfirm_vrenew")
async def cb_konfirm_vrenew(cb: CallbackQuery):
    uid = cb.from_user.id
    if state_get(uid, "STATE") != "vrenew_confirm":
        await cb.answer("⚠️ Sesi habis, mulai ulang"); state_clear(uid); return
    await cb.answer("⏳ Memperpanjang VMess...")
    username = state_get(uid, "USERNAME")
    sname    = state_get(uid, "SERVER")
    days     = int(state_get(uid, "DAYS") or "0")
    fname    = state_get(uid, "FNAME")
    tg       = load_tg_server_conf(sname)
    harga    = int(tg.get("TG_HARGA_VMESS_HARI","0") or tg.get("TG_HARGA_HARI","0"))
    total    = harga * days
    if harga > 0 and total > 0:
        if not saldo_deduct(uid, total):
            await cb.message.edit_text("❌ Saldo tidak cukup."); state_clear(uid); return
    vc           = load_vmess_conf(username)
    now_ts       = int(time.time())
    old_exp      = int(vc.get("EXPIRED_TS","0") or "0")
    base_ts      = old_exp if old_exp > now_ts else now_ts
    new_exp_ts   = base_ts + days * 86400
    new_exp_date = datetime.fromtimestamp(new_exp_ts).strftime("%Y-%m-%d")
    new_exp_disp = ts_to_wib(new_exp_ts)
    vc["EXPIRED_TS"]   = str(new_exp_ts)
    vc["EXPIRED_DATE"] = new_exp_date
    save_vmess_conf(username, vc)
    # Perpanjang via agent (lokal/remote)
    sname_renew = vc.get("SERVER", "local")
    await _vmess_agent(sname_renew, "renew", username, days)
    # Hapus marker notified
    try:
        Path(f"{NOTIFY_DIR}/vmess_{username}.notified").unlink(missing_ok=True)
    except Exception: pass
    state_clear(uid)
    zv_log(f"VMESS_RENEW: {uid} user={username} days={days} total={total}")
    backup_realtime_vmess(username, "renew")
    if ADMIN_ID and uid != ADMIN_ID:
        try:
            await cb.bot.send_message(ADMIN_ID,
                f"🔄 <b>Perpanjang VMess</b>\n"
                f"━━━━━━━━━━━━━━━━━━━\n"
                f"👤 User   : {fname} (<code>{uid}</code>)\n"
                f"⚡ Akun   : <code>{username}</code>\n"
                f"📅 Durasi : {days} hari\n"
                f"💸 Total  : Rp{fmt(total)}\n"
                f"━━━━━━━━━━━━━━━━━━━",
                parse_mode="HTML")
        except Exception: pass
    await cb.message.edit_text("✅ VMess berhasil diperpanjang!")
    await cb.message.answer(
        f"🔄 <b>Perpanjang VMess Berhasil</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"⚡ Username  : <code>{username}</code>\n"
        f"📅 Tambah    : {days} hari\n"
        f"⏳ Expired   : {new_exp_disp}\n"
        f"💸 Dibayar   : Rp{fmt(total)}\n"
        f"💰 Sisa Saldo: Rp{fmt(saldo_get(uid))}\n"
        f"━━━━━━━━━━━━━━━━━━━",
        parse_mode="HTML"
    )

@router.callback_query(F.data.startswith("renew_"))
async def cb_renew_akun(cb: CallbackQuery):
    username = cb.data[len("renew_"):]
    uid      = cb.from_user.id
    fname    = cb.from_user.first_name or "User"
    await cb.answer()
    ac = load_account_conf(username)
    if not ac:
        await cb.message.edit_text("❌ Akun tidak ditemukan.", reply_markup=kb_home_btn()); return
    if str(ac.get("TG_USER_ID", "")).strip() != str(uid):
        await cb.message.edit_text("❌ Akun ini bukan milikmu.", reply_markup=kb_home_btn()); return
    sname      = ac.get("SERVER", "")
    tg         = load_tg_server_conf(sname)
    harga      = int(tg["TG_HARGA_HARI"])
    hh         = f"Rp{fmt(harga)}/hari" if harga > 0 else "Gratis"
    exp_ts_raw = ac.get("EXPIRED_TS", "")
    exp_display = ts_to_wib(int(exp_ts_raw)) if exp_ts_raw.isdigit() else ac.get("EXPIRED", "-")
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
        parse_mode="HTML", reply_markup=kb_back("m_perpanjang")
    )

@router.callback_query(F.data == "konfirm_renew")
async def cb_konfirm_renew(cb: CallbackQuery):
    uid = cb.from_user.id
    if state_get(uid, "STATE") != "renew_confirm":
        await cb.answer("⚠️ Sesi habis, mulai ulang"); state_clear(uid); return
    await cb.answer("⏳ Memperpanjang akun...")
    username = state_get(uid, "USERNAME")
    sname    = state_get(uid, "SERVER")
    days     = int(state_get(uid, "DAYS") or "0")
    fname    = state_get(uid, "FNAME")
    tg       = load_tg_server_conf(sname)
    harga    = int(tg["TG_HARGA_HARI"])
    total    = harga * days
    if harga > 0 and total > 0:
        if not saldo_deduct(uid, total):
            await cb.message.edit_text("❌ Saldo tidak cukup."); state_clear(uid); return
    ac           = load_account_conf(username)
    now_ts       = int(time.time())
    old_exp      = int(ac.get("EXPIRED_TS", "0") or "0")
    base_ts      = old_exp if old_exp > now_ts else now_ts
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
    await notify_admin(cb.bot, "RENEW", fname, uid, username, tg["TG_SERVER_LABEL"], days, total)
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
        f"━━━━━━━━━━━━━━━━━━━",
        parse_mode="HTML"
    )


# ── Tambah Bandwidth ─────────────────────────────────────────
async def _show_tambah_bw(cb: CallbackQuery, proto: str):
    """proto: 'ssh' atau 'vmess'"""
    uid       = cb.from_user.id
    akun_list = []  # list of (label, callback_data)
    await cb.answer()

    if proto == "ssh":
        try:
            for f in sorted(Path(ACCOUNT_DIR).glob("*.conf")):
                ac = load_account_conf(f.stem)
                if str(ac.get("TG_USER_ID","")).strip() != str(uid): continue
                if ac.get("IS_TRIAL","0") == "1": continue
                if not ac.get("BW_QUOTA_BYTES","0") or ac.get("BW_QUOTA_BYTES","0") == "0": continue
                uname = ac.get("USERNAME","")
                if uname: akun_list.append((f"🔑 {uname}", f"bw_akun_{uname}"))
        except Exception: pass

    elif proto == "vmess":
        try:
            if Path(VMESS_DIR).exists():
                for vf in sorted(Path(VMESS_DIR).glob("*.conf")):
                    vc = load_vmess_conf(vf.stem)
                    if str(vc.get("TG_USER_ID","")).strip() != str(uid): continue
                    if vc.get("IS_TRIAL","0") == "1": continue
                    bw_limit = int(vc.get("BW_LIMIT_GB","0") or "0")
                    if bw_limit == 0: continue
                    vuname = vc.get("USERNAME","")
                    if vuname: akun_list.append((f"⚡ {vuname}", f"vbw_akun_{vuname}"))
        except Exception: pass

    back_cb = f"akun_proto_{proto}"
    if not akun_list:
        await cb.message.edit_text(
            "📶 <b>Tambah Bandwidth</b>\n\nTidak ada akun yang mendukung fitur bandwidth.",
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[
                [InlineKeyboardButton(text="↩ Kembali", callback_data=back_cb)]
            ])
        ); return

    b = InlineKeyboardBuilder()
    for i in range(0, len(akun_list), 2):
        row = [InlineKeyboardButton(text=akun_list[i][0], callback_data=akun_list[i][1])]
        if i+1 < len(akun_list):
            row.append(InlineKeyboardButton(text=akun_list[i+1][0], callback_data=akun_list[i+1][1]))
        b.row(*row)
    b.row(InlineKeyboardButton(text="↩ Kembali", callback_data=back_cb))
    await cb.message.edit_text(
        "📶 <b>Tambah Bandwidth</b>\n\nPilih akun:",
        parse_mode="HTML", reply_markup=b.as_markup()
    )

@router.callback_query(F.data == "m_tambah_bw_ssh")
async def cb_tambah_bw_ssh(cb: CallbackQuery):
    await _show_tambah_bw(cb, "ssh")

@router.callback_query(F.data == "m_tambah_bw_vmess")
async def cb_tambah_bw_vmess(cb: CallbackQuery):
    await _show_tambah_bw(cb, "vmess")

@router.callback_query(F.data == "m_tambah_bw")
async def cb_tambah_bw(cb: CallbackQuery):
    # Fallback: cek SSH dulu, lalu VMess
    await _show_tambah_bw(cb, "ssh")

@router.callback_query(F.data.startswith("bw_akun_"))
async def cb_bw_akun(cb: CallbackQuery):
    username = cb.data[len("bw_akun_"):]
    uid      = cb.from_user.id
    await cb.answer()
    ac = load_account_conf(username)
    if not ac:
        await cb.message.edit_text("❌ Akun tidak ditemukan.", reply_markup=kb_home_btn()); return
    if str(ac.get("TG_USER_ID", "")).strip() != str(uid):
        await cb.answer("❌ Bukan akun kamu"); return
    sname        = ac.get("SERVER", "")
    tg           = load_tg_server_conf(sname)
    harga_hari   = int(tg["TG_HARGA_HARI"] or "0")
    bw_per_hari  = int(tg.get("TG_BW_PER_HARI", "5") or "5")
    bw_harga_pct = int(tg.get("TG_BW_HARGA_PCT", "40") or "40")
    harga_per_gb = max(1, int(harga_hari * bw_harga_pct / 100))
    bw_quota     = int(ac.get("BW_QUOTA_BYTES", "0") or "0")
    bw_used      = int(ac.get("BW_USED_BYTES", "0") or "0")
    bw_blocked   = ac.get("BW_BLOCKED", "0") == "1"
    pct          = min(round(bw_used * 100 / bw_quota), 100) if bw_quota > 0 else 0
    filled       = pct // 10
    bar          = "▓" * filled + "░" * (10 - filled)
    color        = "🔴" if pct >= 80 else "🟡" if pct >= 50 else "🟢"
    status_str   = "🚫 Diblokir (Bandwidth Habis)" if bw_blocked else "✅ Aktif"
    p1 = harga_per_gb * 1; p5 = harga_per_gb * 5; p10 = harga_per_gb * 10
    state_clear(uid)
    state_set(uid, "STATE",    "bw_pilih_paket")
    state_set(uid, "USERNAME", username)
    state_set(uid, "SERVER",   sname)
    b = InlineKeyboardBuilder()
    b.row(
        InlineKeyboardButton(text=f"➕ 1 GB — Rp{fmt(p1)}",  callback_data=f"bw_beli_1_{username}"),
        InlineKeyboardButton(text=f"➕ 5 GB — Rp{fmt(p5)}",  callback_data=f"bw_beli_5_{username}")
    )
    b.row(InlineKeyboardButton(text=f"➕ 10 GB — Rp{fmt(p10)}", callback_data=f"bw_beli_10_{username}"))
    b.row(InlineKeyboardButton(text="↩ Kembali", callback_data="m_tambah_bw_ssh"))
    await cb.message.edit_text(
        f"➕ <b>Tambah Bandwidth</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"👤 Username : <code>{username}</code>\n"
        f"📶 Terpakai : {fmt_bytes(bw_used)} / {fmt_bytes(bw_quota)}\n"
        f"{color} [{bar}] {pct}%\n"
        f"📊 Status   : {status_str}\n"
        f"💰 Saldo    : Rp{fmt(saldo_get(uid))}\n"
        f"━━━━━━━━━━━━━━━━━━━\nPilih paket tambahan:",
        parse_mode="HTML", reply_markup=b.as_markup()
    )

@router.callback_query(F.data.startswith("bw_beli_"))
async def cb_bw_beli(cb: CallbackQuery):
    parts    = cb.data.split("_", 3)
    gb       = int(parts[2])
    username = parts[3]
    uid      = cb.from_user.id
    await cb.answer()
    ac           = load_account_conf(username)
    sname        = ac.get("SERVER", "")
    tg           = load_tg_server_conf(sname)
    harga_hari   = int(tg["TG_HARGA_HARI"] or "0")
    bw_per_hari  = int(tg.get("TG_BW_PER_HARI", "5") or "5")
    bw_harga_pct = int(tg.get("TG_BW_HARGA_PCT", "40") or "40")
    harga_per_gb = max(1, int(harga_hari * bw_harga_pct / 100))
    total        = harga_per_gb * gb
    saldo        = saldo_get(uid)
    if total > 0 and saldo < total:
        await cb.message.edit_text(
            f"❌ Saldo tidak cukup.\nSaldo  : Rp{fmt(saldo)}\nButuh  : Rp{fmt(total)}\n\nHubungi admin.",
            reply_markup=kb_home_btn()
        )
        state_clear(uid); return
    state_set(uid, "STATE",    "bw_confirm")
    state_set(uid, "USERNAME", username)
    state_set(uid, "SERVER",   sname)
    state_set(uid, "BW_GB",    str(gb))
    state_set(uid, "BW_TOTAL", str(total))
    await cb.message.edit_text(
        f"➕ <b>Konfirmasi Tambah Bandwidth</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"👤 Username     : <code>{username}</code>\n"
        f"📶 Tambah Bandwidth : {gb} GB\n"
        f"💸 Total        : Rp{fmt(total)}\n"
        f"💰 Saldo        : Rp{fmt(saldo)}\n"
        f"━━━━━━━━━━━━━━━━━━━\nLanjutkan?",
        parse_mode="HTML", reply_markup=kb_confirm("bw_konfirm")
    )

@router.callback_query(F.data == "bw_konfirm")
async def cb_konfirm_bw(cb: CallbackQuery):
    uid = cb.from_user.id
    if state_get(uid, "STATE") != "bw_confirm":
        await cb.answer("⚠️ Sesi habis"); state_clear(uid); return
    await cb.answer("⏳ Memproses...")
    username  = state_get(uid, "USERNAME")
    gb        = int(state_get(uid, "BW_GB") or "0")
    total     = int(state_get(uid, "BW_TOTAL") or "0")
    if total > 0:
        if not saldo_deduct(uid, total):
            await cb.message.edit_text("❌ Saldo tidak cukup."); state_clear(uid); return
    add_bytes = gb * 1024 * 1024 * 1024
    ac        = load_account_conf(username)
    old_quota = int(ac.get("BW_QUOTA_BYTES", "0") or "0")
    old_used  = int(ac.get("BW_USED_BYTES", "0") or "0")
    ac["BW_QUOTA_BYTES"] = str(old_quota + add_bytes)
    ac["BW_BLOCKED"]     = "0"
    save_account_conf(username, ac)
    subprocess.run(["/bin/bash", "-c",
        f"source /etc/zv-manager/core/bandwidth.sh && _bw_unblock {username}"],
        capture_output=True)
    state_clear(uid)
    zv_log(f"BW_BELI: {uid} user={username} gb={gb} total={total}")
    new_bw = int(ac["BW_QUOTA_BYTES"])
    await cb.message.edit_text("✅ Bandwidth ditambahkan!")
    await cb.message.answer(
        f"➕ <b>Bandwidth Berhasil Ditambahkan</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"👤 Username     : <code>{username}</code>\n"
        f"📶 Ditambah     : {gb} GB\n"
        f"📊 Total Bandwidth  : {fmt_bytes(new_bw)}\n"
        f"📈 Terpakai     : {fmt_bytes(old_used)}\n"
        f"💸 Dibayar      : Rp{fmt(total)}\n"
        f"💰 Sisa Saldo   : Rp{fmt(saldo_get(uid))}\n"
        f"━━━━━━━━━━━━━━━━━━━\nKoneksi sudah aktif kembali!",
        parse_mode="HTML"
    )


# ── VMess Bandwidth ────────────────────────────────────────────
@router.callback_query(F.data.startswith("vbw_akun_"))
async def cb_vbw_akun(cb: CallbackQuery):
    username = cb.data[len("vbw_akun_"):]
    uid      = cb.from_user.id
    await cb.answer()
    vc = load_vmess_conf(username)
    if not vc:
        await cb.message.edit_text("❌ Akun tidak ditemukan.", reply_markup=kb_home_btn()); return
    if str(vc.get("TG_USER_ID","")).strip() != str(uid):
        await cb.answer("❌ Bukan akun kamu"); return
    sname        = vc.get("SERVER","")
    tg           = load_tg_server_conf(sname)
    harga_hari   = int(tg.get("TG_HARGA_VMESS_HARI","0") or tg.get("TG_HARGA_HARI","0"))
    bw_harga_pct = int(tg.get("TG_BW_HARGA_PCT","40") or "40")
    harga_per_gb = max(1, int(harga_hari * bw_harga_pct / 100))
    bw_limit     = int(vc.get("BW_LIMIT_GB","0") or "0")
    bw_used_b    = int(vc.get("BW_USED_BYTES","0") or "0")
    bw_quota_b   = bw_limit * 1024 * 1024 * 1024
    pct          = min(round(bw_used_b * 100 / bw_quota_b), 100) if bw_quota_b > 0 else 0
    filled       = pct // 10
    bar          = "▓" * filled + "░" * (10 - filled)
    color        = "🔴" if pct >= 80 else "🟡" if pct >= 50 else "🟢"
    p1 = harga_per_gb * 1; p5 = harga_per_gb * 5; p10 = harga_per_gb * 10
    state_clear(uid)
    state_set(uid, "STATE",    "vbw_pilih_paket")
    state_set(uid, "USERNAME", username)
    state_set(uid, "SERVER",   sname)
    b = InlineKeyboardBuilder()
    b.row(
        InlineKeyboardButton(text=f"➕ 1 GB — Rp{fmt(p1)}",  callback_data=f"vbw_beli_1_{username}"),
        InlineKeyboardButton(text=f"➕ 5 GB — Rp{fmt(p5)}",  callback_data=f"vbw_beli_5_{username}")
    )
    b.row(InlineKeyboardButton(text=f"➕ 10 GB — Rp{fmt(p10)}", callback_data=f"vbw_beli_10_{username}"))
    b.row(InlineKeyboardButton(text="↩ Kembali", callback_data="m_tambah_bw_vmess"))
    await cb.message.edit_text(
        f"📶 <b>Tambah Bandwidth VMess</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"⚡ Username : <code>{username}</code>\n"
        f"📶 Terpakai : {fmt_bytes(bw_used_b)} / {bw_limit} GB\n"
        f"{color} [{bar}] {pct}%\n"
        f"💰 Saldo    : Rp{fmt(saldo_get(uid))}\n"
        f"━━━━━━━━━━━━━━━━━━━\nPilih paket tambahan:",
        parse_mode="HTML", reply_markup=b.as_markup()
    )

@router.callback_query(F.data.startswith("vbw_beli_"))
async def cb_vbw_beli(cb: CallbackQuery):
    parts    = cb.data.split("_", 3)
    gb       = int(parts[2])
    username = parts[3]
    uid      = cb.from_user.id
    await cb.answer()
    vc           = load_vmess_conf(username)
    sname        = vc.get("SERVER","")
    tg           = load_tg_server_conf(sname)
    harga_hari   = int(tg.get("TG_HARGA_VMESS_HARI","0") or tg.get("TG_HARGA_HARI","0"))
    bw_harga_pct = int(tg.get("TG_BW_HARGA_PCT","40") or "40")
    harga_per_gb = max(1, int(harga_hari * bw_harga_pct / 100))
    total        = harga_per_gb * gb
    saldo        = saldo_get(uid)
    if total > 0 and saldo < total:
        await cb.message.edit_text(
            f"❌ Saldo tidak cukup.\nSaldo : Rp{fmt(saldo)}\nButuh : Rp{fmt(total)}",
            reply_markup=kb_home_btn()
        ); state_clear(uid); return
    state_set(uid, "STATE",    "vbw_confirm")
    state_set(uid, "USERNAME", username)
    state_set(uid, "SERVER",   sname)
    state_set(uid, "BW_GB",    str(gb))
    state_set(uid, "BW_TOTAL", str(total))
    await cb.message.edit_text(
        f"📶 <b>Konfirmasi Tambah Bandwidth VMess</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"⚡ Username      : <code>{username}</code>\n"
        f"📶 Tambah       : {gb} GB\n"
        f"💸 Total        : Rp{fmt(total)}\n"
        f"💰 Saldo        : Rp{fmt(saldo)}\n"
        f"━━━━━━━━━━━━━━━━━━━\nLanjutkan?",
        parse_mode="HTML", reply_markup=kb_confirm("vbw_konfirm")
    )

@router.callback_query(F.data == "vbw_konfirm")
async def cb_konfirm_vbw(cb: CallbackQuery):
    uid = cb.from_user.id
    if state_get(uid, "STATE") != "vbw_confirm":
        await cb.answer("⚠️ Sesi habis"); state_clear(uid); return
    await cb.answer("⏳ Memproses...")
    username = state_get(uid, "USERNAME")
    gb       = int(state_get(uid, "BW_GB") or "0")
    total    = int(state_get(uid, "BW_TOTAL") or "0")
    if total > 0:
        if not saldo_deduct(uid, total):
            await cb.message.edit_text("❌ Saldo tidak cukup."); state_clear(uid); return
    sname = state_get(uid, "SERVER")
    # Update conf VMess
    vc = load_vmess_conf(username)
    old_limit = int(vc.get("BW_LIMIT_GB","0") or "0")
    new_limit = old_limit + gb
    vc["BW_LIMIT_GB"] = str(new_limit)
    save_vmess_conf(username, vc)
    # Notify agent (agar xray update limit jika support)
    await _vmess_agent(sname, "setbw", username, str(new_limit))
    state_clear(uid)
    zv_log(f"VMESS_BW_BELI: {uid} user={username} gb={gb} total={total}")
    backup_realtime_vmess(username, "edit")
    await cb.message.edit_text("✅ Bandwidth VMess ditambahkan!")
    await cb.message.answer(
        f"📶 <b>Bandwidth VMess Berhasil Ditambahkan</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"⚡ Username   : <code>{username}</code>\n"
        f"📶 Ditambah  : {gb} GB\n"
        f"📊 Total BW  : {new_limit} GB\n"
        f"💸 Dibayar   : Rp{fmt(total)}\n"
        f"💰 Sisa Saldo: Rp{fmt(saldo_get(uid))}\n"
        f"━━━━━━━━━━━━━━━━━━━",
        parse_mode="HTML", reply_markup=kb_home_btn()
    )


# ── Riwayat Saldo ─────────────────────────────────────────────
@router.callback_query(F.data == "m_saldo_history")
async def cb_saldo_history(cb: CallbackQuery):
    uid        = cb.from_user.id
    saldo      = saldo_get(uid)
    entries    = []
    total_bln  = 0
    bulan_ini  = datetime.now().strftime("%Y-%m")
    uid_str    = str(uid)
    await cb.answer()
    for line in tail_log(300):
        if "] TOPUP:" not in line or f"target={uid_str} " not in line: continue
        ts_m = re.search(r"^\[([^\]]+)\]", line)
        am_m = re.search(r"amount=(\d+)", line)
        if not ts_m or not am_m: continue
        ts = ts_m.group(1); amount = int(am_m.group(1))
        entries.append((ts, amount))
        if ts[:7] == bulan_ini: total_bln += amount
    bulan_label = datetime.now().strftime("%B %Y")
    msg = (
        f"💰 <b>Riwayat Saldo</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"💳 Saldo sekarang : Rp{fmt(saldo)}\n"
        f"📅 Total topup {bulan_label} : Rp{fmt(total_bln)}\n"
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


# ── Riwayat Transaksi ─────────────────────────────────────────
@router.callback_query(F.data == "m_history")
async def cb_history(cb: CallbackQuery):
    uid     = cb.from_user.id
    entries = []
    uid_str = str(uid)
    await cb.answer()
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
                entries.append(f"📶 Tambah Bandwidth <code>{user}</code>\n   +{gb} GB — Rp{fmt(total)}\n   <i>{ts}</i>")
            except Exception: pass
    if not entries:
        await cb.message.edit_text(
            "📝 <b>Riwayat Transaksi</b>\n\nBelum ada transaksi.",
            parse_mode="HTML", reply_markup=kb_home_btn()
        ); return
    msg = f"📝 <b>Riwayat Transaksi</b> ({len(entries)} total)\n━━━━━━━━━━━━━━━━━━━\n"
    for i, e in enumerate(entries[-10:]):
        msg += e + "\n"
        if i < min(9, len(entries) - 1):
            msg += "─────────────────\n"
    msg += f"━━━━━━━━━━━━━━━━━━━\n💳 Saldo saat ini: Rp{fmt(saldo_get(uid))}"
    await cb.message.edit_text(msg, parse_mode="HTML", reply_markup=kb_home_btn())


# ── Konfirmasi buat akun ──────────────────────────────────────
@router.callback_query(F.data == "konfirm")
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
    sconf    = load_server_conf(sname)
    tg       = load_tg_server_conf(sname)
    ip       = sconf.get("IP", "")
    lip      = local_ip()
    if not ip: ip = lip
    domain   = sconf.get("DOMAIN") or ip
    harga    = int(tg["TG_HARGA_HARI"])
    total    = harga * days
    now_ts   = int(time.time())
    exp_ts   = now_ts + days * 86400
    exp_date    = datetime.fromtimestamp(exp_ts).strftime("%Y-%m-%d")
    exp_display = ts_to_wib(exp_ts)
    if harga > 0 and total > 0:
        if not saldo_deduct(uid, total):
            await cb.message.edit_text("❌ Saldo tidak cukup."); state_clear(uid); return
    if ip == lip:
        subprocess.run(["useradd", "-e", exp_date, "-s", "/bin/false", "-M", username],
                       capture_output=True)
        subprocess.run(["chpasswd"], input=f"{username}:{password}", text=True,
                       capture_output=True)
        bw_per_hari   = int(tg.get("TG_BW_PER_HARI", "5") or "5")
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
            ["sshpass", "-p", sconf.get("PASS", ""),
             "ssh", "-o", "StrictHostKeyChecking=no",
             "-o", "ConnectTimeout=10", "-o", "BatchMode=no",
             "-p", sconf.get("PORT", "22"),
             f"{sconf.get('USER', '')}@{ip}",
             f"zv-agent add {username} {password} {tg['TG_LIMIT_IP']} {days}"],
            capture_output=True, text=True, timeout=15
        )
        if not result.stdout.startswith("ADD-OK"):
            if total > 0:
                from storage import saldo_add
                saldo_add(uid, total)
            await cb.message.edit_text("❌ Gagal membuat akun. Saldo dikembalikan.")
            state_clear(uid); return
    state_clear(uid)
    zv_log(f"BELI: {uid} server={sname} user={username} days={days} total={total}")
    invalidate_account_cache(ip, "ssh")
    await notify_admin(cb.bot, "BELI", fname, uid, username, tg["TG_SERVER_LABEL"], days, total)
    backup_realtime(username, "create")
    await cb.message.edit_text("✅ Akun sedang dibuat...")
    await cb.message.answer(
        text_akun_info("BELI", username, password, domain, exp_display,
                       tg["TG_LIMIT_IP"], tg["TG_SERVER_LABEL"], days, total, isp=sconf.get("ISP","")),
        parse_mode="HTML", reply_markup=kb_after_buy("ssh")
    )
