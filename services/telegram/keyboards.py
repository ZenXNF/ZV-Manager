#!/usr/bin/env python3
# ============================================================
#   ZV-Manager Bot - Keyboards (Inline Markup)
# ============================================================

from aiogram.types import InlineKeyboardMarkup, InlineKeyboardButton
from aiogram.utils.keyboard import InlineKeyboardBuilder

from config import ADMIN_ID
from storage import get_server_list, get_server_list_by_type, saldo_get, load_tg_server_conf


def kb_home() -> InlineKeyboardMarkup:
    b = InlineKeyboardBuilder()
    b.row(
        InlineKeyboardButton(text="🛒 Beli Akun",      callback_data="m_buat"),
        InlineKeyboardButton(text="🎁 Coba Gratis",    callback_data="m_trial")
    )
    b.row(
        InlineKeyboardButton(text="📋 Akun Saya",      callback_data="m_akun"),
        InlineKeyboardButton(text="💰 Riwayat Saldo",  callback_data="m_saldo_history")
    )
    return b.as_markup()

def kb_home_admin() -> InlineKeyboardMarkup:
    b = InlineKeyboardBuilder()
    b.row(
        InlineKeyboardButton(text="🛒 Beli Akun",      callback_data="m_buat"),
        InlineKeyboardButton(text="🎁 Coba Gratis",    callback_data="m_trial")
    )
    b.row(
        InlineKeyboardButton(text="📋 Akun Saya",      callback_data="m_akun"),
        InlineKeyboardButton(text="💰 Riwayat Saldo",  callback_data="m_saldo_history")
    )
    b.row(
        InlineKeyboardButton(text="🔧 Admin",          callback_data="m_admin")
    )
    return b.as_markup()

def kb_for_user(uid: int) -> InlineKeyboardMarkup:
    return kb_home_admin() if uid == ADMIN_ID else kb_home()

def kb_after_buy(proto: str = "ssh") -> InlineKeyboardMarkup:
    """Tombol setelah beli/trial berhasil."""
    b = InlineKeyboardBuilder()
    b.row(
        InlineKeyboardButton(text="📋 Akun Saya", callback_data="m_akun"),
        InlineKeyboardButton(text="🛒 Beli Lagi",  callback_data="m_buat")
    )
    b.row(InlineKeyboardButton(text="🏠 Menu Utama", callback_data="home"))
    return b.as_markup()

def kb_home_btn() -> InlineKeyboardMarkup:
    b = InlineKeyboardBuilder()
    b.button(text="🏠 Menu Utama", callback_data="home")
    return b.as_markup()

def kb_back(cb: str = "home") -> InlineKeyboardMarkup:
    b = InlineKeyboardBuilder()
    b.button(text="↩ Kembali", callback_data=cb)
    return b.as_markup()

def kb_confirm(cb_yes: str) -> InlineKeyboardMarkup:
    b = InlineKeyboardBuilder()
    b.row(
        InlineKeyboardButton(text="✅ Konfirmasi", callback_data=cb_yes),
        InlineKeyboardButton(text="❌ Batal",      callback_data="home")
    )
    return b.as_markup()

def kb_server_list(prefix: str, page: int = 0, back_cb: str = "m_buat") -> InlineKeyboardMarkup:
    servers  = get_server_list_by_type("ssh")
    per_page = 6
    start    = page * per_page
    chunk    = servers[start:start + per_page]
    b        = InlineKeyboardBuilder()
    for s in chunk:
        name = s.get("NAME", "")
        b.button(text=name, callback_data=f"{prefix}_{name}")
    b.adjust(2)
    nav = []
    if page > 0:
        nav.append(InlineKeyboardButton(text="◀ Sebelumnya", callback_data=f"page_{prefix}_{page-1}"))
    if start + per_page < len(servers):
        nav.append(InlineKeyboardButton(text="Berikutnya ▶", callback_data=f"page_{prefix}_{page+1}"))
    if nav:
        b.row(*nav)
    b.row(InlineKeyboardButton(text="↩ Kembali", callback_data=back_cb))
    return b.as_markup()

def kb_admin_panel() -> InlineKeyboardMarkup:
    b = InlineKeyboardBuilder()
    b.row(
        InlineKeyboardButton(text="💰 Top Up Saldo",     callback_data="adm_topup"),
        InlineKeyboardButton(text="➖ Kurangi Saldo",    callback_data="adm_kurangi")
    )
    b.row(
        InlineKeyboardButton(text="🗑️ Hapus Akun",       callback_data="adm_hapus_akun"),
        InlineKeyboardButton(text="📢 Broadcast",        callback_data="m_broadcast")
    )
    b.row(
        InlineKeyboardButton(text="👥 Daftar User",      callback_data="adm_daftar_user"),
        InlineKeyboardButton(text="🔍 Cek User",         callback_data="adm_cek_user")
    )
    b.row(
        InlineKeyboardButton(text="📊 History Transaksi", callback_data="adm_history"),
        InlineKeyboardButton(text="🟢 Online VMess",      callback_data="adm_online_vmess")
    )
    b.row(
        InlineKeyboardButton(text="🖥 Akun per Server",  callback_data="adm_akun_per_server"),
        InlineKeyboardButton(text="⚡ Kelola VMess",      callback_data="adm_vmess_menu")
    )
    b.row(
        InlineKeyboardButton(text="🏠 Menu Utama",        callback_data="home")
    )
    return b.as_markup()

def kb_vmess_server_list(prefix: str, page: int = 0, back_cb: str = "m_buat") -> InlineKeyboardMarkup:
    """Server list untuk VMess — filter tipe vmess/both."""
    servers = get_server_list_by_type("vmess")
    per_page = 6
    start    = page * per_page
    chunk    = servers[start:start + per_page]
    b        = InlineKeyboardBuilder()
    for s in chunk:
        name = s.get("NAME", "")
        b.button(text=name, callback_data=f"{prefix}_{name}")
    b.adjust(2)
    nav = []
    if page > 0:
        nav.append(InlineKeyboardButton(text="◀ Sebelumnya", callback_data=f"vpage_{prefix}_{page-1}"))
    if start + per_page < len(servers):
        nav.append(InlineKeyboardButton(text="Berikutnya ▶", callback_data=f"vpage_{prefix}_{page+1}"))
    if nav:
        b.row(*nav)
    b.row(InlineKeyboardButton(text="↩ Kembali", callback_data=back_cb))
    return b.as_markup()
