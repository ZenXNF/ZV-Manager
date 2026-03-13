#!/usr/bin/env python3
# ============================================================
#   ZV-Manager Bot - Topup Handler (Tripay QRIS)
#   File: services/telegram/handlers/topup.py
# ============================================================

import time
from aiogram import Router, F
from aiogram.types import (
    CallbackQuery,
    InlineKeyboardMarkup, InlineKeyboardButton,
)
from aiogram.utils.keyboard import InlineKeyboardBuilder

from config import BASE_DIR
from storage import saldo_get
from utils import fmt

router = Router()

# ── Load preset nominal dari tripay.conf ─────────────────────
def _load_preset() -> list[int]:
    try:
        with open(f"{BASE_DIR}/tripay.conf") as f:
            for line in f:
                if line.startswith("TRIPAY_NOMINAL_PRESET="):
                    val = line.split("=", 1)[1].strip().strip('"').strip("'")
                    return [int(x.strip()) for x in val.split(",") if x.strip().isdigit()]
    except Exception:
        pass
    return [10000, 20000, 50000, 100000]

def _is_tripay_configured() -> bool:
    try:
        with open(f"{BASE_DIR}/tripay.conf") as f:
            conf = {}
            for line in f:
                if "=" in line and not line.startswith("#"):
                    k, _, v = line.partition("=")
                    conf[k.strip()] = v.strip().strip('"').strip("'")
        return bool(
            conf.get("TRIPAY_API_KEY") and
            conf.get("TRIPAY_PRIVATE_KEY") and
            conf.get("TRIPAY_MERCHANT_CODE")
        )
    except Exception:
        return False

# ── Keyboard pilih nominal ────────────────────────────────────
def _kb_pilih_nominal() -> InlineKeyboardMarkup:
    presets = _load_preset()
    b = InlineKeyboardBuilder()
    # Susun 2 per baris
    row = []
    for nominal in presets:
        row.append(InlineKeyboardButton(
            text=f"Rp{fmt(nominal)}",
            callback_data=f"topup_nominal_{nominal}"
        ))
        if len(row) == 2:
            b.row(*row)
            row = []
    if row:
        b.row(*row)
    b.row(InlineKeyboardButton(text="✏️ Nominal Lain", callback_data="topup_custom"))
    b.row(InlineKeyboardButton(text="↩ Kembali", callback_data="home"))
    return b.as_markup()

def _kb_cancel(ref: str = "") -> InlineKeyboardMarkup:
    b = InlineKeyboardBuilder()
    b.row(InlineKeyboardButton(text="❌ Batalkan", callback_data=f"topup_cancel_{ref}"))
    b.row(InlineKeyboardButton(text="🏠 Menu Utama", callback_data="home"))
    return b.as_markup()

# ── Entry: tombol Top Up di menu home ────────────────────────
@router.callback_query(F.data == "m_topup")
async def cb_topup_menu(cb: CallbackQuery):
    uid = cb.from_user.id
    await cb.answer()

    if not _is_tripay_configured():
        await cb.message.edit_text(
            "⚠️ <b>Top Up belum tersedia</b>\n\n"
            "Fitur top up sedang dalam proses setup.\n"
            "Hubungi admin untuk mengisi saldo secara manual.",
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
                InlineKeyboardButton(text="🏠 Menu Utama", callback_data="home")
            ]])
        )
        return

    saldo = saldo_get(uid)
    text = (
        f"💳 <b>Top Up Saldo</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"💰 Saldo saat ini : <b>Rp{fmt(saldo)}</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"Pilih nominal top up:"
    )
    await cb.message.edit_text(text, parse_mode="HTML", reply_markup=_kb_pilih_nominal())

# ── Pilih nominal preset ──────────────────────────────────────
@router.callback_query(F.data.startswith("topup_nominal_"))
async def cb_topup_nominal(cb: CallbackQuery):
    uid = cb.from_user.id
    await cb.answer()
    try:
        amount = int(cb.data.removeprefix("topup_nominal_"))
    except ValueError:
        return

    await _process_topup(cb.message, uid, amount, edit=True)

