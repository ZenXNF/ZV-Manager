#!/usr/bin/env python3
# ============================================================
#   ZV-Manager Bot - Admin Handlers
#   Admin panel, broadcast, top up, kurangi, hapus, cek user,
#   daftar user, history transaksi + helper functions
# ============================================================

import asyncio
import os
import re
import subprocess
from pathlib import Path

from aiogram import F, Router
from aiogram.types import (
    CallbackQuery, InlineKeyboardButton,
    InlineKeyboardMarkup, Message
)
from aiogram.utils.keyboard import InlineKeyboardBuilder

from config import ACCOUNT_DIR, ADMIN_ID, NOTIFY_DIR, USERS_DIR, log
from keyboards import kb_admin_panel, kb_home_btn
from storage import (
    load_account_conf, load_server_conf, load_user_info,
    saldo_get, state_clear, state_set
)
from utils import fmt, tail_log, zv_log

router = Router()


# ── do_hapus_akun helper ──────────────────────────────────────
async def do_hapus_akun(msg: Message, username: str, admin_uid: int):
    conf_file = f"{ACCOUNT_DIR}/{username}.conf"
    if not os.path.exists(conf_file):
        await msg.answer(
            f"❌ Akun <code>{username}</code> tidak ditemukan.",
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
                InlineKeyboardButton(text="🗑️ Coba Lagi", callback_data="adm_hapus_akun"),
                InlineKeyboardButton(text="↩ Admin Panel", callback_data="m_admin")
            ]])
        ); return

    ac     = load_account_conf(username)
    tg_uid = ac.get("TG_USER_ID", "").strip()
    sname  = ac.get("SERVER", "")
    sconf  = load_server_conf(sname)
    lip    = _local_ip_cached()
    srv_ip = sconf.get("IP", "").strip()

    if srv_ip == lip or not srv_ip:
        subprocess.run(["pkill", "-u", username], capture_output=True)
        subprocess.run(["userdel", "-r", username], capture_output=True)
        subprocess.run(["/bin/bash", "-c",
            f"source /etc/zv-manager/core/bandwidth.sh && _bw_cleanup_user {username}"],
            capture_output=True)
    else:
        subprocess.run(
            ["sshpass", "-p", sconf.get("PASS", ""),
             "ssh", "-o", "StrictHostKeyChecking=no",
             "-o", "ConnectTimeout=10", "-o", "BatchMode=no",
             "-p", sconf.get("PORT", "22"),
             f"{sconf.get('USER', '')}@{srv_ip}",
             f"zv-agent del {username}"],
            capture_output=True, timeout=15
        )

    os.remove(conf_file)
    for extra in [f"{NOTIFY_DIR}/{username}.notified",
                  f"{NOTIFY_DIR}/{username}.bw_warn"]:
        try: os.remove(extra)
        except Exception: pass

    zv_log(f"ADM_HAPUS: admin={admin_uid} username={username}")

    from utils import backup_realtime
    backup_realtime(username, "delete")

    await msg.answer(
        f"✅ <b>Akun Berhasil Dihapus</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
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
            await msg.bot.send_message(int(tg_uid),
                f"⚠️ <b>Akun Kamu Dihapus</b>\n━━━━━━━━━━━━━━━━━━━\n"
                f"🗑️ Username : <code>{username}</code>\n"
                f"━━━━━━━━━━━━━━━━━━━\nHubungi admin untuk informasi lebih lanjut.",
                parse_mode="HTML", reply_markup=kb_home_btn())
        except Exception: pass


# ── do_cek_user helper ────────────────────────────────────────
async def do_cek_user(msg: Message, target_uid: int):
    import time
    saldo  = saldo_get(target_uid)
    t_info = load_user_info(target_uid)
    name   = t_info.get("NAME", "(tidak terdaftar)")
    joined = t_info.get("JOINED", "-")
    now_ts = int(time.time())
    akun_info  = ""
    akun_count = 0
    if Path(ACCOUNT_DIR).exists():
        for f in Path(ACCOUNT_DIR).glob("*.conf"):
            ac = load_account_conf(f.stem)
            if str(ac.get("TG_USER_ID", "")).strip() != str(target_uid): continue
            uname    = ac.get("USERNAME", "")
            is_trial = ac.get("IS_TRIAL", "0") == "1"
            exp_ts_r = ac.get("EXPIRED_TS", "0")
            tipe     = "Trial" if is_trial else "Premium"
            status   = "✅ Aktif" if (exp_ts_r.isdigit() and int(exp_ts_r) > now_ts) else "❌ Expired"
            akun_info  += f"   • <code>{uname}</code> ({tipe}) {status}\n"
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


# ── do_broadcast helpers ──────────────────────────────────────
async def do_broadcast(msg: Message, text: str):
    _bot   = msg.bot
    sender = msg.from_user.id
    uids   = _collect_uids()
    uids.discard(sender)
    if not uids:
        await msg.answer("❌ Belum ada user lain yang terdaftar."); return
    await msg.answer(f"⏳ Mengirim ke {len(uids)} user...")
    ok = 0; fail = 0; fail_reasons = []
    for target_uid in uids:
        try:
            await _bot.send_message(target_uid, text, parse_mode="HTML")
            ok += 1
        except Exception as e:
            fail += 1
            reason = f"{type(e).__name__}: {str(e) or '(no message)'}"[:80]
            fail_reasons.append(f"uid {target_uid} → {reason}")
            zv_log(f"BROADCAST FAIL uid={target_uid} err={e}")
        await asyncio.sleep(0.05)
    zv_log(f"BROADCAST DONE total={len(uids)} ok={ok} fail={fail}")
    reason_txt = ""
    if fail_reasons:
        lines = "\n".join(f"• <code>{r}</code>" for r in fail_reasons[:5])
        reason_txt = f"\n\n🔍 <b>Detail Error:</b>\n{lines}"
    await msg.answer(
        f"📢 <b>Broadcast Selesai</b>\n━━━━━━━━━━━━━━━━━━━\n"
        f"✅ Terkirim : {ok} user\n"
        f"❌ Gagal    : {fail} user\n"
        f"━━━━━━━━━━━━━━━━━━━{reason_txt}",
        parse_mode="HTML"
    )

async def do_broadcast_stiker(msg: Message, file_id: str):
    _bot   = msg.bot
    sender = msg.from_user.id
    uids   = _collect_uids()
    uids.discard(sender)
    if not uids:
        await msg.answer("❌ Belum ada user lain yang terdaftar."); return
    await msg.answer(f"⏳ Mengirim stiker ke {len(uids)} user...")
    ok = 0; fail = 0; fail_reasons = []
    for target_uid in uids:
        try:
            await _bot.send_sticker(target_uid, file_id)
            ok += 1
        except Exception as e:
            fail += 1
            fail_reasons.append(f"uid {target_uid} → {type(e).__name__}: {str(e)[:50]}")
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
        f"━━━━━━━━━━━━━━━━━━━{reason_txt}",
        parse_mode="HTML"
    )

