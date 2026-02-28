#!/bin/bash
# ============================================================
#   ZV-Manager - Server Info
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/helpers.sh

show_server_info() {
    clear

    local ip domain os kernel uptime cpu ram_used ram_total disk
    ip=$(curl -s --max-time 5 ipv4.icanhazip.com 2>/dev/null)
    domain=$(cat /etc/zv-manager/domain 2>/dev/null)
    os=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
    kernel=$(uname -r)
    uptime=$(uptime -p | sed 's/up //')
    cpu=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    ram_used=$(free -m | awk '/Mem:/ {print $3}')
    ram_total=$(free -m | awk '/Mem:/ {print $2}')
    disk=$(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')

    echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
    echo -e " │             ${BWHITE}INFORMASI SERVER${NC}                  │"
    echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BWHITE}IP Publik   :${NC} ${BGREEN}${ip}${NC}"
    echo -e "  ${BWHITE}Domain/Host :${NC} ${BGREEN}${domain}${NC}"
    echo -e "  ${BWHITE}OS          :${NC} ${BGREEN}${os}${NC}"
    echo -e "  ${BWHITE}Kernel      :${NC} ${BGREEN}${kernel}${NC}"
    echo -e "  ${BWHITE}Uptime      :${NC} ${BGREEN}${uptime}${NC}"
    echo -e "  ${BWHITE}CPU Usage   :${NC} ${BYELLOW}${cpu}%${NC}"
    echo -e "  ${BWHITE}RAM         :${NC} ${BYELLOW}${ram_used}MB / ${ram_total}MB${NC}"
    echo -e "  ${BWHITE}Disk        :${NC} ${BYELLOW}${disk}${NC}"
    echo ""
    echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
    echo -e " │               ${BWHITE}PORT AKTIF${NC}                     │"
    echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BWHITE}OpenSSH     :${NC} ${BPURPLE}22, 500, 40000${NC}"
    echo -e "  ${BWHITE}Dropbear    :${NC} ${BPURPLE}109, 143${NC}"
    echo -e "  ${BWHITE}WS HTTP     :${NC} ${BPURPLE}80${NC}"
    echo -e "  ${BWHITE}WS HTTPS    :${NC} ${BPURPLE}443${NC}"
    echo -e "  ${BWHITE}UDP Custom  :${NC} ${BPURPLE}1-65535${NC}"
    echo -e "  ${BWHITE}UDPGW       :${NC} ${BPURPLE}7100-7900${NC}"
    echo ""

    press_any_key
}

show_server_info
