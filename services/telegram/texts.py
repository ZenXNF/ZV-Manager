#!/usr/bin/env python3
# ============================================================
#   ZV-Manager Bot - Text Message Builders
# ============================================================

from pathlib import Path
from storage import get_server_list, get_server_list_by_type, saldo_get, load_tg_server_conf, count_ssh_accounts, count_vmess_accounts
from utils import fmt, fmt_bytes

def _status_url() -> tuple:
    """
    Baca dari /etc/zv-manager/web-host.
    Return (url, label) — url untuk href, label untuk teks ditampilkan.
    - File tidak ada → ("", "")
    - IP  → ("https://IP", "IP")
    - Domain → ("https://domain", "domain")
    """
    try:
        val = Path("/etc/zv-manager/web-host").read_text().strip()
        if not val:
            return ("", "")
        return (f"https://{val}", val)
    except Exception:
        return ("", "")


def text_home(fname: str, uid: int) -> str:
    servers  = get_server_list()
    saldo    = saldo_get(uid)
    url, label = _status_url()
    cek_line = f"\n🖥️ Cek server: <a href=\"{url}\">{label}</a>" if url else ""
    return (
        f"⚡ <b>ZV-Manager SSH Tunnel</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"🌐 Server  : {len(servers)} server tersedia\n"
        f"🆔 User ID : <code>{uid}</code>\n"
        f"💰 Saldo   : Rp{fmt(saldo)}\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"💎 <b>Layanan Tersedia</b>\n"
        f"🔹 SSH Tunnel Premium\n"
        f"🔹 Support Bug Host / SNI\n"
        f"🔹 Masa Aktif Fleksibel\n"
        f"🔹 Auto Deploy Akun 24 Jam\n"
        f"━━━━━━━━━━━━━━━━━━━{cek_line}\n"
        f"Halo, {fname}! Pilih menu 👇"
    )


def text_server_list(title: str, proto: str = "ssh") -> str:
    """Daftar server untuk pilih saat beli/trial. proto='ssh', 'vmess', atau 'vless'."""
    servers = get_server_list_by_type(proto)
    out = f"<b>{title}</b>\n\n"
    if not servers:
        return out + "❌ Belum ada server.\n\nPilih server:"
    for s in servers:
        name = s.get("NAME", "")
        ip   = s.get("IP", "")
        tg   = load_tg_server_conf(name)

        # Hitung akun sesuai proto
        if proto == "vmess":
            cnt = count_vmess_accounts(ip)
        elif proto == "vless":
            from storage import count_vless_accounts
            cnt = count_vless_accounts(ip)
        else:
            cnt = count_ssh_accounts(ip)

        # Harga sesuai proto
        if proto == "vmess":
            harga_hari_raw = tg.get("TG_HARGA_VMESS_HARI","0") or "0"
            if harga_hari_raw == "0":
                harga_hari_raw = tg.get("TG_HARGA_HARI","0") or "0"
        elif proto == "vless":
            harga_hari_raw = tg.get("TG_HARGA_VLESS_HARI","0") or "0"
            if harga_hari_raw == "0":
                harga_hari_raw = tg.get("TG_HARGA_HARI","0") or "0"
        else:
            harga_hari_raw = tg.get("TG_HARGA_HARI","0") or "0"

        hh = f"Rp{fmt(harga_hari_raw)}" if harga_hari_raw != "0" else "Hubungi admin"
        hb_raw = str(int(harga_hari_raw) * 30) if harga_hari_raw.isdigit() else "0"
        hb = f"Rp{fmt(hb_raw)}" if hb_raw != "0" else "Hubungi admin"

        # BW, max akun, limit IP sesuai proto
        if proto == "vmess":
            bw_hr    = int(tg.get("TG_BW_PER_HARI_VMESS", tg.get("TG_BW_PER_HARI", "5")) or "5")
            max_akun = int(tg.get("TG_MAX_AKUN_VMESS", tg.get("TG_MAX_AKUN", "500")) or "500")
            limit_ip = tg.get("TG_LIMIT_IP_VMESS", tg.get("TG_LIMIT_IP", "2"))
        elif proto == "vless":
            bw_hr    = int(tg.get("TG_BW_PER_HARI_VLESS", tg.get("TG_BW_PER_HARI", "5")) or "5")
            max_akun = int(tg.get("TG_MAX_AKUN_VLESS", tg.get("TG_MAX_AKUN", "500")) or "500")
            limit_ip = tg.get("TG_LIMIT_IP_VLESS", tg.get("TG_LIMIT_IP", "2"))
        else:
            bw_hr    = int(tg.get("TG_BW_PER_HARI", "5") or "5")
            max_akun = int(tg.get("TG_MAX_AKUN", "500") or "500")
            limit_ip = tg.get("TG_LIMIT_IP", "2")

        bw_30 = bw_hr * 30
        bandwidth = f"{bw_hr} GB/hari · {bw_30} GB/30hr" if bw_hr > 0 else "Unlimited"
        is_full = cnt >= max_akun

        proto_label = {"vmess": "VMess", "vless": "VLESS"}.get(proto, "SSH")
        if is_full:
            akun_label = f"👥 {proto_label}: <b>🔴 TERJUAL HABIS</b>"
        else:
            akun_label = f"👥 Total {proto_label}: {cnt}/{max_akun}"

        out += (
            f"🌐 <b>{tg['TG_SERVER_LABEL']}</b>{'  🔴 Penuh' if is_full else ''}\n"
            f"💰 Harga/hari: {hh}\n"
            f"📅 Harga/30hr: {hb}\n"
            f"📶 Bandwidth: {bandwidth}\n"
            f"🔢 Limit IP: {limit_ip} IP/akun\n"
            f"{akun_label}\n\n"
        )
    return out + "Pilih server:"


