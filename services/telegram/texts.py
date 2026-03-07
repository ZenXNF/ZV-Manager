#!/usr/bin/env python3
# ============================================================
#   ZV-Manager Bot - Text Message Builders
# ============================================================

from storage import get_server_list, saldo_get, load_tg_server_conf, count_accounts
from utils import fmt, fmt_bytes


def text_home(fname: str, uid: int) -> str:
    servers = get_server_list()
    saldo   = saldo_get(uid)
    return (
        f"⚡ <b>ZV-Manager SSH Tunnel</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"🖥️ Server   : {len(servers)} server\n"
        f"🆔 User ID  : <code>{uid}</code>\n"
        f"💰 Saldo    : Rp{fmt(saldo)}\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"🔹 SSH Tunnel / Premium\n"
        f"🔹 Support Bug Host / SNI\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"Halo, {fname}! Pilih menu 👇"
    )


def text_server_list(title: str) -> str:
    servers = get_server_list()
    out = f"<b>{title}</b>\n\n"
    if not servers:
        return out + "❌ Belum ada server.\n\nPilih server:"
    for s in servers:
        name = s.get("NAME", "")
        ip   = s.get("IP", "")
        tg   = load_tg_server_conf(name)
        cnt  = count_accounts(ip)
        hh   = f"Rp{fmt(tg['TG_HARGA_HARI'])}" if tg["TG_HARGA_HARI"] != "0" else "Hubungi admin"
        hb   = f"Rp{fmt(tg['TG_HARGA_BULAN'])}" if tg["TG_HARGA_BULAN"] != "0" else "Hubungi admin"
        bw_hr = int(tg.get("TG_BW_PER_HARI", "5") or "5")
        bw_30 = bw_hr * 30
        bandwidth = f"{bw_hr} GB/hari · {bw_30} GB/30hr" if bw_hr > 0 else "Unlimited"
        out += (
            f"🌐 <b>{tg['TG_SERVER_LABEL']}</b>\n"
            f"💰 Harga/hari  : {hh}\n"
            f"📅 Harga/30hr  : {hb}\n"
            f"📶 Bandwidth       : {bandwidth}\n"
            f"🔢 Limit IP    : {tg['TG_LIMIT_IP']} IP/akun\n"
            f"👥 Total Akun  : {cnt}/{tg['TG_MAX_AKUN']}\n\n"
        )
    return out + "Pilih server:"


def text_akun_info(tipe: str, username: str, password: str, domain: str,
                   exp_display: str, limit: str, server_label: str,
                   days: int = 0, total: int = 0) -> str:
    if tipe == "TRIAL":
        header = "🎁 <b>Akun Trial SSH — 30 Menit</b>"
    else:
        header = "🛒 <b>Akun SSH Berhasil Dibuat</b>"

    harga_line = f"\n💸 Dibayar   : <b>Rp{fmt(total)}</b>" if tipe == "BELI" else ""

    return (
        f"{header}\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"👤 Username : <code>{username}</code>\n"
        f"🔑 Password : <code>{password}</code>\n"
        f"🌐 Host     : <code>{domain}</code>\n"
        f"🖥 Server   : {server_label}\n"
        f"📅 Expired  : {exp_display}\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"📡 <b>Port Tersedia</b>\n"
        f"  OpenSSH  : <code>22, 500, 40000</code>\n"
        f"  Dropbear : <code>109, 143</code>\n"
        f"  BadVPN   : <code>7300</code>\n"
        f"  WS / WSS / UDP Custom\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"🔗 <b>Format HTTP Custom</b>\n"
        f"  Port 80  : <code>{domain}:80@{username}:{password}</code>\n"
        f"  Port 443 : <code>{domain}:443@{username}:{password}</code>\n"
        f"  UDP      : <code>{domain}:1-65535@{username}:{password}</code>"
        f"{harga_line}"
    )
