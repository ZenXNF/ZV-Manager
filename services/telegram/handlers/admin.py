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

from config import ACCOUNT_DIR, ADMIN_ID, NOTIFY_DIR, USERS_DIR, BASE_DIR, log
from keyboards import kb_admin_panel, kb_home_btn
import time
from storage import (
    load_account_conf, load_server_conf, load_user_info,
    saldo_get, state_clear, state_set, invalidate_account_cache,
    get_server_list_by_type, get_server_list,
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

    invalidate_account_cache(srv_ip or _local_ip_cached(), "ssh")
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

async def do_broadcast_server(msg: Message, text: str, server_name: str):
    """Broadcast teks ke user di server tertentu saja."""
    _bot   = msg.bot
    sender = msg.from_user.id
    sc     = load_server_conf(server_name)
    label  = sc.get("TG_SERVER_LABEL") or sc.get("DOMAIN") or server_name
    uids   = _collect_uids_by_server(server_name)
    uids.discard(sender)
    if not uids:
        await msg.answer(f"❌ Tidak ada user di server {label}."); return
    await msg.answer(f"⏳ Mengirim ke {len(uids)} user di {label}...")
    ok = 0; fail = 0; fail_reasons = []
    for target_uid in uids:
        try:
            await _bot.send_message(target_uid, text, parse_mode="HTML")
            ok += 1
        except Exception as e:
            fail += 1
            reason = f"{type(e).__name__}: {str(e) or '(no message)'}'"[:80]
            fail_reasons.append(f"uid {target_uid} → {reason}")
            zv_log(f"BROADCAST_SERVER FAIL uid={target_uid} err={e}")
        await asyncio.sleep(0.05)
    zv_log(f"BROADCAST_SERVER DONE server={server_name} total={len(uids)} ok={ok} fail={fail}")
    reason_txt = ""
    if fail_reasons:
        lines = "\n".join(f"• <code>{r}</code>" for r in fail_reasons[:5])
        reason_txt = f"\n\n🔍 <b>Detail Error:</b>\n{lines}"
    await msg.answer(
        f"🖥 <b>Broadcast {label} Selesai</b>\n━━━━━━━━━━━━━━━━━━━\n"
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
            [InlineKeyboardButton(text="✉️ Semua User",     callback_data="bc_teks")],
            [InlineKeyboardButton(text="🖥 Per Server",     callback_data="bc_server")],
            [InlineKeyboardButton(text="🎭 Stiker",         callback_data="bc_stiker")],
            [InlineKeyboardButton(text="❌ Batal",          callback_data="home")],
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
        "📢 <b>Broadcast — Semua User</b>\n━━━━━━━━━━━━━━━━━━━\n"
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

# ── Broadcast Per Server ──────────────────────────────────────

def _collect_uids_by_server(server_name: str) -> set[int]:
    """Kumpulkan TG_USER_ID dari semua akun SSH + VMess di server tertentu."""
    uids: set[int] = set()
    # SSH
    try:
        for f in Path(ACCOUNT_DIR).glob("*.conf"):
            ac = load_account_conf(f.stem)
            if ac.get("SERVER","") == server_name:
                tid = ac.get("TG_USER_ID","").strip()
                if tid.isdigit(): uids.add(int(tid))
    except Exception: pass
    # VMess
    vmess_dir = f"{BASE_DIR}/accounts/vmess"
    try:
        for f in Path(vmess_dir).glob("*.conf"):
            from storage import load_vmess_conf
            vc = load_vmess_conf(f.stem)
            if vc.get("SERVER","") == server_name:
                tid = vc.get("TG_USER_ID","").strip()
                if tid.isdigit(): uids.add(int(tid))
    except Exception: pass
    return uids

@router.callback_query(F.data == "bc_server")
async def cb_bc_server(cb: CallbackQuery):
    uid = cb.from_user.id
    if uid != ADMIN_ID:
        await cb.answer("❌ Akses ditolak"); return
    await cb.answer()
    state_clear(uid)
    servers = get_server_list()
    if not servers:
        await cb.message.edit_text(
            "❌ Tidak ada server terdaftar.",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
                InlineKeyboardButton(text="↩ Kembali", callback_data="m_broadcast")
            ]])
        )
        return
    b = InlineKeyboardBuilder()
    for s in servers:
        name  = s.get("NAME","")
        label = s.get("TG_SERVER_LABEL") or name
        # Hitung jumlah user unik di server ini
        count = len(_collect_uids_by_server(name))
        b.row(InlineKeyboardButton(
            text=f"🖥 {label} ({count} user)",
            callback_data=f"bc_srv_{name}"
        ))
    b.row(InlineKeyboardButton(text="↩ Kembali", callback_data="m_broadcast"))
    await cb.message.edit_text(
        "🖥 <b>Broadcast Per Server</b>\n━━━━━━━━━━━━━━━━━━━\nPilih server tujuan:",
        parse_mode="HTML",
        reply_markup=b.as_markup()
    )