def _collect_uids() -> set[int]:
    uids: set[int] = set()
    if Path(USERS_DIR).exists():
        for f in Path(USERS_DIR).glob("*.user"):
            try: uids.add(int(f.stem))
            except: pass
    if Path(ACCOUNT_DIR).exists():
        for f in Path(ACCOUNT_DIR).glob("*.conf"):
            ac  = load_account_conf(f.stem)
            tid = ac.get("TG_USER_ID", "").strip()
            if tid.isdigit(): uids.add(int(tid))
    return uids

def _local_ip_cached() -> str:
    from utils import local_ip
    return local_ip()


# ── Admin Panel ───────────────────────────────────────────────
@router.callback_query(F.data == "m_admin")
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

@router.callback_query(F.data == "m_broadcast")
async def cb_broadcast(cb: CallbackQuery):
    uid = cb.from_user.id
    if uid != ADMIN_ID:
        await cb.answer("❌ Akses ditolak"); return
    await cb.answer()
    state_clear(uid)
    await cb.message.edit_text(
        "📢 <b>Broadcast</b>\n━━━━━━━━━━━━━━━━━━━\nPilih jenis broadcast:",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[
            [InlineKeyboardButton(text="✉️ Teks / HTML", callback_data="bc_teks")],
            [InlineKeyboardButton(text="🎭 Stiker",      callback_data="bc_stiker")],
            [InlineKeyboardButton(text="❌ Batal",       callback_data="home")],
        ])
    )

@router.callback_query(F.data == "bc_teks")
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
        "Bisa pakai format HTML: <code>&lt;b&gt;bold&lt;/b&gt;</code>\n\nKetik pesan:",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
            InlineKeyboardButton(text="❌ Batal", callback_data="home")
        ]])
    )

@router.callback_query(F.data == "bc_stiker")
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

@router.callback_query(F.data == "adm_topup")
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
        "Contoh: <code>123456789</code>",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
            InlineKeyboardButton(text="❌ Batal", callback_data="m_admin")
        ]])
    )

@router.callback_query(F.data == "adm_kurangi")
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

@router.callback_query(F.data == "adm_hapus_akun")
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

