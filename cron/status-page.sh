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

# ── Helper: hitung akun VMess aktif per server ───────────
_count_vmess_active() {
    local server_name="$1"
    local now_ts; now_ts=$(date +%s)
    local count=0
    for conf in /etc/zv-manager/accounts/vmess/*.conf; do
        [[ -f "$conf" ]] || continue
        local srv exp_ts
        srv=$(grep "^SERVER=" "$conf" | cut -d= -f2 | tr -d '"')
        exp_ts=$(grep "^EXPIRED_TS=" "$conf" | cut -d= -f2 | tr -d '"')
        [[ "$srv" == "$server_name" && -n "$exp_ts" && "$exp_ts" -gt "$now_ts" ]] && count=$((count+1))
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
    vakun=$(_count_vmess_active "$NAME")
    TOTAL_AKUN=$((TOTAL_AKUN + akun + vakun))

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
      <div class='chead'>
        <div class='cname'>
          <span class='dot dot-${STATUS_CLASS}'></span>
          ${LABEL}
          <span class='ctag'>${DOMAIN:-$IP}</span>
        </div>
        <span class='badge badge-${STATUS_CLASS}'>${STATUS}</span>
      </div>
      <div class='cbody'>
        <div>
          <div class='slbl'>UPTIME</div>
          <div class='sval ${UPT_CLASS}'>${uptime_pct}%</div>
        </div>
        <div>
          <div class='slbl'>RESPONSE</div>
          <div class='sval'>${ms} ms</div>
        </div>
        <div>
          <div class='slbl'>AKUN AKTIF</div>
          <div class='sval'>${akun} SSH · ${vakun} VMess</div>
        </div>
        <div>
          <div class='slbl'>LAST CHECK</div>
          <div class='sval sm'>$(TZ=Asia/Jakarta date '+%H:%M')</div>
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
    --bg:       #f5f7fa;
    --surface:  #ffffff;
    --border:   #e8ecf0;
    --text:     #1a202c;
    --text2:    #4a5568;
    --text3:    #a0aec0;
    --tag-bg:   #f0f4f8;
    --time-bg:  #edf2f7;
    --sep:      #f0f4f8;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg:       #0d1117;
      --surface:  #161b22;
      --border:   #21262d;
      --text:     #e6edf3;
      --text2:    #8b949e;
      --text3:    #484f58;
      --tag-bg:   #1c2128;
      --time-bg:  #1c2128;
      --sep:      #1c2128;
    }
  }
  * { margin:0; padding:0; box-sizing:border-box; }
  body {
    background: var(--bg);
    color: var(--text);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Inter", sans-serif;
    min-height: 100vh;
    padding-bottom: 48px;
  }

  /* ── Header ── */
  .header {
    background: var(--surface);
    border-bottom: 1px solid var(--border);
    padding: 24px 20px 20px;
    text-align: center;
  }
  .logo {
    width: 50px; height: 50px;
    background: linear-gradient(135deg, #2563eb 0%, #0ea5e9 100%);
    border-radius: 14px;
    display: inline-flex; align-items: center; justify-content: center;
    font-size: 22px; margin-bottom: 12px;
    box-shadow: 0 4px 12px rgba(37,99,235,.2);
  }
  .header h1 { font-size: 17px; font-weight: 700; color: var(--text); }
  .htime {
    display: inline-flex; align-items: center; gap: 5px;
    font-size: 12px; color: var(--text2);
    background: var(--time-bg); border: 1px solid var(--border);
    border-radius: 20px; padding: 5px 13px; margin-top: 10px;
  }

  /* ── Summary strip (horizontal scroll-safe) ── */
  .summary {
    display: grid; grid-template-columns: repeat(4,1fr);
    gap: 8px; padding: 14px 16px;
    max-width: 600px; margin: 0 auto;
  }
  @media (max-width: 360px) {
    .summary { grid-template-columns: repeat(2,1fr); }
  }
  .scard {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 12px; padding: 12px 10px;
    text-align: center;
  }
  .scard-val { font-size: 20px; font-weight: 700; line-height: 1; }
  .scard-val.green  { color: #16a34a; }
  .scard-val.red    { color: #dc2626; }
  .scard-val.blue   { color: #2563eb; }
  .scard-val.purple { color: #7c3aed; }
  @media (prefers-color-scheme: dark) {
    .scard-val.green  { color: #4ade80; }
    .scard-val.red    { color: #f87171; }
    .scard-val.blue   { color: #60a5fa; }
    .scard-val.purple { color: #c084fc; }
  }
  .scard-lbl { font-size: 10px; color: var(--text3); margin-top: 4px; text-transform: uppercase; letter-spacing: .4px; }

  /* ── Status pill ── */
  .spill {
    margin: 0 16px 14px; max-width: 568px;
    margin-left: auto; margin-right: auto;
    background: var(--surface); border: 1px solid var(--border);
    border-radius: 10px; padding: 10px 14px;
    display: flex; align-items: center; gap: 8px;
    font-size: 13px; color: var(--text2);
  }
  .sdot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
  .sdot.all-up    { background: #16a34a; box-shadow: 0 0 0 0 rgba(22,163,74,.4); animation: spulse 2s infinite; }
  .sdot.some-down { background: #dc2626; }
  @media (prefers-color-scheme: dark) {
    .sdot.all-up { background: #4ade80; }
    .sdot.some-down { background: #f87171; }
  }
  @keyframes spulse {
    0%,100% { box-shadow: 0 0 0 0 rgba(22,163,74,.4); }
    50%      { box-shadow: 0 0 0 5px rgba(22,163,74,0); }
  }
  .spill-text { flex: 1; }
  .spill-note { font-size: 11px; color: var(--text3); }

  /* ── Section label ── */
  .sec {
    font-size: 11px; font-weight: 600; color: var(--text3);
    text-transform: uppercase; letter-spacing: 1px;
    padding: 0 16px 8px; max-width: 600px; margin: 0 auto;
  }

  /* ── Cards — full width, vertical stack ── */
  .cards {
    display: flex; flex-direction: column; gap: 8px;
    padding: 0 16px; max-width: 600px; margin: 0 auto;
  }
  .card {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 14px; overflow: hidden;
    width: 100%;
  }

  /* Card header row */
  .chead {
    display: flex; align-items: center; justify-content: space-between;
    padding: 13px 14px 11px;
    border-bottom: 1px solid var(--sep);
  }
  .cname {
    display: flex; align-items: center; gap: 8px;
    font-size: 14px; font-weight: 600; color: var(--text);
    min-width: 0;
  }
  .ctag {
    font-size: 11px; color: var(--text3);
    background: var(--tag-bg); border: 1px solid var(--border);
    border-radius: 6px; padding: 2px 7px; font-weight: 400;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
    max-width: 150px;
  }
  .dot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
  .dot-up   { background: #16a34a; animation: dpulse 2s infinite; }
  .dot-down { background: #dc2626; }
  @media (prefers-color-scheme: dark) {
    .dot-up   { background: #4ade80; }
    .dot-down { background: #f87171; }
  }
  @keyframes dpulse {
    0%,100% { box-shadow: 0 0 0 0 rgba(22,163,74,.4); }
    50%      { box-shadow: 0 0 0 4px rgba(22,163,74,0); }
  }
  .badge { font-size: 11px; font-weight: 700; padding: 3px 10px; border-radius: 20px; flex-shrink:0; }
  .badge-up   { background: rgba(22,163,74,.1);  color: #16a34a; }
  .badge-down { background: rgba(220,38,38,.1);  color: #dc2626; }
  @media (prefers-color-scheme: dark) {
    .badge-up   { background: rgba(74,222,128,.12); color: #4ade80; }
    .badge-down { background: rgba(248,113,113,.12); color: #f87171; }
  }

  /* Card stats row — always 4 col */
  .cbody {
    display: grid; grid-template-columns: repeat(4,1fr);
    padding: 11px 14px; gap: 8px;
  }
  .slbl { font-size: 10px; color: var(--text3); text-transform: uppercase; letter-spacing: .4px; margin-bottom: 3px; }
  .sval { font-size: 14px; font-weight: 600; color: var(--text2); }
  .sval.green  { color: #16a34a; }
  .sval.yellow { color: #d97706; }
  .sval.red    { color: #dc2626; }
  .sval.sm     { font-size: 13px; }
  @media (prefers-color-scheme: dark) {
    .sval.green  { color: #4ade80; }
    .sval.yellow { color: #fbbf24; }
    .sval.red    { color: #f87171; }
  }

  /* ── Footer ── */
  .footer { text-align: center; font-size: 11px; color: var(--text3); padding: 20px 16px 0; }
</style>
</head>
<body>

<div class="header">
  <div class="logo">🖥️</div>
  <h1>${PANEL_NAME}</h1>
  <div class="htime">🕐 ${NOW_WIB}</div>
</div>

<br>

<div class="summary">
  <div class="scard">
    <div class="scard-val green">${TOTAL_UP}</div>
    <div class="scard-lbl">Up</div>
  </div>
  <div class="scard">
    <div class="scard-val red">${TOTAL_DOWN}</div>
    <div class="scard-lbl">Down</div>
  </div>
  <div class="scard">
    <div class="scard-val blue">${TOTAL_AKUN}</div>
    <div class="scard-lbl">Akun</div>
  </div>
  <div class="scard">
    <div class="scard-val purple">${AVG_UPTIME}%</div>
    <div class="scard-lbl">Uptime</div>
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

# Fix permission
chown -R www-data:www-data "$WEB_DIR" 2>/dev/null