@router.callback_query(F.data.startswith("bc_srv_"))
async def cb_bc_srv_pick(cb: CallbackQuery):
    uid = cb.from_user.id
    if uid != ADMIN_ID:
        await cb.answer("❌ Akses ditolak"); return
    await cb.answer()
    server_name = cb.data.removeprefix("bc_srv_")
    sc    = load_server_conf(server_name)
    label = sc.get("TG_SERVER_LABEL") or sc.get("DOMAIN") or server_name
    uids  = _collect_uids_by_server(server_name)
    if not uids:
        await cb.message.edit_text(
            f"❌ Tidak ada user di server <b>{label}</b>.",
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
                InlineKeyboardButton(text="↩ Kembali", callback_data="bc_server")
            ]])
        )
        return
    # Simpan target server di state
    state_clear(uid)
    state_set(uid, "STATE",      "broadcast_server_msg")
    state_set(uid, "BC_SERVER",  server_name)
    await cb.message.edit_text(
        f"🖥 <b>Broadcast → {label}</b>\n━━━━━━━━━━━━━━━━━━━\n"
        f"Pesan akan dikirim ke <b>{len(uids)} user</b> di server ini.\n\n"
        "Ketik pesan (bisa HTML):",
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
        for tag in ["BELI", "VMESS_BELI", "RENEW", "VMESS_RENEW", "BW_BELI", "VMESS_BW_BELI", "TOPUP", "KURANGI"]:
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
            msg += (f"🛒 <b>Beli SSH</b> — <code>{u.group(1) if u else '?'}</code> ({s.group(1) if s else '?'})\n"
                    f"   {d.group(1) if d else '?'} hari · Rp{fmt(t.group(1) if t else 0)} · uid:{uid_m.group(1) if uid_m else '?'}\n"
                    f"   <i>{ts}</i>\n")
        elif "] VMESS_BELI:" in line:
            u = re.search(r"user=(\S+)", line); d = re.search(r"days=(\d+)", line)
            t = re.search(r"total=(\d+)", line); s = re.search(r"server=(\S+)", line)
            uid_m = re.search(r"VMESS_BELI: (\S+)", line)
            msg += (f"🛒 <b>Beli VMess</b> — <code>{u.group(1) if u else '?'}</code> ({s.group(1) if s else '?'})\n"
                    f"   {d.group(1) if d else '?'} hari · Rp{fmt(t.group(1) if t else 0)} · uid:{uid_m.group(1) if uid_m else '?'}\n"
                    f"   <i>{ts}</i>\n")
        elif "] RENEW:" in line:
            u = re.search(r"user=(\S+)", line); d = re.search(r"days=(\d+)", line)
            t = re.search(r"total=(\d+)", line); uid_m = re.search(r"RENEW: (\S+)", line)
            msg += (f"🔄 <b>Renew SSH</b> — <code>{u.group(1) if u else '?'}</code>\n"
                    f"   +{d.group(1) if d else '?'} hari · Rp{fmt(t.group(1) if t else 0)} · uid:{uid_m.group(1) if uid_m else '?'}\n"
                    f"   <i>{ts}</i>\n")
        elif "] VMESS_RENEW:" in line:
            u = re.search(r"user=(\S+)", line); d = re.search(r"days=(\d+)", line)
            t = re.search(r"total=(\d+)", line); uid_m = re.search(r"VMESS_RENEW: (\S+)", line)
            msg += (f"🔄 <b>Renew VMess</b> — <code>{u.group(1) if u else '?'}</code>\n"
                    f"   +{d.group(1) if d else '?'} hari · Rp{fmt(t.group(1) if t else 0)} · uid:{uid_m.group(1) if uid_m else '?'}\n"
                    f"   <i>{ts}</i>\n")
        elif "] BW_BELI:" in line:
            u = re.search(r"user=(\S+)", line); g = re.search(r"gb=(\d+)", line)
            t = re.search(r"total=(\d+)", line); uid_m = re.search(r"BW_BELI: (\S+)", line)
            msg += (f"📶 <b>Beli BW SSH</b> — <code>{u.group(1) if u else '?'}</code>\n"
                    f"   +{g.group(1) if g else '?'} GB · Rp{fmt(t.group(1) if t else 0)} · uid:{uid_m.group(1) if uid_m else '?'}\n"
                    f"   <i>{ts}</i>\n")
        elif "] VMESS_BW_BELI:" in line:
            u = re.search(r"user=(\S+)", line); g = re.search(r"gb=(\d+)", line)
            t = re.search(r"total=(\d+)", line); uid_m = re.search(r"VMESS_BW_BELI: (\S+)", line)
            msg += (f"📶 <b>Beli BW VMess</b> — <code>{u.group(1) if u else '?'}</code>\n"
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

# ── Admin: Kelola VMess ───────────────────────────────────────
VMESS_DIR_ADMIN = "/etc/zv-manager/accounts/vmess"

def _load_vmess_list():
    """Return list dict dari semua conf VMess di brain."""
    items = []
    p = Path(VMESS_DIR_ADMIN)
    if not p.exists():
        return items
    for conf in sorted(p.glob("*.conf")):
        d = {}
        for line in conf.read_text().splitlines():
            if "=" in line:
                k, _, v = line.partition("=")
                d[k.strip()] = v.strip().strip('"')
        if d.get("USERNAME"):
            items.append(d)
    return items

async def _vmess_agent_admin(sname: str, *args) -> str:
    import asyncio
    cmd_parts = " ".join(str(a) for a in args)
    srv = sname if sname and sname != "local" else "local"
    cmd = f"source /etc/zv-manager/utils/remote.sh && remote_vmess_agent {srv} {cmd_parts}"
    try:
        proc = await asyncio.create_subprocess_shell(
            cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            executable="/bin/bash"
        )
        stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=30)
        return stdout.decode().strip()
    except asyncio.TimeoutError:
        try: proc.kill()
        except Exception: pass
        return "AGENT-ERR|Timeout"
    except Exception as e:
        return f"AGENT-ERR|{e}"

@router.callback_query(F.data == "adm_vmess_menu")
async def cb_adm_vmess_menu(cb: CallbackQuery):
    uid = cb.from_user.id
    if uid != ADMIN_ID:
        await cb.answer("❌ Akses ditolak"); return
    await cb.answer()
    items = _load_vmess_list()
    total = len(items)
    aktif = sum(1 for i in items if int(i.get("EXPIRED_TS","0") or "0") > int(__import__("time").time()))
    await cb.message.edit_text(
        f"⚡ <b>Kelola VMess</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"📊 Total akun : {total}\n"
        f"✅ Aktif      : {aktif}\n"
        f"━━━━━━━━━━━━━━━━━━━",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[
            [InlineKeyboardButton(text="🗑️ Hapus Akun VMess",  callback_data="adm_vmess_hapus")],
            [InlineKeyboardButton(text="🔄 Renew Akun VMess",  callback_data="adm_vmess_renew")],
            [InlineKeyboardButton(text="🔇 Disable Akun",      callback_data="adm_vmess_disable")],
            [InlineKeyboardButton(text="🔊 Enable Akun",       callback_data="adm_vmess_enable")],
            [InlineKeyboardButton(text="↩ Kembali",            callback_data="m_admin")],
        ])
    )

