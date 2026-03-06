#!/usr/bin/env python3
# ============================================================
#   ZV-Manager - Telegram Bot Entry Point
#   Python 3 + aiogram 3.x
#
#   Struktur modul:
#     config.py      — konstanta, paths, TOKEN, ADMIN_ID
#     utils.py       — zv_log, fmt, backup_realtime, dll
#     storage.py     — saldo, state, conf file, server, akun
#     keyboards.py   — semua kb_* functions
#     texts.py       — semua text_* message builders
#     middleware.py  — RateLimitMiddleware
#     handlers/
#       user.py      — /start, home, buat, trial, akun, perpanjang, bw
#       admin.py     — admin panel, broadcast, topup, hapus, cek
#       messages.py  — state machine handle_message
# ============================================================

import asyncio
import sys
import os

# Tambahkan direktori ini ke path supaya import relatif berfungsi
sys.path.insert(0, os.path.dirname(__file__))

from aiogram import Bot, Dispatcher

from config import TOKEN, ADMIN_ID, log
from middleware import RateLimitMiddleware
from handlers import user, admin, messages


async def main():
    if not TOKEN:
        log.error("TG_TOKEN tidak ditemukan di telegram.conf!")
        return

    bot = Bot(token=TOKEN)
    dp  = Dispatcher()

    # ── Daftarkan middleware ───────────────────────────────
    dp.message.middleware(RateLimitMiddleware())
    dp.callback_query.middleware(RateLimitMiddleware())

    # ── Include semua router ───────────────────────────────
    # Urutan penting: user & admin dulu, messages terakhir
    # (messages pakai @router.message() tanpa filter — harus paling akhir)
    dp.include_router(user.router)
    dp.include_router(admin.router)
    dp.include_router(messages.router)

    log.info(f"ZV-Manager Bot starting... Admin: {ADMIN_ID}")

    await dp.start_polling(
        bot,
        allowed_updates=["message", "callback_query"],
        drop_pending_updates=True,
    )


if __name__ == "__main__":
    asyncio.run(main())
