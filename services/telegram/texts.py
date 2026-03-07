#!/usr/bin/env python3
# ============================================================
#   ZV-Manager Bot - Text Message Builders
# ============================================================

from pathlib import Path
from storage import get_server_list, saldo_get, load_tg_server_conf, count_accounts
from utils import fmt, fmt_bytes

def _status_url() -> str:
    # Hanya tampilkan jika web sudah diinstall (cron ada)
    if not Path("/etc/cron.d/zv-status-page").exists():
        return ""
    # Prioritas: domain → IP
    for p in ["/etc/zv-manager/domain", "/etc/zv-manager/accounts/ipvps"]:
        try:
            h = Path(p).read_text().strip()
            if h: return f"https://{h}/status"
        except: pass
    return ""


def text_home(fname: str, uid: int) -> str:
    servers = get_server_list()
    saldo   = saldo_get(uid)
    url     = _status_url()
    cek_line = f"\n🖥️ Cek server: {url}" if url else ""
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
            f"💰 Harga/hari: {hh}\n"
            f"📅 Harga/30hr: {hb}\n"
            f"📶 Bandwidth: {bandwidth}\n"
            f"🔢 Limit IP: {tg['TG_LIMIT_IP']} IP/akun\n"
            f"👥 Total Akun: {cnt}/{tg['TG_MAX_AKUN']}\n\n"
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
        f"📡 <b>Port</b>\n"
        f"  SSH  : <code>22, 500, 40000</code>\n"
        f"  DB   : <code>109, 143</code>\n"
        f"  BVPN : <code>7300</code>  WS/WSS/UDP\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"🔗 <b>Format HTTP Custom</b>\n"
        f"  Port 80  : <code>{domain}:80@{username}:{password}</code>\n"
        f"  Port 443 : <code>{domain}:443@{username}:{password}</code>\n"
        f"  UDP      : <code>{domain}:1-65535@{username}:{password}</code>"
        f"{harga_line}"
    )

def text_vmess_info(tipe: str, username: str, uuid: str, domain: str,
                    exp_display: str, server_label: str,
                    days: int = 0, total: int = 0) -> str:
    """Pesan info akun VMess setelah beli/trial."""
    import base64, json
    is_trial = (tipe == "TRIAL")
    header = "🌟 TRIAL VMESS PREMIUM 🌟" if is_trial else "✅ AKUN VMESS PREMIUM"

    def _url(port, tls, net, path, label):
        obj = {"v":"2","ps":label,"add":domain,"port":str(port),
               "id":uuid,"aid":"0","net":net,"type":"none",
               "host":domain if net=="ws" else "","path":path,
               "tls":tls}
        return "vmess://" + base64.b64encode(json.dumps(obj).encode()).decode()

    url_tls  = _url(443,  "tls",  "ws",   "/vmess",      f"{username}-TLS")
    url_http = _url(80,   "none", "ws",   "/vmess",      f"{username}-HTTP")
    url_grpc = _url(443, "tls",  "grpc", "vmess-grpc",  f"{username}-gRPC")

    lines = [
        f"<b>{header}</b>",
        "",
        "🔹 <b>Informasi Akun</b>",
        "┌─────────────────────",
        f"│ Username : <code>{username}</code>",
        f"│ Domain   : <code>{domain}</code>",
        f"│ UUID     : <code>{uuid}</code>",
        "│ Port TLS : 443",
        "│ Port HTTP: 80",
        "│ Alter ID : 0",
        "│ Network  : Websocket / gRPC",
        "│ Path WS  : /vmess",
        "│ Path gRPC: vmess-grpc",
        "└─────────────────────",
        "",
        "🔐 <b>URL VMESS TLS (WS)</b>",
        f"<code>{url_tls}</code>",
        "",
        "🔓 <b>URL VMESS HTTP (WS)</b>",
        f"<code>{url_http}</code>",
        "",
        "🔒 <b>URL VMESS gRPC</b>",
        f"<code>{url_grpc}</code>",
        "",
        "┌─────────────────────",
    ]
    if is_trial:
        lines.append("│ Expired : 30 menit")
    else:
        lines.append(f"│ Expired : {exp_display}")
        if days and total:
            from utils import fmt
            lines.append(f"│ Durasi  : {days} hari — Rp{fmt(total)}")
    lines += ["└─────────────────────", "", "✨ Selamat menikmati layanan! ✨"]
    return "\n".join(lines)

