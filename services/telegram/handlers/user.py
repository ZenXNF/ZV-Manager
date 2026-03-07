#!/usr/bin/env python3
# ============================================================
#   ZV-Manager Bot - User Handlers
#   /start, home, buat akun, trial, akun saya,
#   perpanjang, tambah bandwidth, riwayat, konfirmasi
# ============================================================

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

from config import ACCOUNT_DIR, ADMIN_ID, NOTIFY_DIR, log
from keyboards import (
    kb_back, kb_confirm, kb_for_user, kb_home_btn, kb_server_list
)
from middleware import _throttle
from storage import (
    already_trial, count_accounts, load_account_conf,
    load_server_conf, load_tg_server_conf, local_ip, mark_trial,
    register_user, saldo_deduct, saldo_get, save_account_conf,
    state_clear, state_get, state_set
)
from texts import text_akun_info, text_home, text_server_list
from utils import backup_realtime, fmt, fmt_bytes, tail_log, ts_to_wib, zv_log

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
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
            InlineKeyboardButton(text="SSH", callback_data="proto_buat_ssh"),
            InlineKeyboardButton(text="↩ Kembali", callback_data="home")
        ]]))
    await cb.answer()

@router.callback_query(F.data == "m_trial")
async def cb_menu_trial(cb: CallbackQuery):
    await cb.message.edit_text(
        "🎁 <b>Coba Gratis</b>\n\nPilih protokol:", parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
            InlineKeyboardButton(text="SSH", callback_data="proto_trial_ssh"),
            InlineKeyboardButton(text="↩ Kembali", callback_data="home")
        ]]))
    await cb.answer()

@router.callback_query(F.data == "proto_buat_ssh")
async def cb_proto_buat_ssh(cb: CallbackQuery):
    if not load_server_list_safe():
        await cb.message.edit_text("❌ Belum ada server.")
        await cb.answer(); return
    await cb.message.edit_text(text_server_list("Buat Akun SSH"), parse_mode="HTML",
                                reply_markup=kb_server_list("s_buat"))
    await cb.answer()

@router.callback_query(F.data == "proto_trial_ssh")
async def cb_proto_trial_ssh(cb: CallbackQuery):
    if not load_server_list_safe():
        await cb.message.edit_text("❌ Belum ada server.")
        await cb.answer(); return
    await cb.message.edit_text(text_server_list("Trial SSH Gratis"), parse_mode="HTML",
                                reply_markup=kb_server_list("s_trial"))
    await cb.answer()

def load_server_list_safe() -> bool:
    from storage import get_server_list
    return bool(get_server_list())

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
    domain = sconf.get("DOMAIN") or ip

    if count_accounts(ip) >= int(tg["TG_MAX_AKUN"]):
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

    mark_trial(uid, sname)
    zv_log(f"TRIAL: {uid} server={sname} user={username}")
    await cb.message.answer(
        text_akun_info("TRIAL", username, password, domain,
                       exp_display, tg["TG_LIMIT_IP"], tg["TG_SERVER_LABEL"]),
        parse_mode="HTML", reply_markup=kb_home_btn()
    )


# ── Akun Saya ─────────────────────────────────────────────────
@router.callback_query(F.data == "m_akun")
async def cb_akun_saya(cb: CallbackQuery):
    uid    = cb.from_user.id
    now_ts = int(time.time())
    out    = "📋 <b>Akun Kamu</b>\n━━━━━━━━━━━━━━━━━━━\n"
    found  = False
    await cb.answer()
    try:
        for f in Path(ACCOUNT_DIR).glob("*.conf"):
            ac = load_account_conf(f.stem)
            if str(ac.get("TG_USER_ID", "")).strip() != str(uid):
                continue
            uname      = ac.get("USERNAME", "")
            passwd     = ac.get("PASSWORD", "")
            exp_ts_raw = ac.get("EXPIRED_TS", "")
            is_trial   = ac.get("IS_TRIAL", "0") == "1"
            sname      = ac.get("SERVER", "")
            sc         = load_server_conf(sname)
            domain     = sc.get("DOMAIN") or sc.get("IP") or ac.get("DOMAIN", "")
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
                exp_display = ac.get("EXPIRED", "-")
                status = "✅ Aktif"; sisa_label = "-"
            tipe  = "Trial" if is_trial else "Premium"
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