def _vmess_list_keyboard(prefix: str, back: str = "adm_vmess_menu") -> InlineKeyboardMarkup:
    items = _load_vmess_list()
    b = InlineKeyboardBuilder()
    for i in items:
        uname = i.get("USERNAME","?")
        sname = i.get("SERVER","local")
        exp   = i.get("EXPIRED_DATE","?")
        b.row(InlineKeyboardButton(
            text=f"{uname} [{sname}] — {exp}",
            callback_data=f"{prefix}|{uname}"
        ))
    b.row(InlineKeyboardButton(text="↩ Kembali", callback_data=back))
    return b.as_markup()

@router.callback_query(F.data == "adm_vmess_hapus")
async def cb_adm_vmess_hapus(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID:
        await cb.answer("❌"); return
    await cb.answer()
    await cb.message.edit_text(
        "🗑️ <b>Hapus Akun VMess</b>\n━━━━━━━━━━━━━━━━━━━\nPilih akun yang ingin dihapus:",
        parse_mode="HTML", reply_markup=_vmess_list_keyboard("adm_vdel")
    )

@router.callback_query(F.data.startswith("adm_vdel|"))
async def cb_adm_vdel_exec(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID:
        await cb.answer("❌"); return
    username = cb.data.split("|", 1)[1]
    conf_path = Path(f"{VMESS_DIR_ADMIN}/{username}.conf")
    sname = "local"
    if conf_path.exists():
        for line in conf_path.read_text().splitlines():
            if line.startswith("SERVER="):
                sname = line.split("=",1)[1].strip().strip('"')
    result = await _vmess_agent_admin(sname, "del", username)
    conf_path.unlink(missing_ok=True)
    # Invalidate cache supaya slot langsung terupdate
    sconf = load_server_conf(sname)
    invalidate_account_cache(sconf.get("IP", "") or _local_ip_cached(), "vmess")
    zv_log(f"ADM_VMESS_DEL: {username} server={sname}")
    await cb.answer("✅ Dihapus!")
    await cb.message.edit_text(
        f"✅ Akun VMess <code>{username}</code> berhasil dihapus.\nAgent: {result}",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
            InlineKeyboardButton(text="↩ Kembali", callback_data="adm_vmess_menu")
        ]])
    )

