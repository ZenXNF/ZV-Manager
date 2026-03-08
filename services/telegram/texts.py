#!/usr/bin/env python3
# ============================================================
#   ZV-Manager Bot - Text Message Builders
# ============================================================

from pathlib import Path
from storage import get_server_list, get_server_list_by_type, saldo_get, load_tg_server_conf, count_accounts
from utils import fmt, fmt_bytes

def _status_url() -> str:
    """
    Baca dari /etc/zv-manager/web-host (dibuat setup-web.sh).
    - File tidak ada → web belum diinstall, tidak tampil
    - Isi IP (x.x.x.x) → http://x.x.x.x/status
    - Isi domain (mis. status.zenxu.my.id) → https://status.zenxu.my.id
    """
    try:
        val = Path("/etc/zv-manager/web-host").read_text().strip()
        if not val:
            return ""
        import re as _re
        if _re.match(r"^\d{1,3}(\.\d{1,3}){3}$", val):
            return f"http://{val}/status"
        # Domain custom — tampilkan apa adanya sebagai subdomain
        return f"https://{val}"
    except Exception:
        return ""


def text_home(fname: str, uid: int) -> str:
    servers  = get_server_list()
    saldo    = saldo_get(uid)
    url      = _status_url()
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


def text_server_list(title: str, proto: str = "ssh") -> str:
    """Daftar server untuk pilih saat beli/trial. proto='ssh' atau 'vmess'."""
    servers = get_server_list_by_type(proto)
    out = f"<b>{title}</b>\n\n"
    if not servers:
        return out + "❌ Belum ada server.\n\nPilih server:"
    for s in servers:
        name = s.get("NAME", "")
        ip   = s.get("IP", "")
        tg   = load_tg_server_conf(name)
        cnt  = count_accounts(ip)
        # Harga: VMess pakai TG_HARGA_VMESS_HARI jika > 0, else fallback SSH
        if proto == "vmess":
            harga_hari_raw = tg.get("TG_HARGA_VMESS_HARI","0") or "0"
            if harga_hari_raw == "0":
                harga_hari_raw = tg.get("TG_HARGA_HARI","0") or "0"
        else:
            harga_hari_raw = tg.get("TG_HARGA_HARI","0") or "0"
        hh = f"Rp{fmt(harga_hari_raw)}" if harga_hari_raw != "0" else "Hubungi admin"
        hb_raw = str(int(harga_hari_raw) * 30) if harga_hari_raw.isdigit() else "0"
        hb = f"Rp{fmt(hb_raw)}" if hb_raw != "0" else "Hubungi admin"
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
        f"  Port 80  : <code>{domain}:80@{username}:{password}</code>\n"
        f"  Port 443 : <code>{domain}:443@{username}:{password}</code>\n"
        f"  UDP      : <code>{domain}:1-65535@{username}:{password}</code>"
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
        _url(443, "tls",  "ws",   "/vmess",     f"{username}-TLS"),
        _url(80,  "none", "ws",   "/vmess",     f"{username}-HTTP"),
        _url(443, "tls",  "grpc", "vmess-grpc", f"{username}-gRPC"),
    )


def _fmt_bw(used_bytes: int, limit_gb: int) -> str:
    """Format bandwidth usage untuk display."""
    if limit_gb == 0:
        return "Unlimited"
    used_gb = used_bytes / 1073741824
    pct = min(int(used_gb / limit_gb * 100), 100)
    bar_filled = pct // 10
    bar = "█" * bar_filled + "░" * (10 - bar_filled)
    return f"{used_gb:.1f}/{limit_gb} GB [{bar}] {pct}%"

def text_vmess_info(tipe: str, username: str, uuid: str, domain: str,
                    exp_display: str, server_label: str,
                    days: int = 0, total: int = 0,
                    dashboard_url: str = "", isp: str = "") -> str:
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
    if dashboard_url:
        lines += ["━━━━━━━━━━━━━━━━━━━",
                  f"🖥 <a href=\"{dashboard_url}\">Dashboard Akun</a>"]
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

def vmess_url_messages(username: str, uuid: str, domain: str) -> list:
    """Tidak dipakai lagi — URL sudah digabung di text_vmess_info."""
    return []