# ── Nominal custom (ketik manual) ─────────────────────────────
@router.callback_query(F.data == "topup_custom")
async def cb_topup_custom(cb: CallbackQuery):
    from storage import state_set
    await cb.answer()
    await cb.message.edit_text(
        "✏️ <b>Masukkan Nominal Top Up</b>\n"
        "━━━━━━━━━━━━━━━━━━━\n"
        "Ketik jumlah yang ingin kamu top up.\n"
        "<i>Contoh: 75000</i>\n\n"
        "Minimal top up: <b>Rp10.000</b>",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
            InlineKeyboardButton(text="↩ Kembali", callback_data="m_topup")
        ]])
    )
    # Set state via state machine (bukan file manual)
    state_set(cb.from_user.id, "STATE", "topup_custom_nominal")

# ── Core: buat transaksi QRIS dan kirim ke user ───────────────
async def _process_topup(target, uid: int, amount: int, edit: bool = False):
    from tripay_api import create_qris_transaction, calc_fee, FEE_CUSTOMER

    # Baca domain
    try:
        domain = open(f"{BASE_DIR}/domain").read().strip()
    except Exception:
        domain = "localhost"

    # Loading message
    loading_text = "⏳ Membuat transaksi QRIS...\nMohon tunggu sebentar."
    if edit:
        sent = await target.edit_text(loading_text)
    else:
        sent = await target.answer(loading_text)

    # Buat transaksi
    result = create_qris_transaction(uid, amount, domain)

    if not result.get("success"):
        err_msg = result.get("message", "Terjadi kesalahan")
        await sent.edit_text(
            f"❌ <b>Gagal membuat transaksi</b>\n\n{err_msg}",
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
                InlineKeyboardButton(text="🔄 Coba Lagi", callback_data="m_topup"),
                InlineKeyboardButton(text="🏠 Menu Utama", callback_data="home")
            ]])
        )
        return

    ref         = result["merchant_ref"]
    pay_amount  = result["pay_amount"]
    qr_url      = result["qr_url"]
    expired_ts  = result["expired_time"]
    fee         = result["fee"]
    exp_str     = time.strftime("%H:%M", time.localtime(expired_ts))

    fee_line = f"\n💸 Biaya QRIS : <b>Rp{fmt(fee)}</b>" if FEE_CUSTOMER and fee > 0 else ""
    total_line = f"\n💳 Total Bayar: <b>Rp{fmt(pay_amount)}</b>" if FEE_CUSTOMER else ""

    text = (
        f"🧾 <b>Transaksi Top Up QRIS</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"💰 Top Up   : <b>Rp{fmt(amount)}</b>"
        f"{fee_line}"
        f"{total_line}\n"
        f"🧾 Ref      : <code>{ref}</code>\n"
        f"⏰ Berlaku  : sampai pukul <b>{exp_str}</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"Scan QR Code di bawah menggunakan aplikasi e-wallet atau mobile banking.\n\n"
        f"✅ Saldo akan otomatis bertambah setelah pembayaran berhasil."
    )

    # Kirim QR image + teks
    await sent.delete()
    if qr_url:
        try:
            await target.bot.send_photo(
                uid,
                photo=qr_url,
                caption=text,
                parse_mode="HTML",
                reply_markup=_kb_cancel(ref)
            )
            return
        except Exception:
            pass

    # Fallback: teks saja + link QR
    text += f"\n\n🔗 <a href=\"{qr_url}\">Buka QR Code</a>" if qr_url else ""
    await target.bot.send_message(uid, text, parse_mode="HTML", reply_markup=_kb_cancel(ref))

# ── Batalkan transaksi ────────────────────────────────────────
@router.callback_query(F.data.startswith("topup_cancel_"))
async def cb_topup_cancel(cb: CallbackQuery):
    uid = cb.from_user.id
    ref = cb.data.removeprefix("topup_cancel_")
    await cb.answer()

    # Hapus dari pending
    try:
        from tripay_api import pending_get, pending_remove
        pending = pending_get(ref)
        if pending and int(pending.get("uid", 0)) == uid:
            pending_remove(ref)
    except Exception:
        pass

    await cb.message.edit_caption(
        "❌ Transaksi dibatalkan.",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
            InlineKeyboardButton(text="🔄 Top Up Lagi", callback_data="m_topup"),
            InlineKeyboardButton(text="🏠 Menu Utama",  callback_data="home")
        ]])
    )
