#!/bin/bash
# ============================================================
#   ZV-Manager - Bandwidth Tracking & Enforcement
#   Pakai iptables per-user untuk track & block
# ============================================================

ACCOUNT_DIR="/etc/zv-manager/accounts/ssh"
BW_LOG="/var/log/zv-manager/bandwidth.log"

_bw_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$BW_LOG" 2>/dev/null; }

# ── Bytes ↔ GB ──────────────────────────────────────────────
_bw_gb_to_bytes() { echo $(( ${1} * 1024 * 1024 * 1024 )); }
_bw_bytes_to_gb() {
    python3 -c "print(round(${1}/1024/1024/1024,2))" 2>/dev/null || echo "0"
}
_bw_fmt() {
    # Format bytes ke string human-readable (KB/MB/GB)
    local b="$1"
    python3 -c "
b=int('$b' or 0)
if b < 1024: print(f'{b} B')
elif b < 1024**2: print(f'{b/1024:.1f} KB')
elif b < 1024**3: print(f'{b/1024**2:.1f} MB')
else: print(f'{b/1024**3:.2f} GB')
" 2>/dev/null || echo "${b}B"
}

# ── iptables chain per user ──────────────────────────────────
_bw_chain()   { echo "BW_${1}"; }

_bw_init_user() {
    local user="$1"
    local chain; chain=$(_bw_chain "$user")
    # Buat chain kalau belum ada
    iptables -N "$chain" 2>/dev/null
    # Tambah rule counter di chain (RETURN = hitung lalu lanjut)
    iptables -C "$chain" -j RETURN 2>/dev/null || iptables -A "$chain" -j RETURN
    # Jump ke chain dari OUTPUT (traffic yang dikirim server ke user)
    iptables -C OUTPUT -m owner --uid-owner "$user" -j "$chain" 2>/dev/null || \
        iptables -I OUTPUT -m owner --uid-owner "$user" -j "$chain"
    _bw_log "INIT: $user"
}

# Baca bytes dari iptables dan RESET counter (return delta)
_bw_read_delta() {
    local user="$1"
    local chain; chain=$(_bw_chain "$user")
    # -nvxZ: verbose, no-resolve, exact, Zero setelah baca
    local bytes
    bytes=$(iptables -nvxZ "$chain" 2>/dev/null | awk '/RETURN/ {print $2; exit}')
    echo "${bytes:-0}"
}

# Hapus semua rules untuk user (saat akun dihapus)
_bw_cleanup_user() {
    local user="$1"
    local chain; chain=$(_bw_chain "$user")
    iptables -D OUTPUT -m owner --uid-owner "$user" -j "$chain" 2>/dev/null
    iptables -F "$chain" 2>/dev/null
    iptables -X "$chain" 2>/dev/null
    _bw_log "CLEANUP: $user"
}

# ── Block / Unblock ──────────────────────────────────────────
_bw_is_blocked() {
    local user="$1"
    grep -q "^BW_BLOCKED=1" "${ACCOUNT_DIR}/${user}.conf" 2>/dev/null
}

_bw_block() {
    local user="$1"
    local conf="${ACCOUNT_DIR}/${user}.conf"
    [[ ! -f "$conf" ]] && return 1
    # Kick semua sesi aktif
    pkill -u "$user" -KILL 2>/dev/null
    # Tambah DROP rule di OUTPUT
    iptables -I OUTPUT -m owner --uid-owner "$user" -j DROP 2>/dev/null
    # Lock akun di sistem
    passwd -l "$user" &>/dev/null
    # Tandai di conf
    if grep -q "^BW_BLOCKED=" "$conf"; then
        sed -i "s/^BW_BLOCKED=.*/BW_BLOCKED=1/" "$conf"
    else
        echo "BW_BLOCKED=1" >> "$conf"
    fi
    _bw_log "BLOCKED: $user"
}

_bw_unblock() {
    local user="$1"
    local conf="${ACCOUNT_DIR}/${user}.conf"
    [[ ! -f "$conf" ]] && return 1
    # Hapus DROP rule
    iptables -D OUTPUT -m owner --uid-owner "$user" -j DROP 2>/dev/null
    # Unlock akun
    passwd -u "$user" &>/dev/null
    # Update conf
    if grep -q "^BW_BLOCKED=" "$conf"; then
        sed -i "s/^BW_BLOCKED=.*/BW_BLOCKED=0/" "$conf"
    else
        echo "BW_BLOCKED=0" >> "$conf"
    fi
    _bw_log "UNBLOCKED: $user"
}

# ── Quota management ─────────────────────────────────────────
_bw_get_quota() {
    local conf="${ACCOUNT_DIR}/${1}.conf"
    local q; q=$(grep "^BW_QUOTA_BYTES=" "$conf" 2>/dev/null | cut -d= -f2 | tr -d "[:space:]")
    echo "${q:-0}"
}

_bw_get_used() {
    local conf="${ACCOUNT_DIR}/${1}.conf"
    local u; u=$(grep "^BW_USED_BYTES=" "$conf" 2>/dev/null | cut -d= -f2 | tr -d "[:space:]")
    echo "${u:-0}"
}

_bw_add_quota() {
    local user="$1" add_bytes="$2"
    local conf="${ACCOUNT_DIR}/${user}.conf"
    local cur; cur=$(_bw_get_quota "$user")
    local new=$(( cur + add_bytes ))
    if grep -q "^BW_QUOTA_BYTES=" "$conf"; then
        sed -i "s/^BW_QUOTA_BYTES=.*/BW_QUOTA_BYTES=${new}/" "$conf"
    else
        echo "BW_QUOTA_BYTES=${new}" >> "$conf"
    fi
    _bw_log "ADD_QUOTA: $user +${add_bytes}B total=${new}B"
}

# Akumulasi delta ke BW_USED_BYTES di conf
_bw_accumulate() {
    local user="$1"
    local conf="${ACCOUNT_DIR}/${user}.conf"
    [[ ! -f "$conf" ]] && return
    local delta; delta=$(_bw_read_delta "$user")
    [[ "$delta" -eq 0 ]] && return
    local cur; cur=$(_bw_get_used "$user")
    local new=$(( cur + delta ))
    if grep -q "^BW_USED_BYTES=" "$conf"; then
        sed -i "s/^BW_USED_BYTES=.*/BW_USED_BYTES=${new}/" "$conf"
    else
        echo "BW_USED_BYTES=${new}" >> "$conf"
    fi
    echo "$new"  # return new total
}

# ── Progress bar ──────────────────────────────────────────────
_bw_progress_bar() {
    local used="$1" quota="$2"
    [[ "$quota" -eq 0 ]] && { echo "∞ (Unlimited)"; return; }
    python3 -c "
used,quota=int('$used'),int('$quota')
pct=min(100,int(used/quota*100)) if quota>0 else 0
filled=int(pct/10)
bar='█'*filled+'░'*(10-filled)
print(f'{bar} {pct}%')
" 2>/dev/null || echo "?"
}
