#!/bin/bash
# ============================================================
#   ZV-Manager - Color Definitions
# ============================================================

# Reset
NC='\033[0m'

# Regular Colors
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'

# Bold
BOLD='\033[1m'
BRED='\033[1;31m'
BGREEN='\033[1;32m'
BYELLOW='\033[1;33m'
BBLUE='\033[1;34m'
BPURPLE='\033[1;35m'
BCYAN='\033[1;36m'
BWHITE='\033[1;37m'

# Underline
UWHITE='\033[4;37m'

# Background
ON_RED='\033[41m'
ON_GREEN='\033[42m'
ON_YELLOW='\033[43m'

# ── True color gradient helpers ───────────────────────────────
# _grad "text" r1 g1 b1 r2 g2 b2  → gradient kiri ke kanan
_grad() {
    local text="$1" r1=$2 g1=$3 b1=$4 r2=$5 g2=$6 b2=$7 nc="\e[0m"
    local len=0
    for (( c=0; c<${#text}; c++ )); do [[ "${text:$c:1}" != " " ]] && len=$((len+1)); done
    [[ $len -le 1 ]] && len=2
    local i=0 out=""
    for (( c=0; c<${#text}; c++ )); do
        local ch="${text:$c:1}"
        if [[ "$ch" == " " ]]; then out+=" "
        else
            local r=$(( r1 + (r2-r1)*i/(len-1) ))
            local g=$(( g1 + (g2-g1)*i/(len-1) ))
            local b=$(( b1 + (b2-b1)*i/(len-1) ))
            out+="\e[1;38;2;${r};${g};${b}m${ch}${nc}"
            i=$((i+1))
        fi
    done
    echo -e "$out"
}

# Garis separator gradient pakai = (konsisten dengan header)
_sep() {
    local width=${1:-50}
    local str; str=$(printf '=%.0s' $(seq 1 $width))
    _grad "$str" 0 180 255  120 0 255
}

# Header section dengan gradient
_section() {
    local title="$1"
    _sep
    _grad " >>> $title <<<" 0 210 255  160 80 255
    _sep
}
