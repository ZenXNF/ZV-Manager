#!/usr/bin/env python3
# ============================================================
#   ZV-Manager Bot - Message Handler (State Machine)
#   Handle semua input teks user berdasarkan state
# ============================================================

import re
import subprocess
from pathlib import Path
from aiogram import Router
from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup, Message

from config import ADMIN_ID, VMESS_DIR, log
from keyboards import kb_confirm, kb_home_btn
from storage import (
    load_vmess_conf, save_vmess_conf,
    load_tg_server_conf, load_user_info,
    saldo_add, saldo_get, saldo_set,
    state_clear, state_get, state_set, zv_log as _zv_log
)
from utils import fmt, zv_log
from handlers.admin import do_broadcast, do_broadcast_stiker, do_broadcast_server, do_cek_user, do_hapus_akun

router = Router()


@router.message()
async def handle_message(msg: Message):
    uid   = msg.from_user.id
    text  = msg.text or ""

    # Jangan intercept command — biarkan handler Command() di router lain yang proses
    if text.startswith("/"):
        return

    state = state_get(uid, "STATE")
    if not state:
        return

    try:
        await _handle_state(msg, uid, text, state)
    except Exception as e:
        log.error(f"handle_message error uid={uid} state={state} err={e}", exc_info=True)
        zv_log(f"MSG_ERROR: uid={uid} state={state} err={e}")
        state_clear(uid)
        try:
            await msg.answer(
                "❌ Terjadi error. Silakan mulai ulang dari /start.",
                reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
                    InlineKeyboardButton(text="🏠 Menu Utama", callback_data="home")
                ]])
            )
        except Exception:
            pass


