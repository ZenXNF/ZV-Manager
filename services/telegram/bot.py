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


async def _check_restore_flag(bot: Bot) -> None:
    """Cek flag restore dari install.sh, kirim notif ke admin, hapus flag."""
    flag_file = "/etc/zv-manager/.restore_pending"
    if not os.path.exists(flag_file):
        return
    try:
        data = {}
        with open(flag_file) as f:
            for line in f:
                line = line.strip()
                if "=" in line:
                    k, v = line.split("=", 1)
                    data[k.strip()] = v.strip()

        ssh_ok   = data.get("SSH_OK", "?")
        vmess_ok = data.get("VMESS_OK", "?")
        ip       = data.get("IP", "?")
        date     = data.get("DATE", "?")

        msg = (
            "🔄 <b>Restore Otak Selesai</b>
"
            "━━━━━━━━━━━━━━━━━━━
"
            f"✅ SSH      : {ssh_ok} akun di-recreate
"
            f"⚡ VMess    : {vmess_ok} akun di-inject
"
            "🤖 Bot      : aktif
"
            f"🌐 IP VPS   : {ip}
"
            f"📅 Waktu    : {date}
"
            "━━━━━━━━━━━━━━━━━━━
"
            "<i>VPS siap digunakan. Tambah server via Menu Server → Tambah Server.</i>"
        )

        await bot.send_message(ADMIN_ID, msg, parse_mode="HTML")
        os.remove(flag_file)
        log.info("Restore flag: notif terkirim ke admin, flag dihapus")
    except Exception as e:
        log.error(f"Restore flag error: {e}")


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

    # ── Cek flag restore setelah bot siap ─────────────────
    await _check_restore_flag(bot)

    await dp.start_polling(
        bot,
        allowed_updates=["message", "callback_query"],
        drop_pending_updates=True,
    )


if __name__ == "__main__":
    asyncio.run(main())
