#!/bin/bash
# ============================================================
#   ZV-Manager - Logger / Print Functions
# ============================================================

source "$(dirname "$0")/../../utils/colors.sh" 2>/dev/null || \
source "$(dirname "$0")/../utils/colors.sh" 2>/dev/null || \
source "/etc/zv-manager/utils/colors.sh" 2>/dev/null

LOG_FILE="/var/log/zv-manager/install.log"

# --- Print Functions ---
print_ok() {
    echo -e "${BGREEN} ✔ ${NC} $1"
    echo "[OK] $1" >> "$LOG_FILE" 2>/dev/null
}

print_error() {
    echo -e "${BRED} ✘ ${NC} $1"
    echo "[ERROR] $1" >> "$LOG_FILE" 2>/dev/null
}

print_info() {
    echo -e "${BCYAN} ℹ ${NC} $1"
    echo "[INFO] $1" >> "$LOG_FILE" 2>/dev/null
}

print_warning() {
    echo -e "${BYELLOW} ⚠ ${NC} $1"
    echo "[WARN] $1" >> "$LOG_FILE" 2>/dev/null
}

print_section() {
    echo ""
    echo -e "${BYELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BWHITE}  $1${NC}"
    echo -e "${BYELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_success() {
    echo ""
    echo -e "${BGREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BGREEN}  ✔ $1 berhasil dipasang${NC}"
    echo -e "${BGREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    sleep 1
}

# --- Timer ---
timer_start() {
    TIMER_START=$(date +%s)
}

timer_end() {
    local elapsed=$(( $(date +%s) - TIMER_START ))
    local hours=$(( elapsed / 3600 ))
    local minutes=$(( (elapsed % 3600) / 60 ))
    local seconds=$(( elapsed % 60 ))
    echo -e "${BCYAN}Waktu instalasi: ${hours}h ${minutes}m ${seconds}s${NC}"
}