async def _handle_state(msg: Message, uid: int, text: str, state: str):
    # ── Broadcast teks ─────────────────────────────────────
    if state == "broadcast_msg":
        if uid != ADMIN_ID:
            state_clear(uid); return
        if not text:
            await msg.answer("❌ Pesan tidak boleh kosong. Ketik pesan teks:"); return
        state_clear(uid)
        await do_broadcast(msg, text)
        return

    # ── Broadcast per server ────────────────────────────────
    if state == "broadcast_server_msg":
        if uid != ADMIN_ID:
            state_clear(uid); return
        if not text:
            await msg.answer("❌ Pesan tidak boleh kosong. Ketik pesan teks:"); return
        server_name = state_get(uid, "BC_SERVER")
        state_clear(uid)
        await do_broadcast_server(msg, text, server_name)
        return

    # ── Broadcast stiker ───────────────────────────────────
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

    # ── Admin: topup uid ───────────────────────────────────
    if state == "adm_topup_uid":
        if uid != ADMIN_ID:
            state_clear(uid); return
        if not re.match(r"^\d{5,15}$", text):
            await msg.answer("❌ User ID tidak valid. Harus angka 5-15 digit.\n\nKetik User ID:"); return
        state_set(uid, "ADM_TARGET", text)
        state_set(uid, "STATE", "adm_topup_amount")
        t_info  = load_user_info(int(text))
        t_name  = t_info.get("NAME", "(belum terdaftar)")
        t_saldo = saldo_get(int(text))
        await msg.answer(
            f"💰 <b>Top Up Saldo</b>\n━━━━━━━━━━━━━━━━━━━\n"
            f"🆔 User ID : <code>{text}</code>\n"
            f"👤 Nama    : {t_name}\n"
            f"💰 Saldo   : Rp{fmt(t_saldo)}\n"
            f"━━━━━━━━━━━━━━━━━━━\n"
            f"Ketik <b>jumlah</b> top up:\nContoh: <code>50000</code>",
            parse_mode="HTML"
        ); return

    # ── Admin: topup amount ────────────────────────────────
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
            f"➕ Ditambah : Rp{fmt(amount)}\n"
            f"💰 Saldo    : Rp{fmt(cur)} → Rp{fmt(new)}\n"
            f"━━━━━━━━━━━━━━━━━━━",
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
                InlineKeyboardButton(text="💰 Top Up Lagi", callback_data="adm_topup"),
                InlineKeyboardButton(text="↩ Admin Panel", callback_data="m_admin")
            ]])
        )
        try:
            await msg.bot.send_message(target,
                f"💰 <b>Saldo Kamu Bertambah!</b>\n━━━━━━━━━━━━━━━━━━━\n"
                f"💳 Ditambah : Rp{fmt(amount)}\n💰 Saldo    : Rp{fmt(new)}\n"
                f"━━━━━━━━━━━━━━━━━━━\nTerima kasih sudah top up! 🙏",
                parse_mode="HTML", reply_markup=kb_home_btn())
        except Exception: pass
        return

    # ── Admin: kurangi uid ─────────────────────────────────
    if state == "adm_kurangi_uid":
        if uid != ADMIN_ID:
            state_clear(uid); return
        if not re.match(r"^\d{5,15}$", text):
            await msg.answer("❌ User ID tidak valid.\n\nKetik User ID:"); return
        state_set(uid, "ADM_TARGET", text)
        state_set(uid, "STATE", "adm_kurangi_amount")
        t_info  = load_user_info(int(text))
        t_name  = t_info.get("NAME", "(belum terdaftar)")
        t_saldo = saldo_get(int(text))
        await msg.answer(
            f"➖ <b>Kurangi Saldo</b>\n━━━━━━━━━━━━━━━━━━━\n"
            f"🆔 User ID : <code>{text}</code>\n"
            f"👤 Nama    : {t_name}\n"
            f"💰 Saldo   : Rp{fmt(t_saldo)}\n"
            f"━━━━━━━━━━━━━━━━━━━\n"
            f"Ketik <b>jumlah</b> yang dikurangi:\nContoh: <code>5000</code>",
            parse_mode="HTML"
        ); return

    # ── Admin: kurangi amount ──────────────────────────────
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
            await msg.bot.send_message(target,
                f"⚠️ <b>Saldo Kamu Berubah</b>\n━━━━━━━━━━━━━━━━━━━\n"
                f"➖ Dikurangi : Rp{fmt(amount)}\n💰 Saldo    : Rp{fmt(new)}\n"
                f"━━━━━━━━━━━━━━━━━━━\nHubungi admin jika ada pertanyaan.",
                parse_mode="HTML", reply_markup=kb_home_btn())
        except Exception: pass
        return

    # ── Admin: hapus akun ──────────────────────────────────
    if state == "adm_hapus_username":
        if uid != ADMIN_ID:
            state_clear(uid); return
        if not re.match(r"^[a-zA-Z0-9]{3,20}$", text):
            await msg.answer("❌ Username tidak valid.\n\nKetik username:"); return
        state_clear(uid)
        await do_hapus_akun(msg, text, uid)
        return

    # ── Admin: renew VMess ─────────────────────────────────
    if state == "adm_vmess_renew_days":
        if uid != ADMIN_ID:
            state_clear(uid); return
        if not re.match(r"^\d+$", text) or int(text) < 1:
            await msg.answer("❌ Jumlah hari tidak valid.\n\nKetik jumlah hari:"); return
        days = int(text)
        username = state_get(uid, "ADM_VMESS_USER")
        state_clear(uid)
        conf_path = Path(f"/etc/zv-manager/accounts/vmess/{username}.conf")
        sname = "local"
        if conf_path.exists():
            for line in conf_path.read_text().splitlines():
                if line.startswith("SERVER="):
                    sname = line.split("=",1)[1].strip().strip('"')
        result = subprocess.run(
            ["/bin/bash", "-c",
             f"source /etc/zv-manager/utils/remote.sh && remote_vmess_agent {sname} renew {username} {days}"],
            capture_output=True, text=True
        ).stdout.strip()
        if result.startswith("RENEW-OK"):
            new_exp = result.split("|")[2] if "|" in result else "?"
            # Update conf lokal
            if conf_path.exists():
                import time as _time
                try:
                    new_ts = int(__import__("datetime").datetime.strptime(new_exp, "%Y-%m-%d").timestamp())
                except Exception:
                    new_ts = 0
                c = conf_path.read_text()
                c = re.sub(r"^EXPIRED_DATE=.*", f'EXPIRED_DATE="{new_exp}"', c, flags=re.M)
                c = re.sub(r"^EXPIRED_TS=.*",   f'EXPIRED_TS="{new_ts}"',   c, flags=re.M)
                conf_path.write_text(c)
            await msg.answer(
                f"✅ <b>VMess Diperpanjang</b>\n"
                f"━━━━━━━━━━━━━━━━━━━\n"
                f"👤 Akun   : <code>{username}</code>\n"
                f"📅 Expired: {new_exp}\n"
                f"⏱️ Tambah : {days} hari",
                parse_mode="HTML"
            )
        else:
            await msg.answer(f"❌ Gagal renew: {result}")
        return

    # ── Admin: cek user ────────────────────────────────────
    if state == "adm_cek_uid":
        if uid != ADMIN_ID:
            state_clear(uid); return
        if not re.match(r"^\d{5,15}$", text):
            await msg.answer("❌ User ID tidak valid.\n\nKetik User ID:"); return
        state_clear(uid)
        await do_cek_user(msg, int(text))
        return

    # ── Buat akun: username ────────────────────────────────
    if state == "await_user":
        if not re.match(r"^[a-zA-Z0-9]{3,20}$", text):
            await msg.answer("❌ Username tidak valid. Huruf dan angka, 3-20 karakter.\n\nKetik username:"); return
        if subprocess.run(["id", text], capture_output=True).returncode == 0:
            await msg.answer(f"❌ Username <b>{text}</b> sudah digunakan.\n\nKetik username lain:",
                             parse_mode="HTML"); return
        state_set(uid, "USERNAME", text)
        state_set(uid, "STATE", "await_pass")
        await msg.answer("Ketik password:\n(Minimal 4 karakter, boleh huruf besar/kecil dan angka)")
        return

    # ── Buat akun: password ────────────────────────────────
    if state == "await_pass":
        if len(text) < 4:
            await msg.answer("❌ Password minimal 4 karakter.\n\nKetik password:"); return
        state_set(uid, "PASSWORD", text)
        state_set(uid, "STATE", "await_days")
        await msg.answer("Berapa hari masa aktif? (1-365)")
        return

    # ── Buat akun: days ───────────────────────────────────
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
        hh          = f"Rp{fmt(harga)}/hari" if harga > 0 else "Gratis"
        bw_per_hari = int(tg.get("TG_BW_PER_HARI", "5") or "5")
        bw_total_gb = days * bw_per_hari
        bw_line     = f"\n📶 Bandwidth      : {bw_total_gb} GB" if bw_per_hari > 0 else ""
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
            parse_mode="HTML", reply_markup=kb_confirm("konfirm")
        )
        return


    # ── VMess: input durasi ────────────────────────────────
    if state == "vmess_await_username":
        uname = text.strip().lower()
        # Validasi: 4-20 char, hanya huruf kecil, angka, strip
        if not re.match(r'^[a-z0-9][a-z0-9\-]{2,18}[a-z0-9]$', uname):
            await msg.answer(
                "❌ Username tidak valid!\n\n"
                "• 4–20 karakter\n"
                "• Hanya huruf kecil, angka, strip (-)\n"
                "• Tidak boleh mulai/akhir dengan strip\n"
                "• Contoh: <code>budi-vip</code>",
                parse_mode="HTML"
            ); return
        # Cek sudah ada
        from pathlib import Path as _P
        if _P(f"/etc/zv-manager/accounts/vmess/{uname}.conf").exists():
            await msg.answer(f"❌ Username <code>{uname}</code> sudah dipakai, coba yang lain.", parse_mode="HTML"); return
        sname = state_get(uid, "SERVER")
        tg    = load_tg_server_conf(sname)
        harga = int(tg.get("TG_HARGA_VMESS_HARI","0") or tg.get("TG_HARGA_HARI","0"))
        hh    = f"Rp{fmt(harga)}/hari" if harga > 0 else "Gratis"
        state_set(uid, "USERNAME_VMESS", uname)
        state_set(uid, "STATE", "vmess_await_days")
        await msg.answer(
            f"⚡ <b>Buat Akun VMess</b>\n"
            f"━━━━━━━━━━━━━━━━━━━\n"
            f"👤 Username : <code>{uname}</code>\n"
            f"🌐 Server   : {tg['TG_SERVER_LABEL']}\n"
            f"💰 Harga    : {hh}\n"
            f"━━━━━━━━━━━━━━━━━━━\n"
            f"Berapa hari? (1–365)",
            parse_mode="HTML"
        )
        return

    if state == "vmess_await_days":
        if not text.isdigit() or not (1 <= int(text) <= 365):
            await msg.answer("❌ Masukkan angka antara 1 sampai 365."); return
        days  = int(text)
        sname = state_get(uid, "SERVER")
        tg    = load_tg_server_conf(sname)
        harga = int(tg.get("TG_HARGA_VMESS_HARI","0") or tg.get("TG_HARGA_HARI","0"))
        total = harga * days
        saldo = saldo_get(uid)
        state_set(uid, "DAYS",  str(days))
        state_set(uid, "STATE", "vmess_confirm")
        hh = f"Rp{fmt(harga)}/hari" if harga > 0 else "Gratis"
        if harga > 0 and saldo < total:
            await msg.answer(
                f"⚡ <b>Konfirmasi VMess</b>\n━━━━━━━━━━━━━━━━━━━\n"
                f"🌐 Server  : {tg['TG_SERVER_LABEL']}\n"
                f"📅 Durasi  : {days} hari\n"
                f"💰 Harga   : {hh}\n"
                f"💸 Total   : Rp{fmt(total)}\n"
                f"💳 Saldo   : Rp{fmt(saldo)}\n"
                f"❌ Kurang  : Rp{fmt(total - saldo)}\n"
                f"━━━━━━━━━━━━━━━━━━━\nSaldo tidak cukup. Hubungi admin.",
                parse_mode="HTML"
            )
            state_clear(uid); return
        saldo_line = f"\n💳 Saldo   : Rp{fmt(saldo)}" if harga > 0 else ""
        await msg.answer(
            f"⚡ <b>Konfirmasi Buat VMess</b>\n━━━━━━━━━━━━━━━━━━━\n"
            f"🌐 Server  : {tg['TG_SERVER_LABEL']}\n"
            f"📅 Durasi  : {days} hari\n"
            f"💰 Harga   : {hh}\n"
            f"💸 Total   : Rp{fmt(total)}{saldo_line}\n"
            f"━━━━━━━━━━━━━━━━━━━\nLanjutkan?",
            parse_mode="HTML",
            reply_markup=__import__('aiogram').types.InlineKeyboardMarkup(inline_keyboard=[[
                __import__('aiogram').types.InlineKeyboardButton(text="✅ Konfirmasi", callback_data="konfirm_vmess"),
                __import__('aiogram').types.InlineKeyboardButton(text="❌ Batal",      callback_data="home")
            ]])
        )
        return

    # ── Perpanjang VMess: days ─────────────────────────────
    if state == "vrenew_days":
        if not text.isdigit() or not (1 <= int(text) <= 365):
            await msg.answer("❌ Masukkan angka antara 1 sampai 365.\n\nBerapa hari perpanjang VMess?"); return
        days     = int(text)
        sname    = state_get(uid, "SERVER")
        username = state_get(uid, "USERNAME")
        tg       = load_tg_server_conf(sname)
        harga    = int(tg.get("TG_HARGA_VMESS_HARI","0") or tg.get("TG_HARGA_HARI","0"))
        total    = harga * days
        saldo    = saldo_get(uid)
        state_set(uid, "DAYS",  str(days))
        state_set(uid, "STATE", "vrenew_confirm")
        hh = f"Rp{fmt(harga)}/hari" if harga > 0 else "Gratis"
        if harga > 0 and saldo < total:
            await msg.answer(
                f"⚡ <b>Perpanjang VMess</b>\n━━━━━━━━━━━━━━━━━━━\n"
                f"👤 Username : <code>{username}</code>\n"
                f"📅 Tambah   : {days} hari\n"
                f"💸 Total    : Rp{fmt(total)}\n"
                f"💳 Saldo    : Rp{fmt(saldo)}\n"
                f"❌ Kurang   : Rp{fmt(total - saldo)}\n"
                f"━━━━━━━━━━━━━━━━━━━\nSaldo tidak cukup. Hubungi admin.",
                parse_mode="HTML"
            )
            state_clear(uid); return
        saldo_line = f"\n💳 Saldo    : Rp{fmt(saldo)}" if harga > 0 else ""
        await msg.answer(
            f"⚡ <b>Konfirmasi Perpanjang VMess</b>\n━━━━━━━━━━━━━━━━━━━\n"
            f"👤 Username : <code>{username}</code>\n"
            f"🌐 Server   : {tg['TG_SERVER_LABEL']}\n"
            f"📅 Tambah   : {days} hari\n"
            f"💰 Harga    : {hh}\n"
            f"💸 Total    : Rp{fmt(total)}{saldo_line}\n"
            f"━━━━━━━━━━━━━━━━━━━\nLanjutkan?",
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
                InlineKeyboardButton(text="✅ Konfirmasi", callback_data="konfirm_vrenew"),
                InlineKeyboardButton(text="❌ Batal",      callback_data="home")
            ]])
        )
        return

    # ── Perpanjang: days ───────────────────────────────────
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
            parse_mode="HTML", reply_markup=kb_confirm("konfirm_renew")
        )
        return
