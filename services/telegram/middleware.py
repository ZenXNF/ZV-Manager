#!/usr/bin/env python3
# ============================================================
#   ZV-Manager Bot - Rate Limit Middleware
# ============================================================

import time
from collections import deque

from aiogram import BaseMiddleware
from aiogram.types import TelegramObject

from config import ADMIN_ID

# ── Throttle sederhana untuk spam klik ──────────────────────
_last_action: dict[int, float] = {}

def _throttle(uid: int, seconds: float = 0.8) -> bool:
    """Return True kalau boleh jalan, False kalau masih cooldown."""
    now  = time.time()
    last = _last_action.get(uid, 0.0)
    if now - last < seconds:
        return False
    _last_action[uid] = now
    return True

# ── Sliding window rate limiter ──────────────────────────────
RL_MAX_CALLS = 12    # maks request per window
RL_WINDOW    = 20    # detik sliding window
RL_MUTE_SEC  = 30    # cooldown pesan peringatan

_rl_store:     dict[int, deque] = {}
_rl_warned_at: dict[int, float] = {}

def _rl_is_limited(uid: int) -> bool:
    if uid == ADMIN_ID:
        return False
    now = time.time()
    q   = _rl_store.setdefault(uid, deque())
    while q and now - q[0] > RL_WINDOW:
        q.popleft()
    if len(q) >= RL_MAX_CALLS:
        return True
    q.append(now)
    return False

def _rl_should_warn(uid: int) -> bool:
    now  = time.time()
    last = _rl_warned_at.get(uid, 0.0)
    if now - last > RL_MUTE_SEC:
        _rl_warned_at[uid] = now
        return True
    return False


class RateLimitMiddleware(BaseMiddleware):
    """Middleware rate limiting untuk semua message & callback_query."""
    async def __call__(self, handler, event: TelegramObject, data: dict):
        uid = None
        if hasattr(event, "from_user") and event.from_user:
            uid = event.from_user.id

        if uid and _rl_is_limited(uid):
            if _rl_should_warn(uid):
                try:
                    if hasattr(event, "answer") and callable(event.answer):
                        # CallbackQuery
                        await event.answer(
                            "⚠️ Terlalu cepat! Tunggu sebentar.",
                            show_alert=True
                        )
                    elif hasattr(event, "reply"):
                        # Message
                        await event.reply(
                            f"⚠️ Kamu terlalu cepat mengirim perintah.\n"
                            f"Tunggu {RL_MUTE_SEC} detik sebelum mencoba lagi."
                        )
                except Exception:
                    pass
            return  # drop, tidak lanjut ke handler

        return await handler(event, data)