def text_akun_info(tipe: str, username: str, password: str, domain: str,
                   exp_display: str, limit: str, server_label: str,
                   days: int = 0, total: int = 0, isp: str = "") -> str:
    if tipe == "TRIAL":
        header = "🎁 <b>Akun Trial SSH — 30 Menit</b>"
    else:
        header = "🛒 <b>Akun SSH Berhasil Dibuat</b>"

    harga_line = f"\n💸 Dibayar   : <b>Rp{fmt(total)}</b>" if tipe == "BELI" else ""
    isp_line   = f"\n🏢 ISP       : {isp}" if isp else ""

    return (
        f"{header}\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"👤 Username : <code>{username}</code>\n"
        f"🔑 Password : <code>{password}</code>\n"
        f"🌐 Host     : <code>{domain}</code>\n"
        f"🖥 Server   : {server_label}{isp_line}\n"
        f"📅 Expired  : {exp_display}\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"📡 <b>Port</b>\n"
        f"  SSH  : <code>22, 500, 40000</code>\n"
        f"  DB   : <code>109, 143</code>\n"
        f"  BVPN : <code>7300</code>  WS/WSS/UDP\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"🔗 <b>Format HTTP Custom</b>\n"
        f"  Port 80      : <code>{domain}:80@{username}:{password}</code>\n"
        f"  Port 443     : <code>{domain}:443@{username}:{password}</code>\n"
        f"  UDP 1-65535  : <code>{domain}:1-65535@{username}:{password}</code>"
        f"{harga_line}"
    )

def vmess_build_urls(username: str, uuid: str, domain: str):
    """Kembalikan (url_tls, url_http, url_grpc)."""
    import base64, json
    def _url(port, tls, net, path, label):
        obj = {"v":"2","ps":label,"add":domain,"port":str(port),
               "id":uuid,"aid":"0","net":net,"type":"none",
               "host":domain if net=="ws" else "","path":path,"tls":tls}
        return "vmess://" + base64.b64encode(json.dumps(obj).encode()).decode()
    return (
        _url(443,  "tls",  "ws",   "/vmess",     f"{username}-TLS"),
        _url(80,   "none", "ws",   "/vmess",     f"{username}-HTTP"),
        _url(8443, "tls",  "grpc", "vmess-grpc", f"{username}-gRPC"),
    )


def _fmt_bw(used_bytes: int, limit_gb: int) -> str:
    """Format bandwidth usage untuk display."""
    if limit_gb == 0:
        return "Unlimited"
    used_gb  = round(used_bytes / 1073741824, 2)
    pct      = min(round(used_gb / limit_gb * 100), 100)
    filled   = pct // 10
    bar      = "█" * filled + "░" * (10 - filled)
    color    = "🔴" if pct >= 80 else "🟡" if pct >= 50 else "🟢"
    return f"{used_gb:.2f} GB / {limit_gb} GB\n{color} [{bar}] {pct}%"