# ── Perpanjang ────────────────────────────────────────────────
@router.callback_query(F.data == "m_perpanjang")
async def cb_perpanjang(cb: CallbackQuery):
    uid       = cb.from_user.id
    akun_list = []
    await cb.answer()
    try:
        for f in Path(ACCOUNT_DIR).glob("*.conf"):
            ac = load_account_conf(f.stem)
            if str(ac.get("TG_USER_ID", "")).strip() != str(uid): continue
            if ac.get("IS_TRIAL", "0") == "1": continue
            uname = ac.get("USERNAME", "")
            if uname: akun_list.append(uname)
    except Exception:
        pass
    if not akun_list:
        await cb.message.edit_text(
            "📋 <b>Perpanjang Akun</b>\n\nKamu belum punya akun premium.",
            parse_mode="HTML", reply_markup=kb_home_btn()
        ); return
    b = InlineKeyboardBuilder()
    for i in range(0, len(akun_list), 2):
        row = [InlineKeyboardButton(text=akun_list[i], callback_data=f"renew_{akun_list[i]}")]
        if i+1 < len(akun_list):
            row.append(InlineKeyboardButton(text=akun_list[i+1], callback_data=f"renew_{akun_list[i+1]}"))
        b.row(*row)
    b.row(InlineKeyboardButton(text="↩ Kembali", callback_data="home"))
    await cb.message.edit_text(
        "🔄 <b>Perpanjang Akun</b>\n\nPilih akun:",
        parse_mode="HTML", reply_markup=b.as_markup()
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


# ── Tambah Bandwidth Bandwidth ───────────────────────────────────
@router.callback_query(F.data == "m_tambah_bw")
async def cb_tambah_bw(cb: CallbackQuery):
    uid       = cb.from_user.id
    akun_list = []
    await cb.answer()
    try:
        for f in Path(ACCOUNT_DIR).glob("*.conf"):
            ac = load_account_conf(f.stem)
            if str(ac.get("TG_USER_ID", "")).strip() != str(uid): continue
            if ac.get("IS_TRIAL", "0") == "1": continue
            if not ac.get("BW_QUOTA_BYTES", "0") or ac.get("BW_QUOTA_BYTES", "0") == "0": continue
            uname = ac.get("USERNAME", "")
            if uname: akun_list.append(uname)
    except Exception: pass
    if not akun_list:
        await cb.message.edit_text(
            "📶 <b>Tambah Bandwidth</b>\n\nTidak ada akun yang mendukung fitur bandwidth.",
            parse_mode="HTML", reply_markup=kb_home_btn()
        ); return
    b = InlineKeyboardBuilder()
    for i in range(0, len(akun_list), 2):
        row = [InlineKeyboardButton(text=akun_list[i], callback_data=f"bw_akun_{akun_list[i]}")]
        if i+1 < len(akun_list):
            row.append(InlineKeyboardButton(text=akun_list[i+1], callback_data=f"bw_akun_{akun_list[i+1]}"))
        b.row(*row)
    b.row(InlineKeyboardButton(text="↩ Kembali", callback_data="m_akun"))
    await cb.message.edit_text("➕ <b>Tambah Bandwidth</b>\n\nPilih akun:",
                                parse_mode="HTML", reply_markup=b.as_markup())

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
    harga_per_gb = (harga_hari // bw_per_hari) if bw_per_hari > 0 else 0
    bw_quota     = int(ac.get("BW_QUOTA_BYTES", "0") or "0")
    bw_used      = int(ac.get("BW_USED_BYTES", "0") or "0")
    bw_blocked   = ac.get("BW_BLOCKED", "0") == "1"
    pct          = min(int(bw_used * 100 / bw_quota), 100) if bw_quota > 0 else 0
    filled       = pct // 10
    bar          = "▓" * filled + "░" * (10 - filled)
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
    b.row(InlineKeyboardButton(text="↩ Kembali", callback_data="m_tambah_bw"))
    await cb.message.edit_text(
        f"➕ <b>Tambah Bandwidth</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"👤 Username : <code>{username}</code>\n"
        f"📶 Terpakai : {fmt_bytes(bw_used)} / {fmt_bytes(bw_quota)}\n"
        f"[{bar}] {pct}%\n"
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
    harga_per_gb = (harga_hari // bw_per_hari) if bw_per_hari > 0 else 0
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
    new_quota = int(ac["BW_QUOTA_BYTES"])
    await cb.message.edit_text("✅ Bandwidth ditambahkan!")
    await cb.message.answer(
        f"➕ <b>Bandwidth Berhasil Ditambahkan</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"👤 Username     : <code>{username}</code>\n"
        f"📶 Ditambah     : {gb} GB\n"
        f"📊 Total Bandwidth  : {fmt_bytes(new_quota)}\n"
        f"📈 Terpakai     : {fmt_bytes(old_used)}\n"
        f"💸 Dibayar      : Rp{fmt(total)}\n"
        f"💰 Sisa Saldo   : Rp{fmt(saldo_get(uid))}\n"
        f"━━━━━━━━━━━━━━━━━━━\nKoneksi sudah aktif kembali!",
        parse_mode="HTML"
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
    await notify_admin(cb.bot, "BELI", fname, uid, username, tg["TG_SERVER_LABEL"], days, total)
    backup_realtime(username, "create")
    await cb.message.edit_text("✅ Akun sedang dibuat...")
    await cb.message.answer(
        text_akun_info("BELI", username, password, domain, exp_display,
                       tg["TG_LIMIT_IP"], tg["TG_SERVER_LABEL"], days, total),
        parse_mode="HTML", reply_markup=kb_home_btn()
    )