@router.callback_query(F.data == "adm_daftar_user")
async def cb_adm_daftar_user(cb: CallbackQuery):
    uid = cb.from_user.id
    if uid != ADMIN_ID:
        await cb.answer("❌ Akses ditolak"); return
    await cb.answer()
    users = []
    if Path(USERS_DIR).exists():
        for f in Path(USERS_DIR).glob("*.user"):
            info = load_user_info(int(f.stem))
            if info.get("UID"): users.append(info)
    if not users:
        await cb.message.edit_text("👥 <b>Daftar User</b>\n\nBelum ada user terdaftar.",
                                    parse_mode="HTML", reply_markup=kb_admin_panel()); return
    msg = f"👥 <b>Daftar User Terdaftar</b> ({len(users)} total)\n━━━━━━━━━━━━━━━━━━━\n"
    for u in users[-20:]:
        saldo = saldo_get(int(u.get("UID", "0")))
        msg += (f"👤 <b>{u.get('NAME', '-')}</b> — <code>{u.get('UID', '-')}</code>\n"
                f"   💰 Rp{fmt(saldo)} | 📅 {u.get('JOINED', '-')[:10]}\n")
    msg += "━━━━━━━━━━━━━━━━━━━"
    await cb.message.edit_text(msg, parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
            InlineKeyboardButton(text="↩ Kembali", callback_data="m_admin")
        ]]))

@router.callback_query(F.data == "adm_cek_user")
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

@router.callback_query(F.data == "adm_history")
async def cb_adm_history(cb: CallbackQuery):
    uid = cb.from_user.id
    if uid != ADMIN_ID:
        await cb.answer("❌ Akses ditolak"); return
    await cb.answer()
    entries = []
    for line in tail_log(200):
        for tag in ["BELI", "RENEW", "BW_BELI", "TOPUP", "KURANGI"]:
            if f"] {tag}:" in line:
                entries.append(line.strip()); break
    if not entries:
        await cb.message.edit_text(
            "📊 <b>History Transaksi</b>\n\nBelum ada transaksi tercatat.",
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
                InlineKeyboardButton(text="↩ Kembali", callback_data="m_admin")
            ]])
        ); return
    msg = f"📊 <b>History Transaksi</b> ({len(entries)} total, 15 terakhir)\n━━━━━━━━━━━━━━━━━━━\n"
    for i, line in enumerate(entries[-15:]):
        ts_m = re.search(r"^\[([^\]]+)\]", line)
        ts   = ts_m.group(1) if ts_m else "-"
        if "] BELI:" in line:
            u = re.search(r"user=(\S+)", line); d = re.search(r"days=(\d+)", line)
            t = re.search(r"total=(\d+)", line); s = re.search(r"server=(\S+)", line)
            uid_m = re.search(r"BELI: (\S+)", line)
            msg += (f"🛒 <b>Beli</b> — <code>{u.group(1) if u else '?'}</code> ({s.group(1) if s else '?'})\n"
                    f"   {d.group(1) if d else '?'} hari · Rp{fmt(t.group(1) if t else 0)} · uid:{uid_m.group(1) if uid_m else '?'}\n"
                    f"   <i>{ts}</i>\n")
        elif "] RENEW:" in line:
            u = re.search(r"user=(\S+)", line); d = re.search(r"days=(\d+)", line)
            t = re.search(r"total=(\d+)", line); uid_m = re.search(r"RENEW: (\S+)", line)
            msg += (f"🔄 <b>Renew</b> — <code>{u.group(1) if u else '?'}</code>\n"
                    f"   +{d.group(1) if d else '?'} hari · Rp{fmt(t.group(1) if t else 0)} · uid:{uid_m.group(1) if uid_m else '?'}\n"
                    f"   <i>{ts}</i>\n")
        elif "] BW_BELI:" in line:
            u = re.search(r"user=(\S+)", line); g = re.search(r"gb=(\d+)", line)
            t = re.search(r"total=(\d+)", line); uid_m = re.search(r"BW_BELI: (\S+)", line)
            msg += (f"📶 <b>Beli BW</b> — <code>{u.group(1) if u else '?'}</code>\n"
                    f"   +{g.group(1) if g else '?'} GB · Rp{fmt(t.group(1) if t else 0)} · uid:{uid_m.group(1) if uid_m else '?'}\n"
                    f"   <i>{ts}</i>\n")
        elif "] TOPUP:" in line:
            adm = re.search(r"admin=(\S+)", line); tgt = re.search(r"target=(\S+)", line)
            amt = re.search(r"amount=(\d+)", line)
            msg += (f"💰 <b>Top Up</b> — uid:{tgt.group(1) if tgt else '?'}\n"
                    f"   +Rp{fmt(amt.group(1) if amt else 0)} oleh admin:{adm.group(1) if adm else '?'}\n"
                    f"   <i>{ts}</i>\n")
        elif "] KURANGI:" in line:
            adm = re.search(r"admin=(\S+)", line); tgt = re.search(r"target=(\S+)", line)
            amt = re.search(r"amount=(\d+)", line)
            msg += (f"➖ <b>Kurangi</b> — uid:{tgt.group(1) if tgt else '?'}\n"
                    f"   -Rp{fmt(amt.group(1) if amt else 0)} oleh admin:{adm.group(1) if adm else '?'}\n"
                    f"   <i>{ts}</i>\n")
        if i < min(14, len(entries[-15:]) - 1):
            msg += "─────────────────\n"
    msg += "━━━━━━━━━━━━━━━━━━━"
    await cb.message.edit_text(msg, parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
            InlineKeyboardButton(text="↩ Kembali", callback_data="m_admin")
        ]]))

