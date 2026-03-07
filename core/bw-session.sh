#!/bin/bash
# ============================================================
#   ZV-Manager - BW Session Tracker (PAM)
#   Dipanggil via pam_exec.so saat SSH session open/close
#   PAM_USER = username, PAM_RHOST = IP client, PAM_TYPE = open/close
# ============================================================
SESSION_DIR="/tmp/zv-bw"
mkdir -p "$SESSION_DIR"

# Hanya proses user yang punya conf ZV-Manager
CONF="/etc/zv-manager/accounts/ssh/${PAM_USER}.conf"
[[ ! -f "$CONF" ]] && exit 0

# Skip jika quota = 0 (unlimited)
quota=$(grep "^BW_QUOTA_BYTES=" "$CONF" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')
[[ "${quota:-0}" == "0" ]] && exit 0

source /etc/zv-manager/core/bandwidth.sh

if [[ "$PAM_TYPE" == "open_session" ]]; then
    CLIENT_IP="$PAM_RHOST"
    [[ -z "$CLIENT_IP" || "$CLIENT_IP" == "unknown" ]] && exit 0

    # Simpan IP ke session file (sort -u supaya tidak duplikat)
    echo "$CLIENT_IP" >> "${SESSION_DIR}/${PAM_USER}.ips"
    sort -u "${SESSION_DIR}/${PAM_USER}.ips" -o "${SESSION_DIR}/${PAM_USER}.ips"

    # Pasang iptables rule OUTPUT → chain user untuk track bytes
    _bw_add_ip_rule "$PAM_USER" "$CLIENT_IP"
    _bw_log "SESSION_OPEN: $PAM_USER from $CLIENT_IP"

elif [[ "$PAM_TYPE" == "close_session" ]]; then
    CLIENT_IP="$PAM_RHOST"
    [[ -z "$CLIENT_IP" ]] && exit 0

    # Akumulasi bytes ke conf sebelum hapus rule
    _bw_accumulate "$PAM_USER"

    # Hapus IP dari session file
    SESSION_FILE="${SESSION_DIR}/${PAM_USER}.ips"
    if [[ -f "$SESSION_FILE" ]]; then
        grep -v "^${CLIENT_IP}$" "$SESSION_FILE" > "${SESSION_FILE}.tmp" 2>/dev/null
        mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
    fi

    # Hapus iptables rule untuk IP ini
    _bw_remove_ip_rule "$PAM_USER" "$CLIENT_IP"
    _bw_log "SESSION_CLOSE: $PAM_USER from $CLIENT_IP"
fi

exit 0
