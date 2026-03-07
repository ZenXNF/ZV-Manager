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
      <div class='card-head'>
        <div class='card-name'>
          <span class='dot dot-${STATUS_CLASS}'></span>
          ${LABEL}
          <span class='ctag'>${DOMAIN:-$IP}</span>
        </div>
        <span class='badge badge-${STATUS_CLASS}'>${STATUS}</span>
      </div>
      <div class='card-body'>
        <div class='stat'>
          <div class='stat-label'>UPTIME</div>
          <div class='stat-val ${UPT_CLASS}'>${uptime_pct}%</span>
        </div>
        <div class='stat'>
          <div class='stat-label'>RESPONSE</div>
          <div class='stat-val'>${ms} ms</div>
        </div>
        <div class='stat'>
          <div class='stat-label'>AKUN AKTIF</div>
          <div class='stat-val'>${akun}</div>
        </div>
        <div class='stat'>
          <div class='stat-label'>LAST CHECK</div>
          <div class='stat-val small'>$(TZ=Asia/Jakarta date '+%H:%M')</span>
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
<title>${PANEL_NAME} — Server Status</title>
<style>
  :root {
    --bg:        #f0f4f8;
    --bg2:       #ffffff;
    --border:    #e2e8f0;
    --border2:   #edf2f7;
    --text:      #1a202c;
    --text2:     #4a5568;
    --text3:     #718096;
    --card-bg:   #ffffff;
    --header-bg: #ffffff;
    --tag-bg:    #f7fafc;
    --time-bg:   #f0f4f8;
    --section:   #718096;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg:        #0d1117;
      --bg2:       #161b22;
      --border:    #21262d;
      --border2:   #1c2128;
      --text:      #e6edf3;
      --text2:     #8b949e;
      --text3:     #484f58;
      --card-bg:   #161b22;
      --header-bg: #161b22;
      --tag-bg:    #1c2128;
      --time-bg:   #1c2128;
      --section:   #484f58;
    }
  }

  * { margin: 0; padding: 0; box-sizing: border-box; }

  body {
    background: var(--bg);
    color: var(--text);
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Inter', sans-serif;
    min-height: 100vh;
    padding-bottom: 48px;
  }

  /* ── Header ── */
  .header {
    background: var(--header-bg);
    border-bottom: 1px solid var(--border);
    padding: 28px 20px 22px;
    text-align: center;
  }
  .header-logo {
    width: 52px; height: 52px;
    background: linear-gradient(135deg, #2563eb, #0ea5e9);
    border-radius: 14px;
    display: inline-flex; align-items: center; justify-content: center;
    font-size: 24px; margin-bottom: 14px;
    box-shadow: 0 4px 14px rgba(37,99,235,.25);
  }
  .header h1 {
    font-size: 18px; font-weight: 700;
    color: var(--text); letter-spacing: -.3px;
  }
  .header-time {
    display: inline-flex; align-items: center; gap: 6px;
    font-size: 12px; color: var(--text2);
    margin-top: 10px;
    background: var(--time-bg);
    border: 1px solid var(--border);
    border-radius: 20px; padding: 5px 14px;
  }

  /* ── Summary ── */
  .summary {
    display: grid; grid-template-columns: repeat(2, 1fr);
    gap: 10px; padding: 16px;
    max-width: 560px; margin: 0 auto;
  }
  .sum-card {
    background: var(--card-bg);
    border: 1px solid var(--border);
    border-radius: 14px;
    padding: 16px 14px;
    display: flex; align-items: center; gap: 12px;
  }
  .sum-icon {
    width: 40px; height: 40px; border-radius: 10px;
    display: flex; align-items: center; justify-content: center;
    font-size: 18px; flex-shrink: 0;
  }
  .sum-icon.green  { background: rgba(22,163,74,.1); }
  .sum-icon.red    { background: rgba(220,38,38,.1); }
  .sum-icon.blue   { background: rgba(37,99,235,.1); }
  .sum-icon.purple { background: rgba(124,58,237,.1); }
  .sum-val { font-size: 22px; font-weight: 700; line-height: 1; }
  .sum-val.green  { color: #16a34a; }
  .sum-val.red    { color: #dc2626; }
  .sum-val.blue   { color: #2563eb; }
  .sum-val.purple { color: #7c3aed; }
  @media (prefers-color-scheme: dark) {
    .sum-val.green  { color: #4ade80; }
    .sum-val.red    { color: #f87171; }
    .sum-val.blue   { color: #60a5fa; }
    .sum-val.purple { color: #c084fc; }
  }
  .sum-label { font-size: 11px; color: var(--text3); margin-top: 3px; text-transform: uppercase; letter-spacing: .4px; }

  /* ── Status bar ── */
  .status-bar {
    margin: 0 16px 14px; max-width: 528px;
    margin-left: auto; margin-right: auto;
    background: var(--card-bg);
    border: 1px solid var(--border);
    border-radius: 10px;
    padding: 11px 14px;
    display: flex; align-items: center; gap: 9px;
    font-size: 13px; color: var(--text2);
  }
  .sdot {
    width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0;
  }
  .sdot.all-up    { background: #16a34a; box-shadow: 0 0 6px #16a34a66; }
  .sdot.some-down { background: #dc2626; box-shadow: 0 0 6px #dc262666; }
  @media (prefers-color-scheme: dark) {
    .sdot.all-up    { background: #4ade80; box-shadow: 0 0 6px #4ade8066; }
    .sdot.some-down { background: #f87171; box-shadow: 0 0 6px #f8717166; }
  }
  .sbar-text { flex: 1; }
  .sbar-note { font-size: 11px; color: var(--text3); }

  /* ── Section label ── */
  .sec-label {
    font-size: 11px; font-weight: 600; color: var(--section);
    text-transform: uppercase; letter-spacing: 1px;
    padding: 0 16px 8px;
    max-width: 560px; margin: 0 auto;
  }

  /* ── Cards ── */
  .cards {
    display: flex; flex-direction: column; gap: 8px;
    padding: 0 16px; max-width: 560px; margin: 0 auto;
  }
  .card {
    background: var(--card-bg);
    border: 1px solid var(--border);
    border-radius: 14px; overflow: hidden;
  }
  .card-head {
    display: flex; align-items: center; justify-content: space-between;
    padding: 13px 14px 11px;
    border-bottom: 1px solid var(--border2);
  }
  .card-name {
    display: flex; align-items: center; gap: 9px;
    font-size: 14px; font-weight: 600; color: var(--text);
  }
  .ctag {
    font-size: 11px; color: var(--text3);
    background: var(--tag-bg);
    border: 1px solid var(--border);
    border-radius: 6px; padding: 2px 7px;
    font-weight: 400;
  }
  .dot {
    width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0;
  }
  .dot-up   { background: #16a34a; animation: pulse 2s infinite; }
  .dot-down { background: #dc2626; }
  @media (prefers-color-scheme: dark) {
    .dot-up { background: #4ade80; }
    .dot-down { background: #f87171; }
  }
  @keyframes pulse {
    0%,100% { box-shadow: 0 0 0 0 rgba(22,163,74,.4); }
    50%      { box-shadow: 0 0 0 4px rgba(22,163,74,0); }
  }
  @media (prefers-color-scheme: dark) {
    @keyframes pulse {
      0%,100% { box-shadow: 0 0 0 0 rgba(74,222,128,.4); }
      50%      { box-shadow: 0 0 0 4px rgba(74,222,128,0); }
    }
  }
  .badge {
    font-size: 11px; font-weight: 700;
    padding: 3px 9px; border-radius: 20px; letter-spacing: .3px;
  }
  .badge-up   { background: rgba(22,163,74,.1);  color: #16a34a; }
  .badge-down { background: rgba(220,38,38,.1);  color: #dc2626; }
  @media (prefers-color-scheme: dark) {
    .badge-up   { background: rgba(74,222,128,.12); color: #4ade80; }
    .badge-down { background: rgba(248,113,113,.12); color: #f87171; }
  }

  .card-body {
    display: grid; grid-template-columns: repeat(2, 1fr);
    padding: 11px 14px; gap: 10px;
  }
  @media (min-width: 400px) {
    .card-body { grid-template-columns: repeat(4, 1fr); }
  }
  .stat-label {
    font-size: 10px; color: var(--text3);
    text-transform: uppercase; letter-spacing: .4px; margin-bottom: 3px;
  }
  .stat-val {
    font-size: 14px; font-weight: 600; color: var(--text2);
  }
  .stat-val.green  { color: #16a34a; }
  .stat-val.yellow { color: #d97706; }
  .stat-val.red    { color: #dc2626; }
  .stat-val.sm     { font-size: 13px; }
  @media (prefers-color-scheme: dark) {
    .stat-val.green  { color: #4ade80; }
    .stat-val.yellow { color: #fbbf24; }
    .stat-val.red    { color: #f87171; }
  }

  /* ── Footer ── */
  .footer {
    text-align: center; font-size: 11px; color: var(--text3);
    padding: 24px 16px 0;
  }
</style>
</head>
<body>

<div class="header">
  <div class="header-logo">🖥️</div>
  <h1>${PANEL_NAME}</h1>
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
  <div class="sdot ${SUMMARY_CLASS}"></div>
  <div class="sbar-text">${SUMMARY_TEXT}</div>
  <div class="sbar-note">Auto-refresh 5 menit</div>
</div>

<div class="sec-label">Status Server</div>

<div class="cards">
${CARDS_HTML}
</div>

<div class="footer">
  ${PANEL_NAME} &nbsp;·&nbsp; Update otomatis setiap 5 menit
</div>

</body>
</html>
HTMLEOF

# Fix permission
chown -R www-data:www-data "$WEB_DIR" 2>/dev/null
