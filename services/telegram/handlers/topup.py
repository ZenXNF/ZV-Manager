#!/usr/bin/env python3
# ============================================================
#   ZV-Manager Bot - Topup Handler (Manual via Admin)
#   File: services/telegram/handlers/topup.py
# ============================================================

from aiogram import Router, F
from aiogram.types import CallbackQuery, InlineKeyboardMarkup, InlineKeyboardButton

from storage import saldo_get
from utils import fmt

router = Router()

# ── Entry: tombol Top Up di menu home ────────────────────────
@router.callback_query(F.data == "m_topup")
async def cb_topup_menu(cb: CallbackQuery):
    uid  = cb.from_user.id
    await cb.answer()
    saldo = saldo_get(uid)
    text = (
        f"💳 <b>Top Up Saldo</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"💰 Saldo saat ini : <b>Rp{fmt(saldo)}</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"Top up dilakukan secara manual melalui admin.\n\n"
        f"Silakan hubungi admin untuk mengisi saldo:"
    )
    await cb.message.edit_text(
        text,
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
            InlineKeyboardButton(text="🏠 Menu Utama", callback_data="home")
        ]])
    )