@router.callback_query(F.data == "adm_vmess_renew")
async def cb_adm_vmess_renew(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID:
        await cb.answer("❌"); return
    await cb.answer()
    await cb.message.edit_text(
        "🔄 <b>Renew Akun VMess</b>\n━━━━━━━━━━━━━━━━━━━\nPilih akun:",
        parse_mode="HTML", reply_markup=_vmess_list_keyboard("adm_vrenew")
    )

@router.callback_query(F.data.startswith("adm_vrenew|"))
async def cb_adm_vrenew_pick(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID:
        await cb.answer("❌"); return
    username = cb.data.split("|", 1)[1]
    uid = cb.from_user.id
    state_set(uid, "STATE", "adm_vmess_renew_days")
    state_set(uid, "ADM_VMESS_USER", username)
    await cb.answer()
    await cb.message.edit_text(
        f"🔄 <b>Renew</b> <code>{username}</code>\n━━━━━━━━━━━━━━━━━━━\nKetik jumlah hari perpanjangan:",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
            InlineKeyboardButton(text="❌ Batal", callback_data="adm_vmess_menu")
        ]])
    )

@router.callback_query(F.data == "adm_vmess_disable")
async def cb_adm_vmess_disable(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID:
        await cb.answer("❌"); return
    await cb.answer()
    await cb.message.edit_text(
        "🔇 <b>Disable Akun VMess</b>\n━━━━━━━━━━━━━━━━━━━\nPilih akun:",
        parse_mode="HTML", reply_markup=_vmess_list_keyboard("adm_vdisable")
    )

@router.callback_query(F.data.startswith("adm_vdisable|"))
async def cb_adm_vdisable_exec(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID:
        await cb.answer("❌"); return
    username = cb.data.split("|", 1)[1]
    conf_path = Path(f"{VMESS_DIR_ADMIN}/{username}.conf")
    sname = "local"
    if conf_path.exists():
        for line in conf_path.read_text().splitlines():
            if line.startswith("SERVER="):
                sname = line.split("=",1)[1].strip().strip('"')
    result = await _vmess_agent_admin(sname, "disable", username)
    if conf_path.exists():
        conf_path.rename(f"{VMESS_DIR_ADMIN}/{username}.disabled")
    await cb.answer("✅ Dinonaktifkan!")
    await cb.message.edit_text(
        f"🔇 Akun <code>{username}</code> dinonaktifkan.\nAgent: {result}",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
            InlineKeyboardButton(text="↩ Kembali", callback_data="adm_vmess_menu")
        ]])
    )

@router.callback_query(F.data == "adm_vmess_enable")
async def cb_adm_vmess_enable(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID:
        await cb.answer("❌"); return
    await cb.answer()
    # List dari .disabled
    items = []
    p = Path(VMESS_DIR_ADMIN)
    if p.exists():
        for f in sorted(p.glob("*.disabled")):
            items.append(f.stem)
    if not items:
        await cb.message.edit_text(
            "✅ Tidak ada akun VMess yang dinonaktifkan.",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
                InlineKeyboardButton(text="↩ Kembali", callback_data="adm_vmess_menu")
            ]])
        ); return
    b = InlineKeyboardBuilder()
    for uname in items:
        b.row(InlineKeyboardButton(text=uname, callback_data=f"adm_venable|{uname}"))
    b.row(InlineKeyboardButton(text="↩ Kembali", callback_data="adm_vmess_menu"))
    await cb.message.edit_text(
        "🔊 <b>Enable Akun VMess</b>\n━━━━━━━━━━━━━━━━━━━\nPilih akun:",
        parse_mode="HTML", reply_markup=b.as_markup()
    )

