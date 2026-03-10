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
    """Daftar server untuk pilih saat beli/trial. proto='ssh' atau 'vmess'."""
    servers = get_server_list_by_type(proto)
    out = f"<b>{title}</b>\n\n"
    if not servers:
        return out + "❌ Belum ada server.\n\nPilih server:"
    for s in servers:
        name = s.get("NAME", "")
        ip   = s.get("IP", "")
        tg   = load_tg_server_conf(name)
        stype = s.get("SERVER_TYPE", tg.get("TG_SERVER_TYPE", "both"))
        # Hitung akun sesuai proto yang ditampilkan
        if proto == "vmess":
            cnt = count_vmess_accounts(ip)
        else:
            cnt = count_ssh_accounts(ip)
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
        max_akun = int(tg.get("TG_MAX_AKUN", "500") or "500")
        is_full  = cnt >= max_akun
        # Label total akun sesuai proto
        if is_full:
            akun_label = f"👥 {'VMess' if proto == 'vmess' else 'SSH'}: <b>🔴 TERJUAL HABIS</b>"
        elif proto == "vmess":
            akun_label = f"👥 Total VMess: {cnt}/{max_akun}"
        else:
            akun_label = f"👥 Total SSH: {cnt}/{max_akun}"
        out += (
            f"🌐 <b>{tg['TG_SERVER_LABEL']}</b>{'  🔴 Penuh' if is_full else ''}\n"
            f"💰 Harga/hari: {hh}\n"
            f"📅 Harga/30hr: {hb}\n"
            f"📶 Bandwidth: {bandwidth}\n"
            f"🔢 Limit IP: {tg['TG_LIMIT_IP']} IP/akun\n"
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
                             is_trial: bool = False,
                             bw_limit_gb: int = 0,
                             bw_used_bytes: int = 0,
                             ip_limit: int = 2,
                             created: str = "") -> str:
    """Generate HTML dashboard akun VMess."""
    url_tls, url_http, url_grpc = vmess_build_urls(username, uuid, domain)

    # Hitung bandwidth
    bw_used_gb  = round(bw_used_bytes / 1073741824, 2) if bw_used_bytes else 0
    bw_limit_str = f"{bw_limit_gb} GB" if bw_limit_gb else "Unlimited"
    bw_used_str  = f"{bw_used_gb} GB"
    bw_pct       = min(round(bw_used_gb / bw_limit_gb * 100), 100) if bw_limit_gb else 0
    bw_bar_color = "#ef4444" if bw_pct >= 80 else "#f97316" if bw_pct >= 50 else "#22c55e"

    trial_banner = f"""
    <div class="trial-banner">
      <span>⚠️</span>
      <div><b>TRIAL ACCOUNT</b> — Akun ini akan expired dalam 60 menit. Beli akun full untuk akses unlimited.</div>
    </div>""" if is_trial else ""

    created_line = created if created else "—"

    return f"""<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>VMess — {username}</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;600&family=Sora:wght@400;600;700&display=swap" rel="stylesheet">
<style>
  :root {{
    --bg:       #0a0f1e;
    --surface:  #111827;
    --surface2: #1a2235;
    --border:   #1f2d45;
    --accent:   #3b82f6;
    --accent2:  #06b6d4;
    --text:     #f1f5f9;
    --text2:    #94a3b8;
    --text3:    #475569;
    --green:    #22c55e;
    --red:      #ef4444;
    --orange:   #f97316;
  }}
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{
    background: var(--bg);
    color: var(--text);
    font-family: 'Sora', sans-serif;
    min-height: 100vh;
    padding: 0 0 40px;
  }}

  /* Header */
  .header {{
    background: linear-gradient(135deg, #1e3a5f 0%, #0f2040 100%);
    padding: 28px 20px 24px;
    text-align: center;
    border-bottom: 1px solid var(--border);
    position: relative;
    overflow: hidden;
  }}
  .header::before {{
    content: '';
    position: absolute;
    top: -40px; left: -40px;
    width: 200px; height: 200px;
    background: radial-gradient(circle, rgba(59,130,246,.15) 0%, transparent 70%);
    pointer-events: none;
  }}
  .header-icon {{
    width: 52px; height: 52px;
    background: linear-gradient(135deg, var(--accent), var(--accent2));
    border-radius: 14px;
    display: inline-flex; align-items: center; justify-content: center;
    font-size: 22px; margin-bottom: 12px;
    box-shadow: 0 0 24px rgba(59,130,246,.4);
  }}
  .header h1 {{ font-size: 18px; font-weight: 700; color: var(--text); }}
  .header p  {{ font-size: 13px; color: var(--text2); margin-top: 4px; }}
  .trial-badge {{
    display: inline-block;
    background: var(--orange); color: #fff;
    font-size: 11px; font-weight: 700;
    padding: 2px 10px; border-radius: 20px;
    margin-top: 8px; letter-spacing: .5px;
  }}

  .wrap {{ max-width: 480px; margin: 0 auto; padding: 0 16px; }}

  /* Trial banner */
  .trial-banner {{
    background: rgba(249,115,22,.1);
    border: 1px solid rgba(249,115,22,.3);
    border-radius: 12px;
    padding: 12px 14px;
    margin: 16px 0 0;
    display: flex; gap: 10px; align-items: flex-start;
    font-size: 13px; color: #fdba74;
  }}

  /* Section card */
  .card {{
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 16px;
    margin-top: 16px;
    overflow: hidden;
  }}
  .card-title {{
    font-size: 11px; font-weight: 600;
    text-transform: uppercase; letter-spacing: 1px;
    color: var(--text3);
    padding: 14px 16px 10px;
    border-bottom: 1px solid var(--border);
  }}

  /* Info rows */
  .info-row {{
    display: flex; align-items: center; justify-content: space-between;
    padding: 11px 16px;
    border-bottom: 1px solid var(--border);
    gap: 12px;
  }}
  .info-row:last-child {{ border-bottom: none; }}
  .info-label {{
    display: flex; align-items: center; gap: 8px;
    font-size: 13px; color: var(--text2);
    flex-shrink: 0;
  }}
  .info-label .ico {{ font-size: 15px; }}
  .info-val {{
    font-size: 13px; font-weight: 600; color: var(--text);
    text-align: right; word-break: break-all;
    font-family: 'JetBrains Mono', monospace;
  }}
  .info-val.mono {{ font-size: 12px; color: var(--text2); }}

  /* Status badge */
  .status-badge {{
    display: inline-flex; align-items: center; gap: 5px;
    padding: 3px 10px; border-radius: 20px;
    font-size: 12px; font-weight: 700;
    font-family: 'Sora', sans-serif;
  }}
  .status-badge.online  {{ background: rgba(34,197,94,.15);  color: #4ade80; }}
  .status-badge.offline {{ background: rgba(239,68,68,.15);  color: #f87171; }}
  .status-dot {{ width: 6px; height: 6px; border-radius: 50%; background: currentColor; }}
  .status-badge.online .status-dot {{ animation: pulse 2s infinite; }}
  @keyframes pulse {{
    0%,100% {{ opacity: 1; }} 50% {{ opacity: .3; }}
  }}

  /* Bandwidth bar */
  .bw-section {{ padding: 12px 16px; }}
  .bw-header {{ display: flex; justify-content: space-between; margin-bottom: 8px; }}
  .bw-label {{ font-size: 12px; color: var(--text2); }}
  .bw-val   {{ font-size: 12px; font-weight: 600; color: var(--text); font-family: 'JetBrains Mono', monospace; }}
  .bw-bar-bg {{
    height: 8px; background: var(--border);
    border-radius: 99px; overflow: hidden;
  }}
  .bw-bar-fill {{
    height: 100%; border-radius: 99px;
    background: {bw_bar_color};
    width: {bw_pct}%;
    transition: width .6s ease;
  }}
  .bw-note {{ font-size: 11px; color: var(--text3); margin-top: 6px; text-align: right; }}

  /* URL blocks */
  .url-item {{ padding: 12px 16px; border-bottom: 1px solid var(--border); }}
  .url-item:last-child {{ border-bottom: none; }}
  .url-type {{
    font-size: 11px; font-weight: 600;
    text-transform: uppercase; letter-spacing: .5px;
    margin-bottom: 6px;
  }}
  .url-type.tls   {{ color: #60a5fa; }}
  .url-type.http  {{ color: #34d399; }}
  .url-type.grpc  {{ color: #a78bfa; }}
  .url-text {{
    font-family: 'JetBrains Mono', monospace;
    font-size: 10px; color: var(--text2);
    word-break: break-all; line-height: 1.5;
    background: var(--surface2);
    border-radius: 8px; padding: 8px 10px;
    margin-bottom: 8px;
  }}
  .copy-btn {{
    width: 100%; padding: 9px;
    background: var(--surface2);
    border: 1px solid var(--border);
    border-radius: 10px;
    color: var(--text2); font-size: 13px;
    cursor: pointer; font-family: 'Sora', sans-serif;
    transition: all .15s;
  }}
  .copy-btn:hover {{ background: var(--border); color: var(--text); }}
  .copy-btn.copied {{ border-color: var(--green); color: var(--green); }}

  /* Refresh button */
  .refresh-btn {{
    display: flex; align-items: center; justify-content: center; gap: 8px;
    width: 100%; padding: 13px;
    background: linear-gradient(135deg, var(--accent), var(--accent2));
    border: none; border-radius: 12px;
    color: #fff; font-size: 14px; font-weight: 600;
    cursor: pointer; margin-top: 16px;
    font-family: 'Sora', sans-serif;
    box-shadow: 0 4px 16px rgba(59,130,246,.3);
    transition: opacity .15s;
  }}
  .refresh-btn:active {{ opacity: .8; }}

  footer {{ text-align: center; margin-top: 24px; font-size: 11px; color: var(--text3); }}
</style>
</head>
<body>

<div class="header">
  <div class="header-icon">⚡</div>
  <h1>VMess Configuration</h1>
  <p>Your secure access account</p>
  {f'<div class="trial-badge">TRIAL</div>' if is_trial else ""}
</div>

<div class="wrap">
  {trial_banner}

  <!-- Account Info -->
  <div class="card">
    <div class="card-title">Account Information</div>

    <div class="info-row">
      <span class="info-label"><span class="ico">👤</span> Username</span>
      <span class="info-val">{username}</span>
    </div>
    <div class="info-row">
      <span class="info-label"><span class="ico">🌐</span> Domain</span>
      <span class="info-val mono">{domain}</span>
    </div>
    <div class="info-row">
      <span class="info-label"><span class="ico">📡</span> Status</span>
      <span class="info-val">
        <span class="status-badge online" id="status-badge">
          <span class="status-dot"></span> Online
        </span>
      </span>
    </div>
    <div class="info-row">
      <span class="info-label"><span class="ico">📅</span> Expired Date</span>
      <span class="info-val" style="color:#fb923c">{exp_display}</span>
    </div>
    <div class="info-row">
      <span class="info-label"><span class="ico">🕐</span> Created</span>
      <span class="info-val mono">{created_line}</span>
    </div>
    <div class="info-row">
      <span class="info-label"><span class="ico">🔒</span> IP Limit</span>
      <span class="info-val">{ip_limit}</span>
    </div>
    <div class="info-row">
      <span class="info-label"><span class="ico">👥</span> Online Users</span>
      <span class="info-val" id="online-count">—</span>
    </div>
  </div>

  <!-- Bandwidth -->
  <div class="card">
    <div class="card-title">Quota Usage</div>
    <div class="bw-section">
      <div class="bw-header">
        <span class="bw-label">Used</span>
        <span class="bw-val">{bw_used_str} / {bw_limit_str}</span>
      </div>
      <div class="bw-bar-bg">
        <div class="bw-bar-fill"></div>
      </div>
      <div class="bw-note">{bw_pct}% used</div>
    </div>
  </div>

  <!-- Configuration Links -->
  <div class="card">
    <div class="card-title">Configuration Links</div>
    <div class="url-item">
      <div class="url-type tls">🔐 VMess TLS (WebSocket)</div>
      <div class="url-text" id="u1">{url_tls}</div>
      <button class="copy-btn" onclick="cp('u1',this)">📋 Copy</button>
    </div>
    <div class="url-item">
      <div class="url-type http">🔓 VMess Non-TLS (WebSocket)</div>
      <div class="url-text" id="u2">{url_http}</div>
      <button class="copy-btn" onclick="cp('u2',this)">📋 Copy</button>
    </div>
    <div class="url-item">
      <div class="url-type grpc">⚡ VMess gRPC</div>
      <div class="url-text" id="u3">{url_grpc}</div>
      <button class="copy-btn" onclick="cp('u3',this)">📋 Copy</button>
    </div>
  </div>

  <button class="refresh-btn" onclick="location.reload()">
    🔄 Refresh
  </button>
</div>

<footer>ZV-Manager • {domain}</footer>

<script>
// Copy to clipboard
function cp(id, btn) {{
  var t = document.getElementById(id).innerText;
  navigator.clipboard.writeText(t).then(function() {{
    btn.textContent = '✅ Copied!';
    btn.classList.add('copied');
    setTimeout(function() {{
      btn.textContent = '📋 Copy';
      btn.classList.remove('copied');
    }}, 2000);
  }});
}}

// Fetch online users dari Xray API via endpoint
async function fetchOnline() {{
  try {{
    var r = await fetch('/api/online-{username}.json', {{cache:'no-store'}});
    if (r.ok) {{
      var d = await r.json();
      document.getElementById('online-count').textContent = d.online ?? '0';
      var badge = document.getElementById('status-badge');
      if (d.online > 0) {{
        badge.className = 'status-badge online';
        badge.innerHTML = '<span class="status-dot"></span> Online';
      }} else {{
        badge.className = 'status-badge offline';
        badge.innerHTML = '<span class="status-dot"></span> Offline';
      }}
    }}
  }} catch(e) {{}}
}}
fetchOnline();
setInterval(fetchOnline, 10000);
</script>
</body>
</html>"""

