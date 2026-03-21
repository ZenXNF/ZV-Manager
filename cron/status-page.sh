#!/bin/bash
# ============================================================
#   ZV-Manager - Status Page Generator
#   Cron: */5 * * * *
#   Generate /var/www/zv-manager/data.json
#   index.html dibuat sekali saat setup-web.sh, tidak dioverwrite
# ============================================================

SERVER_DIR="/etc/zv-manager/servers"
WEB_DIR="/var/www/zv-manager"
STATE_DIR="/var/lib/zv-manager/status"
DATA_JSON="${WEB_DIR}/data.json"
INDEX_HTML="${WEB_DIR}/index.html"
PANEL_NAME=$(grep "^PANEL_NAME=" /etc/zv-manager/config.conf 2>/dev/null | cut -d= -f2 | tr -d '"')
PANEL_NAME="${PANEL_NAME:-ZV}"

mkdir -p "$WEB_DIR" "$STATE_DIR"

# ── Helpers ───────────────────────────────────────────────
_ping_ms() {
    local ip="$1"
    local ms; ms=$(ping -c 1 -W 2 "$ip" 2>/dev/null | grep "time=" | sed 's/.*time=\([0-9.]*\).*/\1/')
    echo "${ms:-0}"
}

_check_port() {
    nc -zw2 "$1" "$2" &>/dev/null && echo "1" || echo "0"
}