@router.callback_query(F.data.startswith("adm_venable|"))
async def cb_adm_venable_exec(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID:
        await cb.answer("❌"); return
    username = cb.data.split("|", 1)[1]
    disabled_path = Path(f"{VMESS_DIR_ADMIN}/{username}.disabled")
    conf_path     = Path(f"{VMESS_DIR_ADMIN}/{username}.conf")
    sname = "local"
    if disabled_path.exists():
        for line in disabled_path.read_text().splitlines():
            if line.startswith("SERVER="):
                sname = line.split("=",1)[1].strip().strip('"')
        disabled_path.rename(conf_path)
    result = await _vmess_agent_admin(sname, "enable", username)
    await cb.answer("✅ Diaktifkan!")
    await cb.message.edit_text(
        f"🔊 Akun <code>{username}</code> diaktifkan.\nAgent: {result}",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
            InlineKeyboardButton(text="↩ Kembali", callback_data="adm_vmess_menu")
        ]])
    )

# ============================================================
#   AKUN PER SERVER
# ============================================================

_APS_PAGE_SIZE = 6

def _status_label_adm(exp_ts: str, now_ts: int) -> tuple[str, str]:
    """Return (exp_date_str, status_label)"""
    try:
        ts = int(exp_ts)
        from datetime import datetime
        exp_d = datetime.fromtimestamp(ts).strftime("%d %b %Y")
        if ts < now_ts:
            return exp_d, "❌ Expired"
        sisa = ts - now_ts
        if sisa < 86400:
            return exp_d, "⚠️ < 1 hari"
        return exp_d, f"✅ {sisa // 86400} hari"
    except Exception:
        return "-", "❓"

def _collect_server_akun_ssh(server_name: str) -> list[dict]:
    """Kumpulkan semua akun SSH di server tertentu."""
    result = []
    try:
        for f in sorted(Path(ACCOUNT_DIR).glob("*.conf")):
            ac = load_account_conf(f.stem)
            if ac.get("SERVER", "") == server_name and ac.get("USERNAME"):
                result.append(ac)
    except Exception:
        pass
    return result

def _collect_server_akun_vmess(server_name: str) -> list[dict]:
    """Kumpulkan semua akun VMess di server tertentu."""
    result = []
    vmess_dir = f"{BASE_DIR}/accounts/vmess"
    try:
        for f in sorted(Path(vmess_dir).glob("*.conf")):
            from storage import load_vmess_conf
            vc = load_vmess_conf(f.stem)
            if vc.get("SERVER", "") == server_name and vc.get("USERNAME"):
                result.append(vc)
    except Exception:
        pass
    return result

def _kb_server_list_adm() -> tuple[str, InlineKeyboardMarkup]:
    """Keyboard daftar server untuk dipilih."""
    servers = get_server_list()
    b = InlineKeyboardBuilder()
    if not servers:
        b.row(InlineKeyboardButton(text="↩ Kembali", callback_data="m_admin"))
        return "❌ Tidak ada server terdaftar.", b.as_markup()

    text = (
        "🖥 <b>Akun per Server</b>\n"
        "━━━━━━━━━━━━━━━━━━━\n"
        "Pilih server untuk lihat daftar akun:"
    )
    for s in servers:
        name  = s.get("NAME", "")
        label = s.get("TG_SERVER_LABEL") or name
        stype = s.get("TG_SERVER_TYPE", s.get("SERVER_TYPE", "both"))
        icon  = "⚡" if stype == "vmess" else "🔑" if stype == "ssh" else "🌐"
        b.row(InlineKeyboardButton(
            text=f"{icon} {label}",
            callback_data=f"adm_aps_{name}"
        ))
    b.row(InlineKeyboardButton(text="↩ Kembali", callback_data="m_admin"))
    return text, b.as_markup()