def generate_dashboard_html(username: str, uuid: str, domain: str,
                             exp_display: str, server_label: str,
                             is_trial: bool = False) -> str:
    """Generate HTML dashboard akun VMess."""
    url_tls, url_http, url_grpc = vmess_build_urls(username, uuid, domain)
    trial_badge = ' <span style="background:#f97316;color:#fff;padding:2px 8px;border-radius:20px;font-size:12px">TRIAL</span>' if is_trial else ""
    return f"""<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>VMess Info — {username}</title>
<style>
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{ background: #0f172a; color: #e2e8f0; font-family: system-ui, sans-serif;
         min-height: 100vh; padding: 20px; }}
  .card {{ background: #1e293b; border-radius: 16px; padding: 24px;
           max-width: 600px; margin: 0 auto; box-shadow: 0 4px 24px rgba(0,0,0,.4); }}
  h1 {{ font-size: 20px; color: #38bdf8; margin-bottom: 4px; }}
  .badge {{ display: inline-block; background: #6366f1; color: #fff;
            padding: 2px 10px; border-radius: 20px; font-size: 12px; margin-bottom: 16px; }}
  .section {{ margin: 16px 0; }}
  .section h2 {{ font-size: 13px; color: #94a3b8; text-transform: uppercase;
                letter-spacing: 1px; margin-bottom: 8px; }}
  .row {{ display: flex; justify-content: space-between; align-items: center;
          padding: 8px 0; border-bottom: 1px solid #334155; gap: 8px; }}
  .row:last-child {{ border-bottom: none; }}
  .label {{ color: #94a3b8; font-size: 13px; flex-shrink: 0; }}
  .val {{ font-family: monospace; font-size: 13px; color: #f1f5f9;
          word-break: break-all; text-align: right; }}
  .url-block {{ background: #0f172a; border-radius: 10px; padding: 12px; margin: 8px 0; }}
  .url-label {{ font-size: 12px; color: #38bdf8; margin-bottom: 6px; }}
  .url-text {{ font-family: monospace; font-size: 11px; color: #a5f3fc;
               word-break: break-all; }}
  .copy-btn {{ display: block; width: 100%; margin-top: 8px; padding: 8px;
               background: #0ea5e9; color: #fff; border: none; border-radius: 8px;
               cursor: pointer; font-size: 13px; }}
  .copy-btn:active {{ background: #0284c7; }}
  .expired {{ color: #fb923c; font-weight: 600; }}
  footer {{ text-align: center; margin-top: 24px; color: #475569; font-size: 12px; }}
</style>
</head>
<body>
<div class="card">
  <h1>⚡ VMess Account{trial_badge}</h1>
  <div class="badge">{server_label}</div>

  <div class="section">
    <h2>Informasi Akun</h2>
    <div class="row"><span class="label">Username</span><span class="val">{username}</span></div>
    <div class="row"><span class="label">UUID</span><span class="val">{uuid}</span></div>
    <div class="row"><span class="label">Domain</span><span class="val">{domain}</span></div>
    <div class="row"><span class="label">Expired</span><span class="val expired">{exp_display}</span></div>
  </div>

  <div class="section">
    <h2>Konfigurasi</h2>
    <div class="row"><span class="label">Port TLS</span><span class="val">443</span></div>
    <div class="row"><span class="label">Port HTTP</span><span class="val">80</span></div>
    <div class="row"><span class="label">Network</span><span class="val">WebSocket / gRPC</span></div>
    <div class="row"><span class="label">Path WS</span><span class="val">/vmess</span></div>
    <div class="row"><span class="label">Path gRPC</span><span class="val">vmess-grpc</span></div>
    <div class="row"><span class="label">Alter ID</span><span class="val">0</span></div>
    <div class="row"><span class="label">TLS</span><span class="val">TLS</span></div>
  </div>

  <div class="section">
    <h2>Import URL</h2>
    <div class="url-block">
      <div class="url-label">🔐 VMess TLS (WS)</div>
      <div class="url-text" id="u1">{url_tls}</div>
      <button class="copy-btn" onclick="cp('u1',this)">📋 Salin</button>
    </div>
    <div class="url-block">
      <div class="url-label">🔓 VMess HTTP (WS)</div>
      <div class="url-text" id="u2">{url_http}</div>
      <button class="copy-btn" onclick="cp('u2',this)">📋 Salin</button>
    </div>
    <div class="url-block">
      <div class="url-label">🔒 VMess gRPC</div>
      <div class="url-text" id="u3">{url_grpc}</div>
      <button class="copy-btn" onclick="cp('u3',this)">📋 Salin</button>
    </div>
  </div>
</div>
<footer>ZV-Manager • {domain}</footer>
<script>
function cp(id,btn){{
  var t=document.getElementById(id).innerText;
  navigator.clipboard.writeText(t).then(function(){{
    btn.textContent='✅ Tersalin!';
    setTimeout(function(){{btn.textContent='📋 Salin';}},2000);
  }});
}}
</script>
</body>
</html>"""

