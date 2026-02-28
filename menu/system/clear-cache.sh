#!/bin/bash
# ============================================================
#   ZV-Manager - Clear Cache
# ============================================================
source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/utils/logger.sh

clear_cache() {
    clear
    print_section "Membersihkan Cache"
    sync && echo 3 > /proc/sys/vm/drop_caches
    apt-get autoremove -y &>/dev/null
    apt-get autoclean -y &>/dev/null
    journalctl --vacuum-time=3d &>/dev/null
    print_ok "Cache berhasil dibersihkan"
    press_any_key
}

clear_cache