# ── Online VMess ─────────────────────────────────────────────
@router.callback_query(F.data == "adm_online_vmess")
async def cb_adm_online_vmess(cb: CallbackQuery):
    uid = cb.from_user.id
    if uid != ADMIN_ID:
        await cb.answer("❌ Akses ditolak"); return
    await cb.answer()

    import re
    from datetime import datetime, timedelta
    from pathlib import Path

    xray_log  = "/var/log/xray-access.log"
    nginx_log = "/var/log/nginx/access.log"
    now       = datetime.now()
    window    = timedelta(minutes=5)

    # Parse nginx: timestamp → [ip, ...]
    nginx_re = re.compile(
        r'^(\S+) \S+ \S+ \[(\d+/\w+/\d+:\d+:\d+:\d+) ([+-]\d{4})\] '
        r'"(?:GET|POST) /vmess[\s/].*?" (101)'
    )
    nginx_map: dict = {}
    try:
        with open(nginx_log) as f:
            for line in f:
                m = nginx_re.match(line)
                if not m: continue
                ip, ts_str, tz_str, _ = m.groups()
                dt = datetime.strptime(f"{ts_str} {tz_str}", "%d/%b/%Y:%H:%M:%S %z").astimezone().replace(tzinfo=None)
                if now - dt > window: continue
                key = dt.strftime("%Y/%m/%d %H:%M:%S")
                nginx_map.setdefault(key, []).append(ip)
    except Exception:
        pass

    # Parse xray: timestamp + email → match ke nginx_map
    xray_re = re.compile(
        r'^(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2})\.\d+ from 127\.0\.0\.1:\d+ '
        r'accepted .+ email: (\S+@vmess)'
    )
    # {username: {ip: last_seen_dt}}
    user_data: dict = {}
    try:
        with open(xray_log) as f:
            for line in f:
                m = xray_re.match(line)
                if not m: continue
                ts_key, email = m.groups()
                base_dt = datetime.strptime(ts_key, "%Y/%m/%d %H:%M:%S")
                if now - base_dt > window: continue
                username = email.replace("@vmess", "")
                for delta in range(-2, 3):
                    check = (base_dt + timedelta(seconds=delta)).strftime("%Y/%m/%d %H:%M:%S")
                    for ip in nginx_map.get(check, []):
                        if username not in user_data:
                            user_data[username] = {}
                        if ip not in user_data[username] or user_data[username][ip] < base_dt:
                            user_data[username][ip] = base_dt
    except Exception:
        pass

    if not user_data:
        msg = (
            "🟢 <b>Online VMess</b>\n"
            "━━━━━━━━━━━━━━━━━━━\n"
            "😴 Tidak ada user aktif saat ini\n"
            "━━━━━━━━━━━━━━━━━━━"
        )
    else:
        msg = (
            f"🟢 <b>Online VMess</b> — {len(user_data)} user aktif\n"
            "━━━━━━━━━━━━━━━━━━━\n"
        )
        for username, ips in sorted(user_data.items()):
            last_seen = max(ips.values())
            ago = int((now - last_seen).total_seconds() / 60)
            ip_list = ", ".join(sorted(set(ips.keys())))
            msg += (
                f"👤 <code>{username}</code>\n"
                f"   🌐 {ip_list}\n"
                f"   🕐 {ago} menit lalu\n"
            )
        msg += "━━━━━━━━━━━━━━━━━━━"

    await cb.message.edit_text(
        msg, parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
            InlineKeyboardButton(text="🔄 Refresh",  callback_data="adm_online_vmess"),
            InlineKeyboardButton(text="↩ Kembali", callback_data="m_admin"),
        ]])
    )