def _render_server_akun(server_name: str, proto: str, page: int) -> tuple[str, InlineKeyboardMarkup]:
    """Render halaman akun SSH/VMess di server tertentu."""
    now_ts = int(time.time())
    sc     = load_server_conf(server_name)
    label  = sc.get("TG_SERVER_LABEL") or sc.get("DOMAIN") or server_name

    if proto == "ssh":
        items = _collect_server_akun_ssh(server_name)
        proto_label = "SSH"
        proto_icon  = "🔑"
    else:
        items = _collect_server_akun_vmess(server_name)
        proto_label = "VMess"
        proto_icon  = "⚡"

    total   = len(items)
    n_pages = max(1, (total + _APS_PAGE_SIZE - 1) // _APS_PAGE_SIZE)
    page    = max(0, min(page, n_pages - 1))
    chunk   = items[page * _APS_PAGE_SIZE:(page + 1) * _APS_PAGE_SIZE]

    # Hitung ringkasan
    now_ts_  = int(time.time())
    aktif    = sum(1 for ac in items if not (
        str(ac.get("EXPIRED_TS","")).isdigit() and int(ac.get("EXPIRED_TS",0)) < now_ts_
    ))
    expired  = total - aktif
    trial    = sum(1 for ac in items if ac.get("IS_TRIAL","0") == "1")

    text = (
        f"🖥 <b>{label}</b> — {proto_icon} {proto_label}\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"📊 Total: {total} akun · ✅ {aktif} aktif · ❌ {expired} expired"
        + (f" · 🎁 {trial} trial" if trial > 0 else "") +
        f"\n<i>Hal. {page+1}/{n_pages}</i>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
    )

    for ac in chunk:
        uname   = ac.get("USERNAME", "")
        exp_ts  = ac.get("EXPIRED_TS", "")
        exp_d, status = _status_label_adm(exp_ts, now_ts)
        is_trial = ac.get("IS_TRIAL","0") == "1"
        tipe_icon = "🎁" if is_trial else proto_icon
        text += f"{tipe_icon} <code>{uname}</code> · {status} · {exp_d}\n"

    b = InlineKeyboardBuilder()
    # Toggle SSH / VMess
    other_proto = "vmess" if proto == "ssh" else "ssh"
    other_label = "⚡ VMess" if proto == "ssh" else "🔑 SSH"
    b.row(InlineKeyboardButton(
        text=f"Ganti ke {other_label}",
        callback_data=f"adm_aps_proto_{server_name}_{other_proto}_0"
    ))
    # Navigasi halaman
    nav = []
    if page > 0:
        nav.append(InlineKeyboardButton(text="◀", callback_data=f"adm_aps_proto_{server_name}_{proto}_{page-1}"))
    if page < n_pages - 1:
        nav.append(InlineKeyboardButton(text="▶", callback_data=f"adm_aps_proto_{server_name}_{proto}_{page+1}"))
    if nav:
        b.row(*nav)
    b.row(InlineKeyboardButton(text="↩ Pilih Server", callback_data="adm_akun_per_server"))
    b.row(InlineKeyboardButton(text="🔧 Admin Panel",  callback_data="m_admin"))
    return text, b.as_markup()

# ── Entry: pilih server ──────────────────────────────────────
@router.callback_query(F.data == "adm_akun_per_server")
async def cb_adm_akun_per_server(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID:
        await cb.answer("❌ Akses ditolak"); return
    await cb.answer()
    text, kb = _kb_server_list_adm()
    await cb.message.edit_text(text, parse_mode="HTML", reply_markup=kb)

# ── Pilih server → tampil akun SSH default ───────────────────
@router.callback_query(F.data.startswith("adm_aps_") & ~F.data.startswith("adm_aps_proto_"))
async def cb_adm_aps_server(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID:
        await cb.answer("❌ Akses ditolak"); return
    await cb.answer()
    server_name = cb.data.removeprefix("adm_aps_")
    text, kb = _render_server_akun(server_name, "ssh", 0)
    await cb.message.edit_text(text, parse_mode="HTML", reply_markup=kb)

# ── Ganti proto / navigasi halaman ──────────────────────────
@router.callback_query(F.data.startswith("adm_aps_proto_"))
async def cb_adm_aps_proto(cb: CallbackQuery):
    if cb.from_user.id != ADMIN_ID:
        await cb.answer("❌ Akses ditolak"); return
    await cb.answer()
    # format: adm_aps_proto_{server}_{proto}_{page}
    parts = cb.data.removeprefix("adm_aps_proto_").rsplit("_", 2)
    if len(parts) != 3:
        return
    server_name, proto, page_str = parts
    try:
        page = int(page_str)
    except ValueError:
        page = 0
    text, kb = _render_server_akun(server_name, proto, page)
    await cb.message.edit_text(text, parse_mode="HTML", reply_markup=kb)
