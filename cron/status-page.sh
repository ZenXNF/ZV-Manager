#!/bin/bash
# ============================================================
#   ZV-Manager - Status Page Generator
#   Cron: */5 * * * *
#   Generate /var/www/zv-manager/index.html
# ============================================================

SERVER_DIR="/etc/zv-manager/servers"
ACCOUNT_DIR="/etc/zv-manager/accounts/ssh"
WEB_DIR="/var/www/zv-manager"
STATE_DIR="/var/lib/zv-manager/status"
OUTPUT="${WEB_DIR}/index.html"
PANEL_NAME=$(grep "^PANEL_NAME=" /etc/zv-manager/config.conf 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "ZV-Manager")

mkdir -p "$WEB_DIR" "$STATE_DIR"

# ── Helper: ping response time (ms) ───────────────────────
_ping_ms() {
    local ip="$1"
    local ms
    ms=$(ping -c 1 -W 2 "$ip" 2>/dev/null | grep "time=" | sed 's/.*time=\([0-9.]*\).*/\1/')
    echo "${ms:-0}"
}

# ── Helper: cek port SSH terbuka ─────────────────────────
_check_port() {
    local ip="$1" port="$2"
    nc -zw2 "$ip" "$port" &>/dev/null && echo "1" || echo "0"
}

