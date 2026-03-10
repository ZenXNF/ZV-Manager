#!/bin/bash
# ============================================================
#   ZV-Manager - Status Page Generator
#   Cron: */5 * * * *
#   Generate /var/www/zv-manager/index.html
# ============================================================

SERVER_DIR="/etc/zv-manager/servers"
WEB_DIR="/var/www/zv-manager"
STATE_DIR="/var/lib/zv-manager/status"
OUTPUT="${WEB_DIR}/index.html"
PANEL_NAME=$(grep "^PANEL_NAME=" /etc/zv-manager/config.conf 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "ZV-Manager")

mkdir -p "$WEB_DIR" "$STATE_DIR"

# ── Helpers ───────────────────────────────────────────────
_ping_ms() {
    local ip="$1"
    ping -c 1 -W 2 "$ip" 2>/dev/null | grep "time=" | sed 's/.*time=\([0-9.]*\).*/\1/'
}

_check_port() {
    nc -zw2 "$1" "$2" &>/dev/null && echo "1" || echo "0"
}

_update_uptime() {
    local name="$1" status="$2"
    local f="${STATE_DIR}/${name}.uptime"
    local h=""
    [[ -f "$f" ]] && h=$(cat "$f")
    h="${h}${status}"
    [[ ${#h} -gt 720 ]] && h="${h: -720}"
    echo "$h" > "$f"
}

_calc_uptime_pct() {
    local f="${STATE_DIR}/${1}.uptime"
    [[ ! -f "$f" ]] && echo "100.0" && return
    local h; h=$(cat "$f")
    local total="${#h}"
    [[ $total -eq 0 ]] && echo "100.0" && return
    local up; up=$(echo "$h" | tr -cd '1' | wc -c)
    python3 -c "print(f'{$up/$total*100:.1f}')" 2>/dev/null || echo "100.0"
}

# ── Kumpulkan data server ─────────────────────────────────
NOW_WIB=$(TZ=Asia/Jakarta date "+%d %b %Y %H:%M:%S WIB")
TOTAL_UP=0
TOTAL_DOWN=0
CARDS_HTML=""

for conf in "$SERVER_DIR"/*.conf; do
    [[ -f "$conf" ]] || continue
    [[ "$conf" == *.tg.conf ]] && continue

    unset NAME IP DOMAIN PORT ISP
    source "$conf"
    [[ -z "$NAME" ]] && continue

    # Kalau IP kosong, fallback ke IP lokal (server ini = tunneling VPS lokal)
    if [[ -z "$IP" ]]; then
        _local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null | tr -d '[:space:]')
        IP="${_local_ip:-127.0.0.1}"
    fi

    LABEL="$NAME"
    tgconf="${SERVER_DIR}/${NAME}.tg.conf"
    [[ -f "$tgconf" ]] && { source "$tgconf"; LABEL="${TG_SERVER_LABEL:-$NAME}"; }

    ms=$(_ping_ms "$IP")
    port_ok=$(_check_port "$IP" "${PORT:-22}")

    if [[ "$port_ok" == "1" ]]; then
        STATUS="UP"; STATUS_CLASS="up"; TOTAL_UP=$((TOTAL_UP+1))
        _update_uptime "$NAME" "1"
    else
        STATUS="DOWN"; STATUS_CLASS="down"; TOTAL_DOWN=$((TOTAL_DOWN+1))
        _update_uptime "$NAME" "0"
    fi

    uptime_pct=$(_calc_uptime_pct "$NAME")
    UPT_CLASS="green"
    [[ $(echo "$uptime_pct < 95" | bc -l 2>/dev/null) == "1" ]] && UPT_CLASS="yellow"
    [[ $(echo "$uptime_pct < 80" | bc -l 2>/dev/null) == "1" ]] && UPT_CLASS="red"

    DISPLAY_HOST="${DOMAIN:-$IP}"
    ISP_LINE="${ISP:-}"
    LAST_CHECK=$(TZ=Asia/Jakarta date '+%H:%M')

    CARDS_HTML+="
    <div class='card'>
      <div class='chead'>
        <div class='cname'>
          <span class='dot dot-${STATUS_CLASS}'></span>
          <span class='clabel'>${LABEL}</span>
          <span class='ctag'>${DISPLAY_HOST}</span>
        </div>
        <span class='badge badge-${STATUS_CLASS}'>${STATUS}</span>
      </div>
      <div class='cbody'>
        <div class='cstat'>
          <div class='slbl'>UPTIME</div>
          <div class='sval ${UPT_CLASS}'>${uptime_pct}%</div>
        </div>
        <div class='cstat'>
          <div class='slbl'>RESPONSE</div>
          <div class='sval'>${ms:-—} ms</div>
        </div>
        <div class='cstat'>
          <div class='slbl'>STATUS</div>
          <div class='sval'>${port_ok/1/OK}</div>
        </div>
        <div class='cstat'>
          <div class='slbl'>LAST CHECK</div>
          <div class='sval sm'>${LAST_CHECK}</div>
        </div>
      </div>$([ -n "$ISP_LINE" ] && echo "
      <div class='cisp'>📡 ${ISP_LINE}</div>")</div>"
done

TOTAL_SERVER=$((TOTAL_UP + TOTAL_DOWN))
[[ $TOTAL_SERVER -gt 0 ]] && \
    AVG_UPTIME=$(python3 -c "print(f'{$TOTAL_UP/$TOTAL_SERVER*100:.1f}')") || AVG_UPTIME="100.0"

[[ $TOTAL_DOWN -eq 0 ]] \
    && SUMMARY_CLASS="all-up"   SUMMARY_TEXT="All Systems Operational" \
    || SUMMARY_CLASS="some-down" SUMMARY_TEXT="${TOTAL_DOWN} Server Membutuhkan Perhatian"

# Favicon SVG (ZV logo biru)
FAVICON='data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"><rect width="32" height="32" rx="8" fill="%232563eb"/><text x="16" y="22" font-family="system-ui,sans-serif" font-size="14" font-weight="700" fill="white" text-anchor="middle">ZV</text></svg>'

# ── Generate HTML ─────────────────────────────────────────
cat > "$OUTPUT" << HTMLEOF
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta http-equiv="refresh" content="300">
<title>${PANEL_NAME} — Server Status</title>
<link rel="icon" type="image/svg+xml" href="${FAVICON}">
<style>
  :root {
    --bg:      #0d1117;
    --surface: #161b22;
    --border:  #21262d;
    --text:    #e6edf3;
    --text2:   #8b949e;
    --text3:   #484f58;
    --tag-bg:  #1c2128;
  }
  * { margin:0; padding:0; box-sizing:border-box; }
  body {
    background: var(--bg);
    color: var(--text);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Inter", sans-serif;
    min-height: 100vh;
    padding-bottom: 48px;
  }

  /* Header */
  .header {
    background: var(--surface);
    border-bottom: 1px solid var(--border);
    padding: 22px 20px 18px;
    text-align: center;
  }
  .logo {
    width: 46px; height: 46px;
    background: linear-gradient(135deg, #2563eb 0%, #0ea5e9 100%);
    border-radius: 12px;
    display: inline-flex; align-items: center; justify-content: center;
    font-size: 15px; font-weight: 800; color: white; letter-spacing: -0.5px;
    margin-bottom: 10px;
    box-shadow: 0 4px 14px rgba(37,99,235,.35);
  }
  .header h1 { font-size: 16px; font-weight: 700; color: var(--text); }
  .htime {
    display: inline-flex; align-items: center; gap: 5px;
    font-size: 12px; color: var(--text2);
    background: var(--tag-bg); border: 1px solid var(--border);
    border-radius: 20px; padding: 4px 12px; margin-top: 9px;
  }

  /* Summary cards */
  .summary {
    display: grid; grid-template-columns: repeat(3, 1fr);
    gap: 8px; padding: 14px 16px;
    max-width: 500px; margin: 0 auto;
  }
  .scard {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 12px; padding: 14px 10px;
    text-align: center;
  }
  .scard-val { font-size: 22px; font-weight: 700; line-height: 1; }
  .scard-val.green  { color: #4ade80; }
  .scard-val.red    { color: #f87171; }
  .scard-val.blue   { color: #60a5fa; }
  .scard-lbl { font-size: 10px; color: var(--text3); margin-top: 5px; text-transform: uppercase; letter-spacing: .5px; }

  /* Status pill */
  .spill {
    margin: 0 16px 14px; max-width: 468px;
    margin-left: auto; margin-right: auto;
    background: var(--surface); border: 1px solid var(--border);
    border-radius: 10px; padding: 10px 14px;
    display: flex; align-items: center; gap: 9px;
    font-size: 13px; color: var(--text2);
  }
  .sdot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
  .sdot.all-up    { background: #4ade80; animation: spulse 2s infinite; }
  .sdot.some-down { background: #f87171; }
  @keyframes spulse {
    0%,100% { box-shadow: 0 0 0 0 rgba(74,222,128,.4); }
    50%      { box-shadow: 0 0 0 5px rgba(74,222,128,0); }
  }
  .spill-text { flex: 1; }
  .spill-note { font-size: 11px; color: var(--text3); }

  /* Section label */
  .sec {
    font-size: 11px; font-weight: 600; color: var(--text3);
    text-transform: uppercase; letter-spacing: 1px;
    padding: 0 16px 8px; max-width: 500px; margin: 0 auto;
  }

  /* Cards */
  .cards {
    display: flex; flex-direction: column; gap: 8px;
    padding: 0 16px; max-width: 500px; margin: 0 auto;
  }
  .card {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 14px; overflow: hidden;
  }
  .chead {
    display: flex; align-items: center; justify-content: space-between;
    padding: 13px 14px 11px;
    border-bottom: 1px solid var(--border);
  }
  .cname {
    display: flex; align-items: center; gap: 8px;
    min-width: 0;
  }
  .clabel { font-size: 14px; font-weight: 600; color: var(--text); white-space: nowrap; }
  .ctag {
    font-size: 11px; color: var(--text3);
    background: var(--tag-bg); border: 1px solid var(--border);
    border-radius: 6px; padding: 2px 7px;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
    max-width: 130px;
  }
  .dot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
  .dot-up   { background: #4ade80; animation: dpulse 2s infinite; }
  .dot-down { background: #f87171; }
  @keyframes dpulse {
    0%,100% { box-shadow: 0 0 0 0 rgba(74,222,128,.4); }
    50%      { box-shadow: 0 0 0 4px rgba(74,222,128,0); }
  }
  .badge { font-size: 11px; font-weight: 700; padding: 3px 10px; border-radius: 20px; flex-shrink:0; }
  .badge-up   { background: rgba(74,222,128,.12); color: #4ade80; }
  .badge-down { background: rgba(248,113,113,.12); color: #f87171; }

  /* Card stats */
  .cbody {
    display: grid; grid-template-columns: repeat(4,1fr);
    padding: 11px 14px; gap: 6px;
  }
  .cstat {}
  .slbl { font-size: 10px; color: var(--text3); text-transform: uppercase; letter-spacing: .4px; margin-bottom: 3px; }
  .sval { font-size: 14px; font-weight: 600; color: var(--text2); }
  .sval.green  { color: #4ade80; }
  .sval.yellow { color: #fbbf24; }
  .sval.red    { color: #f87171; }
  .sval.sm     { font-size: 13px; }

  /* ISP line */
  .cisp {
    font-size: 11px; color: var(--text3);
    padding: 0 14px 10px;
    border-top: 1px solid var(--border);
    padding-top: 8px;
  }

  /* Footer */
  .footer { text-align: center; font-size: 11px; color: var(--text3); padding: 20px 16px 0; }
</style>
</head>
<body>

<div class="header">
  <div class="logo">ZV</div>
  <h1>${PANEL_NAME}</h1>
  <div class="htime">🕐 ${NOW_WIB}</div>
</div>

<br>

<div class="summary">
  <div class="scard">
    <div class="scard-val green">${TOTAL_UP}</div>
    <div class="scard-lbl">Services Up</div>
  </div>
  <div class="scard">
    <div class="scard-val red">${TOTAL_DOWN}</div>
    <div class="scard-lbl">Services Down</div>
  </div>
  <div class="scard">
    <div class="scard-val blue">${AVG_UPTIME}%</div>
    <div class="scard-lbl">Avg. Uptime</div>
  </div>
</div>

<div class="spill">
  <div class="sdot ${SUMMARY_CLASS}"></div>
  <div class="spill-text">${SUMMARY_TEXT}</div>
  <div class="spill-note">Auto-refresh 5 mnt</div>
</div>

<div class="sec">Status Server</div>

<div class="cards">
${CARDS_HTML}
</div>

<div class="footer">${PANEL_NAME} · Update setiap 5 menit</div>

</body>
</html>
HTMLEOF

chown -R www-data:www-data "$WEB_DIR" 2>/dev/null