def text_vmess_info(tipe: str, username: str, uuid: str, domain: str,
                    exp_display: str, server_label: str,
                    days: int = 0, total: int = 0,
                    isp: str = "") -> str:
    """Pesan info akun VMess — semua dalam 1 pesan termasuk URL."""
    from utils import fmt
    is_trial  = (tipe == "TRIAL")
    header    = "🌟 TRIAL VMESS PREMIUM 🌟" if is_trial else "✅ AKUN VMESS PREMIUM"
    url_tls, url_http, url_grpc = vmess_build_urls(username, uuid, domain)

    lines = [
        f"<b>{header}</b>",
        "━━━━━━━━━━━━━━━━━━━",
        f"⚡ Username : <code>{username}</code>",
        f"🌐 Server   : {server_label}",
    ]
    if isp:
        lines.append(f"🏢 ISP      : {isp}")
    lines += [
        f"🔑 UUID     : <code>{uuid}</code>",
        "━━━━━━━━━━━━━━━━━━━",
        "📡 Port TLS  : 443 (WS + gRPC)",
        "📡 Port HTTP : 80 (WS)",
        "📎 Path WS   : /vmess",
        "📎 Path gRPC : vmess-grpc",
        "━━━━━━━━━━━━━━━━━━━",
    ]
    if is_trial:
        lines.append("⏳ Expired : 30 menit")
    else:
        lines.append(f"⏳ Expired : {exp_display}")
        if days and total:
            lines.append(f"💸 Dibayar : {days} hari — Rp{fmt(total)}")
    lines += [
        "━━━━━━━━━━━━━━━━━━━",
        "🔐 <b>URL VMESS TLS</b>",
        f"<code>{url_tls}</code>",
        "",
        "🔓 <b>URL VMESS HTTP</b>",
        f"<code>{url_http}</code>",
        "",
        "🔒 <b>URL VMESS gRPC</b>",
        f"<code>{url_grpc}</code>",
        "━━━━━━━━━━━━━━━━━━━",
        "✨ Selamat menikmati layanan! ✨",
    ]
    return "\n".join(lines)


def vless_build_urls(username: str, uuid: str, domain: str):
    """Kembalikan (url_tls, url_http, url_grpc) untuk VLESS."""
    def _url(port, security, net, path, label):
        if net == "ws":
            return (f"vless://{uuid}@{domain}:{port}"
                    f"?encryption=none&security={security}&type=ws"
                    f"&host={domain}&path={path}#{label}")
        else:
            return (f"vless://{uuid}@{domain}:{port}"
                    f"?encryption=none&security={security}&type=grpc"
                    f"&serviceName={path}#{label}")
    return (
        _url(443,  "tls",  "ws",   "/vless",     f"{username}-TLS"),
        _url(80,   "none", "ws",   "/vless",     f"{username}-HTTP"),
        _url(8443, "tls",  "grpc", "vless-grpc", f"{username}-gRPC"),
    )


def text_vless_info(tipe: str, username: str, uuid: str, domain: str,
                    exp_display: str, server_label: str,
                    days: int = 0, total: int = 0,
                    isp: str = "") -> str:
    """Pesan info akun VLESS — semua dalam 1 pesan termasuk URL."""
    from utils import fmt
    is_trial = (tipe == "TRIAL")
    header   = "🌟 TRIAL VLESS PREMIUM 🌟" if is_trial else "✅ AKUN VLESS PREMIUM"
    url_tls, url_http, url_grpc = vless_build_urls(username, uuid, domain)

    lines = [
        f"<b>{header}</b>",
        "━━━━━━━━━━━━━━━━━━━",
        f"🌐 Username : <code>{username}</code>",
        f"🌐 Server   : {server_label}",
    ]
    if isp:
        lines.append(f"🏢 ISP      : {isp}")
    lines += [
        f"🔑 UUID     : <code>{uuid}</code>",
        "━━━━━━━━━━━━━━━━━━━",
        "📡 Port TLS  : 443 (WS + gRPC)",
        "📡 Port HTTP : 80 (WS)",
        "📎 Path WS   : /vless",
        "📎 Path gRPC : vless-grpc",
        "━━━━━━━━━━━━━━━━━━━",
    ]
    if is_trial:
        lines.append("⏳ Expired : 30 menit")
    else:
        lines.append(f"⏳ Expired : {exp_display}")
        if days and total:
            lines.append(f"💸 Dibayar : {days} hari — Rp{fmt(total)}")
    lines += [
        "━━━━━━━━━━━━━━━━━━━",
        "🔐 <b>URL VLESS TLS</b>",
        f"<code>{url_tls}</code>",
        "",
        "🔓 <b>URL VLESS HTTP</b>",
        f"<code>{url_http}</code>",
        "",
        "🔒 <b>URL VLESS gRPC</b>",
        f"<code>{url_grpc}</code>",
        "━━━━━━━━━━━━━━━━━━━",
        "✨ Selamat menikmati layanan! ✨",
    ]
    return "\n".join(lines)