# ── Helper: hitung akun aktif per server ─────────────────
_count_active() {
    local server_name="$1"
    local today; today=$(date +"%Y-%m-%d")
    local count=0
    for conf in "$ACCOUNT_DIR"/*.conf; do
        [[ -f "$conf" ]] || continue
        local srv exp
        srv=$(grep "^SERVER=" "$conf" | cut -d= -f2 | tr -d '"')
        exp=$(grep "^EXPIRED=" "$conf" | cut -d= -f2 | tr -d '"')
        [[ "$srv" == "$server_name" && "$exp" > "$today" ]] && count=$((count+1))
    done
    echo "$count"
}

# ── Helper: update uptime tracking ───────────────────────
# Simpan history 30 hari sebagai string "1" (up) atau "0" (down)
_update_uptime() {
    local name="$1" status="$2"
    local state_file="${STATE_DIR}/${name}.uptime"
    local history=""
    [[ -f "$state_file" ]] && history=$(cat "$state_file")
    history="${history}${status}"
    # Simpan max 720 entri (5 menit × 720 = 60 jam = ~30 data/jam × 24 = uptime harian)
    if [[ ${#history} -gt 720 ]]; then
        history="${history: -720}"
    fi
    echo "$history" > "$state_file"
}

_calc_uptime_pct() {
    local name="$1"
    local state_file="${STATE_DIR}/${name}.uptime"
    [[ ! -f "$state_file" ]] && echo "100.0" && return
    local history; history=$(cat "$state_file")
    local total="${#history}"
    [[ $total -eq 0 ]] && echo "100.0" && return
    local up; up=$(echo "$history" | tr -cd '1' | wc -c)
    python3 -c "print(f'{$up/$total*100:.1f}')" 2>/dev/null || echo "100.0"
}

# ── Kumpulkan data semua server ───────────────────────────
NOW_WIB=$(TZ=Asia/Jakarta date "+%d %b %Y %H:%M:%S WIB")
TOTAL_UP=0
TOTAL_DOWN=0
TOTAL_AKUN=0

CARDS_HTML=""

LOCAL_DOMAIN=$(cat /etc/zv-manager/domain 2>/dev/null)

# Loop semua remote server
for conf in "$SERVER_DIR"/*.conf; do
    [[ -f "$conf" ]] || continue
    [[ "$conf" == *.tg.conf ]] && continue

    unset NAME IP DOMAIN PORT
    source "$conf"
    [[ -z "$NAME" || -z "$IP" ]] && continue

    # Baca label dari .tg.conf
    LABEL="$NAME"
    tgconf="${SERVER_DIR}/${NAME}.tg.conf"
    [[ -f "$tgconf" ]] && { source "$tgconf"; LABEL="${TG_SERVER_LABEL:-$NAME}"; }

    ms=$(_ping_ms "$IP")
    port_ok=$(_check_port "$IP" "${PORT:-22}")
    akun=$(_count_active "$NAME")
    TOTAL_AKUN=$((TOTAL_AKUN + akun))

    if [[ "$port_ok" == "1" ]]; then
        STATUS="UP"; STATUS_CLASS="up"; TOTAL_UP=$((TOTAL_UP+1))
        _update_uptime "$NAME" "1"
    else
        STATUS="DOWN"; STATUS_CLASS="down"; TOTAL_DOWN=$((TOTAL_DOWN+1))
        _update_uptime "$NAME" "0"
    fi

    uptime_pct=$(_calc_uptime_pct "$NAME")
    [[ $(echo "$uptime_pct >= 95" | bc -l) == "1" ]] && UPT_CLASS="green" \
        || { [[ $(echo "$uptime_pct >= 80" | bc -l) == "1" ]] && UPT_CLASS="yellow" || UPT_CLASS="red"; }

    CARDS_HTML+="
    <div class='card'>
      <div class='card-header'>
        <div class='card-title'>
          <span class='dot dot-${STATUS_CLASS}'></span>
          ${LABEL}
          <span class='domain'>${DOMAIN:-$IP}</span>
        </div>
        <span class='badge badge-${STATUS_CLASS}'>${STATUS}</span>
      </div>
      <div class='card-body'>
        <div class='stat'>
          <span class='stat-label'>UPTIME</span>
          <span class='stat-val ${UPT_CLASS}'>${uptime_pct}%</span>
        </div>
        <div class='stat'>
          <span class='stat-label'>RESPONSE</span>
          <span class='stat-val'>${ms} ms</span>
        </div>
        <div class='stat'>
          <span class='stat-label'>AKUN AKTIF</span>
          <span class='stat-val'>${akun}</span>
        </div>
        <div class='stat'>
          <span class='stat-label'>LAST CHECK</span>
          <span class='stat-val small'>$(TZ=Asia/Jakarta date '+%H:%M')</span>
        </div>
      </div>
    </div>"
done

TOTAL_SERVER=$((TOTAL_UP + TOTAL_DOWN))
[[ $TOTAL_SERVER -gt 0 ]] && \
    AVG_UPTIME=$(python3 -c "print(f'{$TOTAL_UP/$TOTAL_SERVER*100:.1f}')") || AVG_UPTIME="100.0"

[[ $TOTAL_DOWN -eq 0 ]] && SUMMARY_CLASS="all-up" SUMMARY_TEXT="All Systems Operational" \
    || SUMMARY_CLASS="some-down" SUMMARY_TEXT="${TOTAL_DOWN} Server Membutuhkan Perhatian"

# ── Generate HTML ─────────────────────────────────────────
cat > "$OUTPUT" << HTMLEOF
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta http-equiv="refresh" content="300">
<title>${PANEL_NAME} — Status</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    background: #0f1117;
    color: #e2e8f0;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
    min-height: 100vh;
    padding: 0 0 40px 0;
  }

  /* ── Header ── */
  .header {
    background: linear-gradient(135deg, #1a1f2e 0%, #161b27 100%);
    border-bottom: 1px solid #2d3748;
    padding: 24px 20px 20px;
    text-align: center;
  }
  .header-icon {
    width: 48px; height: 48px;
    background: linear-gradient(135deg, #3b82f6, #06b6d4);
    border-radius: 12px;
    display: inline-flex; align-items: center; justify-content: center;
    font-size: 22px; margin-bottom: 12px;
  }
  .header h1 { font-size: 20px; font-weight: 700; color: #f1f5f9; }
  .header p  { font-size: 13px; color: #64748b; margin-top: 4px; }
  .header-time {
    display: inline-flex; align-items: center; gap: 6px;
    font-size: 12px; color: #64748b; margin-top: 12px;
    background: #1e2535; border-radius: 20px; padding: 6px 14px;
  }

  /* ── Summary cards ── */
  .summary {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: 10px;
    padding: 16px;
    max-width: 600px;
    margin: 0 auto;
  }
  .sum-card {
    background: #1a1f2e;
    border: 1px solid #2d3748;
    border-radius: 14px;
    padding: 16px;
    display: flex; align-items: center; gap: 12px;
  }
  .sum-icon {
    width: 44px; height: 44px;
    border-radius: 12px;
    display: flex; align-items: center; justify-content: center;
    font-size: 20px; flex-shrink: 0;
  }
  .sum-icon.green { background: rgba(34,197,94,.15); }
  .sum-icon.red   { background: rgba(239,68,68,.15); }
  .sum-icon.blue  { background: rgba(59,130,246,.15); }
  .sum-icon.purple{ background: rgba(168,85,247,.15); }
  .sum-val  { font-size: 24px; font-weight: 700; line-height: 1; }
  .sum-val.green  { color: #22c55e; }
  .sum-val.red    { color: #ef4444; }
  .sum-val.blue   { color: #3b82f6; }
  .sum-val.purple { color: #a855f7; }
  .sum-label { font-size: 11px; color: #64748b; margin-top: 3px; text-transform: uppercase; letter-spacing: .5px; }

  /* ── Status bar ── */
  .status-bar {
    margin: 0 16px 16px;
    max-width: 568px;
    margin-left: auto; margin-right: auto;
    background: #1a1f2e;
    border: 1px solid #2d3748;
    border-radius: 12px;
    padding: 12px 16px;
    display: flex; align-items: center; gap: 10px;
    font-size: 13px;
  }
  .status-dot {
    width: 10px; height: 10px; border-radius: 50%; flex-shrink: 0;
  }
  .status-dot.all-up   { background: #22c55e; box-shadow: 0 0 8px #22c55e88; }
  .status-dot.some-down{ background: #ef4444; box-shadow: 0 0 8px #ef444488; }
  .status-bar-text { flex: 1; color: #cbd5e1; }
  .status-bar-avg  { font-size: 12px; color: #64748b; }

  /* ── Section title ── */
  .section-title {
    font-size: 12px; font-weight: 600; color: #64748b;
    text-transform: uppercase; letter-spacing: 1px;
    padding: 0 16px 10px;
    max-width: 600px; margin: 0 auto;
  }

  /* ── Server cards ── */
  .cards {
    display: flex; flex-direction: column; gap: 10px;
    padding: 0 16px;
    max-width: 600px;
    margin: 0 auto;
  }
  .card {
    background: #1a1f2e;
    border: 1px solid #2d3748;
    border-radius: 16px;
    overflow: hidden;
    transition: border-color .2s;
  }
  .card:hover { border-color: #3b82f6; }
  .card-header {
    display: flex; align-items: center; justify-content: space-between;
    padding: 14px 16px 12px;
    border-bottom: 1px solid #1e2535;
  }
  .card-title {
    display: flex; align-items: center; gap: 10px;
    font-size: 15px; font-weight: 600; color: #f1f5f9;
  }
  .domain {
    font-size: 11px; color: #475569; font-weight: 400;
    background: #1e2535; border-radius: 6px; padding: 2px 8px;
  }
  .dot {
    width: 9px; height: 9px; border-radius: 50%; flex-shrink: 0;
  }
  .dot-up   { background: #22c55e; box-shadow: 0 0 6px #22c55e88; animation: pulse 2s infinite; }
  .dot-down { background: #ef4444; }
  @keyframes pulse {
    0%,100% { box-shadow: 0 0 6px #22c55e88; }
    50%      { box-shadow: 0 0 12px #22c55ecc; }
  }
  .badge {
    font-size: 11px; font-weight: 700; letter-spacing: .5px;
    padding: 4px 10px; border-radius: 20px;
  }
  .badge-up   { background: rgba(34,197,94,.15); color: #22c55e; }
  .badge-down { background: rgba(239,68,68,.15);  color: #ef4444; }

  .card-body {
    display: grid; grid-template-columns: repeat(4, 1fr);
    padding: 12px 16px;
    gap: 8px;
  }
  .stat { }
  .stat-label {
    font-size: 10px; color: #475569; text-transform: uppercase;
    letter-spacing: .5px; margin-bottom: 4px;
  }
  .stat-val {
    font-size: 15px; font-weight: 600; color: #94a3b8;
  }
  .stat-val.green  { color: #22c55e; }
  .stat-val.yellow { color: #f59e0b; }
  .stat-val.red    { color: #ef4444; }
  .stat-val.small  { font-size: 13px; }

  /* ── Refresh button ── */
  .refresh-btn {
    background: #1e2535;
    border: 1px solid #3b82f6;
    color: #3b82f6;
    font-size: 12px;
    font-weight: 600;
    padding: 7px 16px;
    border-radius: 20px;
    cursor: pointer;
    transition: all .2s;
    white-space: nowrap;
    flex-shrink: 0;
  }
  .refresh-btn:hover { background: #3b82f6; color: #fff; }
  .refresh-btn:active { transform: scale(0.95); }
  .refresh-btn.loading { opacity: .6; pointer-events: none; }

  /* ── Footer ── */
  .footer {
    text-align: center; font-size: 12px; color: #334155;
    padding: 24px 16px 0;
  }
  .footer a { color: #3b82f6; text-decoration: none; }
</style>
</head>
<body>

<div class="header">
  <div class="header-icon">🖥️</div>
  <h1>${PANEL_NAME}</h1>
  <p>${LOCAL_DOMAIN}</p>
  <div class="header-time">🕐 ${NOW_WIB}</div>
</div>

<br>

<div class="summary">
  <div class="sum-card">
    <div class="sum-icon green">✅</div>
    <div>
      <div class="sum-val green">${TOTAL_UP}</div>
      <div class="sum-label">Server Up</div>
    </div>
  </div>
  <div class="sum-card">
    <div class="sum-icon red">❌</div>
    <div>
      <div class="sum-val red">${TOTAL_DOWN}</div>
      <div class="sum-label">Server Down</div>
    </div>
  </div>
  <div class="sum-card">
    <div class="sum-icon blue">👥</div>
    <div>
      <div class="sum-val blue">${TOTAL_AKUN}</div>
      <div class="sum-label">Akun Aktif</div>
    </div>
  </div>
  <div class="sum-card">
    <div class="sum-icon purple">📊</div>
    <div>
      <div class="sum-val purple">${AVG_UPTIME}%</div>
      <div class="sum-label">Avg Uptime</div>
    </div>
  </div>
</div>

<div class="status-bar">
  <div class="status-dot ${SUMMARY_CLASS}"></div>
  <div class="status-bar-text">${SUMMARY_TEXT}</div>
  <button class="refresh-btn" onclick="doRefresh()">🔄 Refresh</button>
</div>

<div class="section-title">STATUS SERVER</div>

<div class="cards">
${CARDS_HTML}
</div>

<div class="footer">
  Powered by <a href="#">${PANEL_NAME}</a> &nbsp;·&nbsp; Auto-refresh setiap 5 menit
</div>

<script>
function doRefresh() {
  var btn = document.querySelector('.refresh-btn');
  btn.classList.add('loading');
  btn.textContent = '⏳ Memuat...';
  setTimeout(function(){ location.reload(); }, 300);
}
</script>
</body>
</html>
HTMLEOF

# Fix permission
chown -R www-data:www-data "$WEB_DIR" 2>/dev/null