_update_uptime() {
    local name="$1" status="$2"
    local f="${STATE_DIR}/${name}.uptime"
    local h=""; [[ -f "$f" ]] && h=$(cat "$f")
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

_escape_json() {
    python3 -c "import json,sys; print(json.dumps(sys.stdin.read().strip()))" <<< "$1" | tr -d '"'
}

# ── Kumpulkan data server ─────────────────────────────────
NOW_WIB=$(TZ=Asia/Jakarta date "+%d %b %Y %H:%M:%S WIB")
NOW_TS=$(date +%s)
TOTAL_UP=0
TOTAL_DOWN=0
SERVERS_JSON=""

for conf in "$SERVER_DIR"/*.conf; do
    [[ -f "$conf" ]] || continue
    [[ "$conf" == *.tg.conf ]] && continue

    unset NAME IP DOMAIN PORT ISP
    source "$conf"
    [[ -z "$NAME" ]] && continue

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
        STATUS="UP"; TOTAL_UP=$((TOTAL_UP+1))
        _update_uptime "$NAME" "1"
    else
        STATUS="DOWN"; TOTAL_DOWN=$((TOTAL_DOWN+1))
        _update_uptime "$NAME" "0"
    fi

    uptime_pct=$(_calc_uptime_pct "$NAME")
    DISPLAY_HOST="${DOMAIN:-$IP}"
    LAST_CHECK=$(TZ=Asia/Jakarta date '+%H:%M')

    SERVERS_JSON+=$(cat << JSONEOF
{
  "name": "$(echo "$LABEL" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read().strip()))'| tr -d '"')",
  "host": "$(echo "$DISPLAY_HOST" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read().strip()))' | tr -d '"')",
  "isp": "$(echo "${ISP:-}" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read().strip()))' | tr -d '"')",
  "status": "$STATUS",
  "uptime": "$uptime_pct",
  "response": "$ms",
  "last_check": "$LAST_CHECK"
},
JSONEOF
)
done

TOTAL_SERVER=$((TOTAL_UP + TOTAL_DOWN))
[[ $TOTAL_SERVER -gt 0 ]] && \
    AVG_UPTIME=$(python3 -c "print(f'{$TOTAL_UP/$TOTAL_SERVER*100:.1f}')") || AVG_UPTIME="100.0"

# Hapus trailing koma dari server terakhir
SERVERS_JSON="${SERVERS_JSON%,}"

cat > "$DATA_JSON" << JSONEOF
{
  "updated": "$NOW_WIB",
  "updated_ts": $NOW_TS,
  "panel": "$(echo "$PANEL_NAME" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read().strip()))' | tr -d '"')",
  "total_up": $TOTAL_UP,
  "total_down": $TOTAL_DOWN,
  "avg_uptime": "$AVG_UPTIME",
  "servers": [${SERVERS_JSON}]
}
JSONEOF

# ── Generate index.html jika belum ada ────────────────────
if [[ ! -f "$INDEX_HTML" ]]; then
    _gen_index
fi

chown -R www-data:www-data "$WEB_DIR" 2>/dev/null

_gen_index() {
cat > "$INDEX_HTML" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Server Status</title>
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
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    min-height: 100vh;
    padding-bottom: 48px;
  }
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
    font-size: 15px; font-weight: 800; color: white;
    margin-bottom: 10px;
    box-shadow: 0 4px 14px rgba(37,99,235,.35);
  }
  .header h1 { font-size: 16px; font-weight: 700; }
  .htime {
    display: inline-flex; align-items: center; gap: 5px;
    font-size: 12px; color: var(--text2);
    background: var(--tag-bg); border: 1px solid var(--border);
    border-radius: 20px; padding: 4px 12px; margin-top: 9px;
  }
  .refresh-btn {
    display: block; width: calc(100% - 32px); max-width: 468px;
    margin: 14px auto 0;
    background: #2563eb; color: white;
    border: none; border-radius: 10px;
    padding: 10px; font-size: 13px; font-weight: 600;
    cursor: pointer; transition: opacity .2s;
  }
  .refresh-btn:hover { opacity: .85; }
  .refresh-btn:active { opacity: .7; }
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
  .green { color: #4ade80; }
  .red   { color: #f87171; }
  .blue  { color: #60a5fa; }
  .yellow { color: #fbbf24; }
  .scard-lbl { font-size: 10px; color: var(--text3); margin-top: 5px; text-transform: uppercase; letter-spacing: .5px; }
  .spill {
    margin: 0 16px 14px; max-width: 468px;
    margin-left: auto; margin-right: auto;
    background: var(--surface); border: 1px solid var(--border);
    border-radius: 10px; padding: 10px 14px;
    display: flex; align-items: center; gap: 9px;
    font-size: 13px; color: var(--text2);
  }
  .sdot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
  .sdot.all-up { background: #4ade80; animation: spulse 2s infinite; }
  .sdot.some-down { background: #f87171; }
  @keyframes spulse {
    0%,100% { box-shadow: 0 0 0 0 rgba(74,222,128,.4); }
    50%      { box-shadow: 0 0 0 5px rgba(74,222,128,0); }
  }
  .spill-text { flex: 1; }
  .spill-note { font-size: 11px; color: var(--text3); }
  .sec {
    font-size: 11px; font-weight: 600; color: var(--text3);
    text-transform: uppercase; letter-spacing: 1px;
    padding: 0 16px 8px; max-width: 500px; margin: 0 auto;
  }
  .cards {
    display: flex; flex-direction: column; gap: 8px;
    padding: 0 16px; max-width: 500px; margin: 0 auto;
  }
  .card {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 14px; overflow: hidden;
    animation: fadeIn .3s ease;
  }
  @keyframes fadeIn { from { opacity:0; transform:translateY(4px); } to { opacity:1; transform:none; } }
  .chead {
    display: flex; align-items: center; justify-content: space-between;
    padding: 13px 14px 11px;
    border-bottom: 1px solid var(--border);
  }
  .cname { display: flex; align-items: center; gap: 8px; min-width: 0; }
  .clabel { font-size: 14px; font-weight: 600; white-space: nowrap; }
  .ctag {
    font-size: 11px; color: var(--text3);
    background: var(--tag-bg); border: 1px solid var(--border);
    border-radius: 6px; padding: 2px 7px;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 130px;
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
  .cbody { display: grid; grid-template-columns: repeat(4,1fr); padding: 11px 14px; gap: 6px; }
  .slbl { font-size: 10px; color: var(--text3); text-transform: uppercase; letter-spacing: .4px; margin-bottom: 3px; }
  .sval { font-size: 14px; font-weight: 600; color: var(--text2); }
  .sval.sm { font-size: 13px; }
  .cisp { font-size: 11px; color: var(--text3); padding: 8px 14px 10px; border-top: 1px solid var(--border); }
  .footer { text-align: center; font-size: 11px; color: var(--text3); padding: 20px 16px 0; }
  .loading { text-align:center; color: var(--text3); padding: 40px; font-size: 13px; }
</style>
</head>
<body>

<div class="header">
  <div class="logo" id="panel-logo">ZV</div>
  <h1 id="panel-name">Server Status</h1>
  <div class="htime">🕐 <span id="last-updated">Memuat...</span></div>
  <button class="refresh-btn" onclick="fetchData()">↻ Refresh</button>
</div>

<br>

<div class="summary">
  <div class="scard">
    <div class="scard-val green" id="total-up">—</div>
    <div class="scard-lbl">Services Up</div>
  </div>
  <div class="scard">
    <div class="scard-val red" id="total-down">—</div>
    <div class="scard-lbl">Services Down</div>
  </div>
  <div class="scard">
    <div class="scard-val blue" id="avg-uptime">—</div>
    <div class="scard-lbl">Avg. Uptime</div>
  </div>
</div>

<div class="spill" id="status-pill">
  <div class="sdot all-up" id="status-dot"></div>
  <div class="spill-text" id="status-text">Memuat data...</div>
  <div class="spill-note" id="refresh-note">Auto-refresh 30 dtk</div>
</div>

<div class="sec">Status Server</div>
<div class="cards" id="cards-container">
  <div class="loading">Memuat data server...</div>
</div>

<div class="footer" id="footer-text">ZV-Manager · Update setiap 5 menit</div>

<script>
let countdown = 30;
let timer;

function fetchData() {
  clearInterval(timer);
  countdown = 30;
  document.getElementById('refresh-note').textContent = 'Memperbarui...';

  fetch('data.json?_=' + Date.now())
    .then(r => r.json())
    .then(d => {
      renderData(d);
      startCountdown();
    })
    .catch(() => {
      document.getElementById('refresh-note').textContent = 'Gagal memuat';
      startCountdown();
    });
}

function renderData(d) {
  document.getElementById('panel-logo').textContent = d.panel || 'ZV';
  document.getElementById('panel-name').textContent = d.panel || 'Server Status';
  document.getElementById('last-updated').textContent = d.updated || '—';
  document.getElementById('total-up').textContent = d.total_up;
  document.getElementById('total-down').textContent = d.total_down;
  document.getElementById('avg-uptime').textContent = d.avg_uptime + '%';
  document.getElementById('footer-text').textContent = (d.panel || 'ZV-Manager') + ' · Update setiap 5 menit';

  const dot = document.getElementById('status-dot');
  const txt = document.getElementById('status-text');
  if (d.total_down === 0) {
    dot.className = 'sdot all-up';
    txt.textContent = 'All Systems Operational';
  } else {
    dot.className = 'sdot some-down';
    txt.textContent = d.total_down + ' Server Membutuhkan Perhatian';
  }

  const container = document.getElementById('cards-container');
  container.innerHTML = '';
  (d.servers || []).forEach(s => {
    const isUp = s.status === 'UP';
    const upt = parseFloat(s.uptime);
    const uptClass = upt >= 95 ? 'green' : upt >= 80 ? 'yellow' : 'red';
    const ms = parseFloat(s.response);
    const msDisp = ms > 0 ? ms.toFixed(1) + ' ms' : '— ms';
    const ispLine = s.isp ? `<div class="cisp">📡 ${s.isp}</div>` : '';

    container.innerHTML += `
      <div class="card">
        <div class="chead">
          <div class="cname">
            <span class="dot ${isUp ? 'dot-up' : 'dot-down'}"></span>
            <span class="clabel">${s.name}</span>
            <span class="ctag">${s.host}</span>
          </div>
          <span class="badge ${isUp ? 'badge-up' : 'badge-down'}">${s.status}</span>
        </div>
        <div class="cbody">
          <div class="cstat">
            <div class="slbl">UPTIME</div>
            <div class="sval ${uptClass}">${s.uptime}%</div>
          </div>
          <div class="cstat">
            <div class="slbl">RESPONSE</div>
            <div class="sval">${msDisp}</div>
          </div>
          <div class="cstat">
            <div class="slbl">STATUS</div>
            <div class="sval">${isUp ? 'OK' : 'DOWN'}</div>
          </div>
          <div class="cstat">
            <div class="slbl">LAST CHECK</div>
            <div class="sval sm">${s.last_check}</div>
          </div>
        </div>
        ${ispLine}
      </div>`;
  });
}

function startCountdown() {
  clearInterval(timer);
  countdown = 30;
  timer = setInterval(() => {
    countdown--;
    document.getElementById('refresh-note').textContent = 'Refresh dalam ' + countdown + 's';
    if (countdown <= 0) fetchData();
  }, 1000);
}

fetchData();
</script>
</body>
</html>
HTMLEOF
}

