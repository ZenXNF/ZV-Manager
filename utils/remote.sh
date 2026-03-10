#!/bin/bash
# ============================================================
#   ZV-Manager - Remote Execution Helper
#   Source file ini dari script SSH menu
# ============================================================

ZV_TARGET_FILE="/tmp/zv_target_server"
SERVER_DIR="/etc/zv-manager/servers"

# ---------- Getter / Setter target ----------

set_target_server() {
    echo "$1" > "$ZV_TARGET_FILE"
}

get_target_server() {
    local t
    t=$(cat "$ZV_TARGET_FILE" 2>/dev/null)
    echo "${t:-local}"
}

is_local_target() {
    local t
    t=$(get_target_server)
    [[ "$t" == "local" || -z "$t" ]]
}

# Nama + IP untuk tampilan header
target_display() {
    local t
    t=$(get_target_server)
    if [[ "$t" == "local" || -z "$t" ]]; then
        local ip
        ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null)
        echo "Local${ip:+ (${ip})}"
    else
        local conf="${SERVER_DIR}/${t}.conf"
        if [[ -f "$conf" ]]; then
            unset NAME IP
            source "$conf"
            echo "${NAME} (${IP})"
        else
            echo "$t"
        fi
    fi
}

# ---------- SSH execution helpers ----------

_ensure_sshpass() {
    if ! command -v sshpass &>/dev/null; then
        apt-get install -y sshpass &>/dev/null
    fi
}

_ssh_opts="-q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=no -o LogLevel=ERROR"

# Eksekusi perintah arbitrary di server tujuan
# remote_exec <server_name> <command_string>
remote_exec() {
    local name="$1"
    shift
    local cmd="$*"

    if [[ "$name" == "local" || -z "$name" ]]; then
        # Jalankan di subshell terisolasi, bukan eval langsung
        # Mencegah variable injection ke parent shell
        bash -c "$cmd"
        return $?
    fi

    local conf="${SERVER_DIR}/${name}.conf"
    [[ ! -f "$conf" ]] && { echo "REMOTE-ERR|Server '$name' tidak ditemukan"; return 1; }

    unset IP PORT USER PASS
    source "$conf"

    _ensure_sshpass

    sshpass -p "$PASS" ssh $_ssh_opts -p "$PORT" "${USER}@${IP}" "$cmd" 2>&1
    return $?
}

# Eksekusi zv-agent di remote dengan argumen
# remote_agent <server_name> [zv-agent args...]
remote_agent() {
    local name="$1"
    shift
    local agent_args="$*"

    if [[ "$name" == "local" || -z "$name" ]]; then
        # Lokal — jalankan langsung
        bash /etc/zv-manager/zv-agent.sh $agent_args
        return $?
    fi

    local conf="${SERVER_DIR}/${name}.conf"
    [[ ! -f "$conf" ]] && { echo "REMOTE-ERR|Server '$name' tidak ditemukan"; return 1; }

    unset IP PORT USER PASS
    source "$conf"

    _ensure_sshpass

    local result
    result=$(sshpass -p "$PASS" ssh $_ssh_opts -p "$PORT" "${USER}@${IP}" \
        "zv-agent $agent_args" 2>&1)
    local rc=$?

    # Jika command not found, mungkin agent belum diinstall
    if echo "$result" | grep -qi "command not found\|not found\|No such file"; then
        echo "REMOTE-ERR|zv-agent tidak ditemukan di server '${name}'. Deploy dulu via Menu Server → Deploy Agent."
        return 1
    fi

    echo "$result"
    return $rc
}

# Upload dan install zv-agent ke remote server
# deploy_agent <server_name>
deploy_agent() {
    local name="$1"
    local conf="${SERVER_DIR}/${name}.conf"

    [[ ! -f "$conf" ]] && { echo "DEPLOY-ERR|Server '$name' tidak ditemukan"; return 1; }

    local agent_src="/etc/zv-manager/zv-agent.sh"
    [[ ! -f "$agent_src" ]] && { echo "DEPLOY-ERR|File zv-agent.sh tidak ada di server ini"; return 1; }

    unset IP PORT USER PASS NAME
    source "$conf"

    _ensure_sshpass

    # Buat direktori dan upload via cat pipe
    sshpass -p "$PASS" ssh $_ssh_opts -p "$PORT" "${USER}@${IP}" \
        "mkdir -p /etc/zv-manager/accounts/ssh" 2>&1

    sshpass -p "$PASS" ssh $_ssh_opts -p "$PORT" "${USER}@${IP}" \
        "cat > /usr/local/bin/zv-agent && chmod +x /usr/local/bin/zv-agent" \
        < "$agent_src" 2>&1

    local rc=$?
    [[ $rc -ne 0 ]] && { echo "DEPLOY-ERR|Gagal upload file"; return 1; }

    # Test
    local test_result
    test_result=$(sshpass -p "$PASS" ssh $_ssh_opts -p "$PORT" "${USER}@${IP}" \
        "zv-agent ping" 2>&1)

    if [[ "$test_result" == "ZV-AGENT-OK" ]]; then
        echo "DEPLOY-OK"
    else
        echo "DEPLOY-ERR|Upload berhasil tapi ping gagal: ${test_result}"
        return 1
    fi
}

