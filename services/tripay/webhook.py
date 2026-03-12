#!/usr/bin/env python3
# ============================================================
#   ZV-Manager - Tripay Webhook Server
#   Jalankan di port 18099 (diproxy nginx di /tripay/callback)
#   Terima callback dari Tripay saat QRIS dibayar → tambah saldo
# ============================================================

import asyncio
import json
import sys
import os

sys.path.insert(0, "/etc/zv-manager/services/telegram")

from aiohttp import web
from tripay_api import verify_webhook_signature, pending_get, pending_remove

LOG = "/var/log/zv-manager/tripay.log"
BOT_TOKEN = ""

def _log(msg: str):
    import time
    ts = time.strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] {msg}\n"
    try:
        with open(LOG, "a") as f:
            f.write(line)
    except Exception:
        pass
    print(line, end="")

def _load_token():
    global BOT_TOKEN
    try:
        with open("/etc/zv-manager/telegram.conf") as f:
            for line in f:
                if line.startswith("TG_TOKEN="):
                    BOT_TOKEN = line.split("=", 1)[1].strip().strip('"').strip("'")
    except Exception:
        pass

async def _tg_send(chat_id: int, text: str):
    """Kirim pesan Telegram via HTTP sederhana (tanpa aiogram)."""
    import urllib.request
    if not BOT_TOKEN:
        return
    payload = json.dumps({
        "chat_id":    chat_id,
        "text":       text,
        "parse_mode": "HTML",
    }).encode()
    req = urllib.request.Request(
        f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage",
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    try:
        urllib.request.urlopen(req, timeout=10)
    except Exception as e:
        _log(f"TG send error: {e}")

def _add_saldo(uid: int, amount: int) -> int:
    """Tambah saldo user, return saldo baru."""
    saldo_dir = "/etc/zv-manager/accounts/saldo"
    os.makedirs(saldo_dir, exist_ok=True)
    path = f"{saldo_dir}/{uid}.saldo"
    try:
        cur = int(open(path).read().strip().replace("SALDO=", ""))
    except Exception:
        cur = 0
    new = cur + amount
    with open(path, "w") as f:
        f.write(str(new))
    return new

def _fmt(n: int) -> str:
    return f"{n:,}".replace(",", ".")

async def handle_callback(request: web.Request) -> web.Response:
    # ── Baca raw body untuk verifikasi signature ──────────────
    raw_body = await request.read()

    # Tripay kirim signature di header X-Callback-Signature
    received_sig = request.headers.get("X-Callback-Signature", "")
    if not received_sig:
        _log("WEBHOOK: Signature header kosong → reject")
        return web.Response(status=400, text="Missing signature")

    if not verify_webhook_signature(raw_body, received_sig):
        _log(f"WEBHOOK: Signature tidak valid → reject")
        return web.Response(status=403, text="Invalid signature")

    # ── Parse payload ─────────────────────────────────────────
    try:
        data = json.loads(raw_body)
    except Exception:
        _log("WEBHOOK: Body bukan JSON valid")
        return web.Response(status=400, text="Invalid JSON")

    merchant_ref   = data.get("merchant_ref", "")
    payment_status = data.get("status", "")
    paid_amount    = int(data.get("total_amount", 0))

    _log(f"WEBHOOK: ref={merchant_ref} status={payment_status} amount={paid_amount}")

    # ── Hanya proses jika status PAID ─────────────────────────
    if payment_status != "PAID":
        return web.Response(text="OK")

    # ── Cari pending transaction ──────────────────────────────
    pending = pending_get(merchant_ref)
    if not pending:
        _log(f"WEBHOOK: merchant_ref={merchant_ref} tidak ditemukan di pending")
        return web.Response(text="OK")

    uid    = int(pending["uid"])
    amount = int(pending["amount"])  # amount asli (sebelum fee)

    # ── Tambah saldo ──────────────────────────────────────────
    new_saldo = _add_saldo(uid, amount)
    pending_remove(merchant_ref)

    # ── Log transaksi ─────────────────────────────────────────
    import time
    ts = time.strftime("%Y-%m-%d %H:%M:%S")
    try:
        with open("/var/log/zv-manager/install.log", "a") as f:
            f.write(f"[{ts}] TOPUP: uid={uid} amount={amount} ref={merchant_ref}\n")
    except Exception:
        pass

    _log(f"TOPUP OK: uid={uid} +Rp{_fmt(amount)} → saldo Rp{_fmt(new_saldo)}")

    # ── Notif ke user via Telegram ────────────────────────────
    text = (
        f"✅ <b>Top Up Berhasil!</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"💰 Top Up   : <b>Rp{_fmt(amount)}</b>\n"
        f"💳 Saldo    : <b>Rp{_fmt(new_saldo)}</b>\n"
        f"🧾 Ref      : <code>{merchant_ref}</code>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"Saldo kamu sudah bertambah dan siap digunakan! 🎉"
    )
    await _tg_send(uid, text)

    return web.Response(text="OK")

async def handle_health(request: web.Request) -> web.Response:
    return web.Response(text="ZV Tripay Webhook OK")

def main():
    _load_token()
    _log("ZV Tripay Webhook Server starting on port 18099...")

    app = web.Application()
    app.router.add_post("/tripay/callback", handle_callback)
    app.router.add_get("/tripay/health",    handle_health)

    web.run_app(app, host="127.0.0.1", port=18099, access_log=None)

if __name__ == "__main__":
    main()