# ---------- Interactive server picker ----------

# Tampilkan picker server, set target ke file temp
# Return 0 jika pilih berhasil, 1 jika dibatalkan
pick_target_server() {
    local local_ip
    local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null)

    clear
    echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
    echo -e " │           ${BWHITE}PILIH TARGET SERVER${NC}               │"
    echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BGREEN}[1]${NC} ${BWHITE}Local${NC} — VPS ini sendiri${local_ip:+ (${local_ip})}"

    local count=1
    local _picker_keys=("" "local")

    for conf in "${SERVER_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue
        [[ "$conf" == *.tg.conf ]] && continue
        unset NAME IP PORT USER
        source "$conf"
        # Skip jika IP sama dengan lokal
        [[ "$IP" == "$local_ip" ]] && continue
        count=$((count + 1))
        _picker_keys+=("$NAME")
        echo -e "  ${BGREEN}[${count}]${NC} ${BWHITE}${NAME}${NC} — ${USER}@${IP}:${PORT}"
    done

    echo ""
    echo -e "  ${BRED}[0]${NC} Batal"
    echo ""
    read -rp "  Pilih target server: " choice

    [[ "$choice" == "0" ]] && return 1

    local chosen="${_picker_keys[$choice]}"
    if [[ -z "$chosen" ]]; then
        echo -e "  ${BRED}Pilihan tidak valid!${NC}"
        sleep 1
        return 1
    fi

    set_target_server "$chosen"
    return 0
}

# Eksekusi zv-vmess-agent di remote/lokal dengan argumen
# remote_vmess_agent <server_name> [zv-vmess-agent args...]
remote_vmess_agent() {
    local name="$1"
    shift
    local agent_args="$*"
    if [[ "$name" == "local" || -z "$name" ]]; then
        bash /etc/zv-manager/zv-vmess-agent.sh $agent_args
        return $?
    fi
    local conf="${SERVER_DIR}/${name}.conf"
    [[ ! -f "$conf" ]] && { echo "REMOTE-ERR|Server '$name' tidak ditemukan"; return 1; }
    unset IP PORT USER PASS
    source "$conf"
    _ensure_sshpass
    local result
    result=$(sshpass -p "$PASS" ssh $_ssh_opts -p "$PORT" "${USER}@${IP}" \
        "zv-vmess-agent $agent_args" 2>&1)
    local rc=$?
    if echo "$result" | grep -qi "command not found\|not found\|No such file"; then
        echo "REMOTE-ERR|zv-vmess-agent tidak ditemukan di '${name}'. Deploy dulu via Menu Server → Deploy Agent."
        return 1
    fi
    echo "$result"
    return $rc
}

# Upload dan install zv-vmess-agent ke remote server
deploy_vmess_agent() {
    local name="$1"
    local conf="${SERVER_DIR}/${name}.conf"
    [[ ! -f "$conf" ]] && { echo "DEPLOY-ERR|Server '$name' tidak ditemukan"; return 1; }
    local agent_src="/etc/zv-manager/zv-vmess-agent.sh"
    [[ ! -f "$agent_src" ]] && { echo "DEPLOY-ERR|File zv-vmess-agent.sh tidak ada"; return 1; }
    unset IP PORT USER PASS NAME
    source "$conf"
    _ensure_sshpass
    sshpass -p "$PASS" ssh $_ssh_opts -p "$PORT" "${USER}@${IP}" \
        "mkdir -p /etc/zv-manager/accounts/vmess" 2>&1
    sshpass -p "$PASS" ssh $_ssh_opts -p "$PORT" "${USER}@${IP}" \
        "cat > /usr/local/bin/zv-vmess-agent && chmod +x /usr/local/bin/zv-vmess-agent" \
        < "$agent_src" 2>&1
    [[ $? -ne 0 ]] && { echo "DEPLOY-ERR|Gagal upload file"; return 1; }
    local test_result
    test_result=$(sshpass -p "$PASS" ssh $_ssh_opts -p "$PORT" "${USER}@${IP}" \
        "zv-vmess-agent ping" 2>&1)
    if [[ "$test_result" == "ZV-VMESS-AGENT-OK" ]]; then
        echo "DEPLOY-OK"
    else
        echo "DEPLOY-ERR|Upload berhasil tapi ping gagal: ${test_result}"
        return 1
    fi
}
