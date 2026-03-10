#!/bin/bash
# ============================================================
#   ZV-Manager - Menu Backup & Restore
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/utils/remote.sh 2>/dev/null
source /etc/zv-manager/core/telegram.sh

BACKUP_DIR="/var/backups/zv-manager"
BASE_DIR="/etc/zv-manager"
mkdir -p "$BACKUP_DIR"

# Format ukuran file
_fmt_size() {
    local bytes
    bytes=$(stat -c%s "$1" 2>/dev/null || echo 0)
    if   [[ $bytes -ge 1048576 ]]; then printf "%.1f MB" "$(echo "scale=1; $bytes/1048576" | bc)"
    elif [[ $bytes -ge 1024    ]]; then printf "%.1f KB" "$(echo "scale=1; $bytes/1024" | bc)"
    else printf "%d B" "$bytes"
    fi
}

backup_menu() {
    while true; do
        clear
        echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
        echo -e " │           ${BWHITE}BACKUP & RESTORE${NC}                  │"
        echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
        echo ""

        # Tampilkan backup otak terakhir
        local last_otak
        last_otak=$(ls -t "$BACKUP_DIR"/zv-backup-otak-*.tar.gz 2>/dev/null | head -1)
        if [[ -n "$last_otak" ]]; then
            local last_size last_date
            last_size=$(_fmt_size "$last_otak")
            last_date=$(basename "$last_otak" | sed 's/zv-backup-otak-//;s/.tar.gz//' | tr '_' ' ')
            echo -e "  ${BWHITE}Backup otak terakhir :${NC} ${BGREEN}${last_date}${NC} (${last_size})"
        else
            echo -e "  ${BWHITE}Backup otak terakhir :${NC} ${BYELLOW}Belum ada${NC}"
        fi

        # Tampilkan backup server terakhir
        local last_srv
        last_srv=$(ls -t "$BACKUP_DIR"/zv-ssh-*.tar.gz 2>/dev/null | head -1)
        if [[ -n "$last_srv" ]]; then
            local srv_size srv_date
            srv_size=$(_fmt_size "$last_srv")
            srv_date=$(basename "$last_srv" | sed 's/zv-ssh-//;s/.tar.gz//' | tr '_' ' ')
            echo -e "  ${BWHITE}Backup server terakhir:${NC} ${BGREEN}${srv_date}${NC} (${srv_size})"
        fi
        echo ""

        echo -e "  ${BGREEN}[1]${NC} Backup sekarang (kirim ke Telegram)"
        echo -e "  ${BGREEN}[2]${NC} Backup lokal saja (tidak kirim TG)"
        echo -e "  ${BGREEN}[3]${NC} List semua backup tersimpan"
        echo -e "  ${BGREEN}[4]${NC} Restore Otak (conf akun, config, SSL)"
        echo -e "  ${BGREEN}[5]${NC} Restore Server Tunneling (push akun ke server)"
        echo -e "  ${BGREEN}[6]${NC} Hapus backup lama (> 7 hari)"
        echo ""
        echo -e "  ${BRED}[0]${NC} Kembali"
        echo ""
        read -rp "  Pilihan: " ch

        case "$ch" in
            1)
                echo ""
                echo -e "  ${BYELLOW}Memulai backup...${NC}"
                bash /etc/zv-manager/cron/backup.sh
                echo -e "  ${BGREEN}✓ Backup selesai! File dikirim ke Telegram admin.${NC}"
                echo ""
                press_any_key
                ;;
            2)
                echo ""
                echo -e "  ${BYELLOW}Memulai backup lokal...${NC}"
                local TMP_DIR DATE FILE
                TMP_DIR="/tmp/zv-backup-manual-$$"
                DATE=$(TZ="Asia/Jakarta" date +"%Y-%m-%d_%H-%M")
                FILE="${BACKUP_DIR}/zv-backup-otak-${DATE}.tar.gz"
                mkdir -p "$TMP_DIR"
                [[ -d "${BASE_DIR}/accounts" ]] && cp -r "${BASE_DIR}/accounts" "$TMP_DIR/"
                [[ -d "${BASE_DIR}/servers"  ]] && cp -r "${BASE_DIR}/servers"  "$TMP_DIR/"
                for f in telegram.conf config.conf license.info; do
                    [[ -f "${BASE_DIR}/${f}" ]] && cp "${BASE_DIR}/${f}" "$TMP_DIR/"
                done
                mkdir -p "${TMP_DIR}/ssl"
                [[ -f "${BASE_DIR}/ssl/cert.pem" ]] && cp "${BASE_DIR}/ssl/cert.pem" "${TMP_DIR}/ssl/"
                [[ -f "${BASE_DIR}/ssl/key.pem"  ]] && cp "${BASE_DIR}/ssl/key.pem"  "${TMP_DIR}/ssl/"
                tar -czf "$FILE" -C "$TMP_DIR" . 2>/dev/null
                rm -rf "$TMP_DIR"
                echo -e "  ${BGREEN}✓ Backup disimpan: ${FILE} ($(_fmt_size "$FILE"))${NC}"
                echo ""
                press_any_key
                ;;
            3)
                clear
                echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
                echo -e " │              ${BWHITE}DAFTAR BACKUP${NC}                  │"
                echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
                echo ""
                echo -e "  ${BWHITE}── Backup Otak ──${NC}"
                local found=0
                for f in $(ls -t "$BACKUP_DIR"/zv-backup-otak-*.tar.gz 2>/dev/null); do
                    local sz nm
                    sz=$(_fmt_size "$f")
                    nm=$(basename "$f" | sed 's/zv-backup-otak-//;s/.tar.gz//' | tr '_' ' ')
                    echo -e "  ${BGREEN}${nm}${NC} — ${sz}"
                    found=$((found+1))
                done
                [[ $found -eq 0 ]] && echo -e "  ${BYELLOW}Belum ada.${NC}"
                echo ""
                echo -e "  ${BWHITE}── Backup Server Tunneling ──${NC}"
                found=0
                for f in $(ls -t "$BACKUP_DIR"/zv-ssh-*.tar.gz 2>/dev/null); do
                    local sz nm
                    sz=$(_fmt_size "$f")
                    nm=$(basename "$f" | sed 's/zv-ssh-//;s/.tar.gz//' | tr '_' ' ')
                    echo -e "  ${BGREEN}${nm}${NC} — ${sz}"
                    found=$((found+1))
                done
                [[ $found -eq 0 ]] && echo -e "  ${BYELLOW}Belum ada.${NC}"
                echo ""
                press_any_key
                ;;
            4)
                # ── Restore Otak ──────────────────────────────
                clear
                echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
                echo -e " │            ${BWHITE}RESTORE OTAK${NC}                     │"
                echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
                echo ""
                echo -e "  ${BYELLOW}⚠ Restore akan MENIMPA conf akun yang ada sekarang!${NC}"
                echo ""

                local files=()
                while IFS= read -r f; do files+=("$f"); done < <(ls -t "$BACKUP_DIR"/zv-backup-otak-*.tar.gz 2>/dev/null)

                if [[ ${#files[@]} -eq 0 ]]; then
                    echo -e "  ${BRED}Tidak ada file backup otak.${NC}"
                    echo ""
                    press_any_key
                    continue
                fi

                local i=1
                for f in "${files[@]}"; do
                    local nm sz
                    nm=$(basename "$f" | sed 's/zv-backup-otak-//;s/.tar.gz//' | tr '_' ' ')
                    sz=$(_fmt_size "$f")
                    echo -e "  ${BGREEN}[${i}]${NC} otak-${nm} (${sz})"
                    i=$((i+1))
                done
                echo ""
                read -rp "  Pilih nomor backup: " num
                [[ ! "$num" =~ ^[0-9]+$ ]] && continue
                local selected="${files[$((num-1))]}"
                [[ -z "$selected" ]] && continue

                echo ""
                if confirm "Restore otak dari $(basename $selected)?"; then
                    echo -e "  ${BYELLOW}Merestore...${NC}"
                    systemctl stop zv-telegram &>/dev/null
                    tar -xzf "$selected" -C "${BASE_DIR}/" 2>/dev/null
                    systemctl start zv-telegram &>/dev/null
                    echo -e "  ${BGREEN}✓ Restore otak selesai! Bot direstart.${NC}"
                fi
                echo ""
                press_any_key
                ;;
            5)
                # ── Restore Server Tunneling ──────────────────
                clear
                echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
                echo -e " │        ${BWHITE}RESTORE SERVER TUNNELING${NC}              │"
                echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
                echo ""
                echo -e "  ${BYELLOW}Fungsi: Push akun SSH+VMess ke server baru${NC}"
                echo -e "  ${BYELLOW}(Gunakan setelah tambah server pengganti)${NC}"
                echo ""

                # Pilih backup server
                local srv_files=()
                while IFS= read -r f; do srv_files+=("$f"); done < <(ls -t "$BACKUP_DIR"/zv-ssh-*.tar.gz 2>/dev/null)

                if [[ ${#srv_files[@]} -eq 0 ]]; then
                    echo -e "  ${BRED}Tidak ada backup server tunneling.${NC}"
                    echo ""
                    press_any_key
                    continue
                fi

                echo -e "  ${BWHITE}Pilih backup server:${NC}"
                echo ""
                local i=1
                for f in "${srv_files[@]}"; do
                    local nm sz
                    nm=$(basename "$f" | sed 's/zv-ssh-//;s/.tar.gz//' | tr '_' ' ')
                    sz=$(_fmt_size "$f")
                    echo -e "  ${BGREEN}[${i}]${NC} ${nm} (${sz})"
                    i=$((i+1))
                done
                echo ""
                read -rp "  Pilih nomor backup: " num
                [[ ! "$num" =~ ^[0-9]+$ ]] && continue
                local sel_backup="${srv_files[$((num-1))]}"
                [[ -z "$sel_backup" ]] && continue

                # Pilih server tujuan (yang sudah ditambah)
                echo ""
                echo -e "  ${BWHITE}Pilih server tujuan (server baru):${NC}"
                echo ""
                local srv_list=()
                local j=1
                for sc in "${BASE_DIR}/servers"/*.conf; do
                    [[ -f "$sc" ]] || continue
                    [[ "$sc" == *.tg.conf ]] && continue
                    local sname; sname=$(basename "$sc" .conf)
                    srv_list+=("$sname")
                    echo -e "  ${BGREEN}[${j}]${NC} ${sname}"
                    j=$((j+1))
                done

                if [[ ${#srv_list[@]} -eq 0 ]]; then
                    echo -e "  ${BRED}Belum ada server terdaftar. Tambah server dulu.${NC}"
                    echo ""
                    press_any_key
                    continue
                fi

                echo ""
                read -rp "  Pilih nomor server tujuan: " snum
                [[ ! "$snum" =~ ^[0-9]+$ ]] && continue
                local target_srv="${srv_list[$((snum-1))]}"
                [[ -z "$target_srv" ]] && continue

                echo ""
                if confirm "Push akun dari $(basename $sel_backup) ke server '$target_srv'?"; then
                    local XTMP="/tmp/zv-restore-srv-$$"
                    mkdir -p "$XTMP"
                    tar -xzf "$sel_backup" -C "$XTMP" 2>/dev/null

                    # Deteksi lokal vs remote
                    local is_local=false
                    local srv_conf="${BASE_DIR}/servers/${target_srv}.conf"
                    local _local_ip; _local_ip=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null | tr -d '[:space:]')
                    if [[ ! -f "$srv_conf" ]]; then
                        is_local=true
                    else
                        local _ip
                        _ip=$(grep "^IP=" "$srv_conf" | cut -d= -f2 | tr -d '"')
                        [[ -z "$_ip" || "$_ip" == "$_local_ip" ]] && is_local=true
                    fi

                    # Ambil domain terbaru dari server conf aktif
                    # atau fallback ke server-info.txt di backup
                    local new_domain=""
                    if [[ -f "$srv_conf" ]]; then
                        new_domain=$(grep "^DOMAIN=" "$srv_conf" | cut -d= -f2 | tr -d '"')
                    fi
                    if [[ -z "$new_domain" && -f "${XTMP}/server-info.txt" ]]; then
                        new_domain=$(grep "^DOMAIN:" "${XTMP}/server-info.txt" | awk '{print $2}')
                    fi

                    echo ""
                    echo -e "  ${BYELLOW}Memproses akun SSH...${NC}"
                    local ssh_ok=0
                    for ac in "${XTMP}/ssh-accounts"/*.conf; do
                        [[ -f "$ac" ]] || continue
                        USERNAME=$(grep "^USERNAME=" "$ac" | cut -d= -f2- | tr -d '"\n')
                        PASSWORD=$(grep "^PASSWORD=" "$ac" | cut -d= -f2- | tr -d '"\n')
                        EXPIRED_TS=$(grep "^EXPIRED_TS=" "$ac" | cut -d= -f2- | tr -d '"\n')
                        [[ -z "$USERNAME" || -z "$PASSWORD" ]] && continue

                        local now_ts days_left new_exp_ts new_exp_date
                        now_ts=$(date +%s)
                        days_left=$(( (EXPIRED_TS - now_ts) / 86400 ))
                        [[ $days_left -lt 1 ]] && days_left=1

                        # Jika sudah expired, extend dari sekarang
                        if [[ "$EXPIRED_TS" -lt "$now_ts" ]]; then
                            new_exp_ts=$(( now_ts + days_left * 86400 ))
                            new_exp_date=$(date -d "@${new_exp_ts}" +"%Y-%m-%d" 2>/dev/null || \
                                          date -r "${new_exp_ts}" +"%Y-%m-%d" 2>/dev/null)
                            sed -i "s/^EXPIRED_TS=.*/EXPIRED_TS=${new_exp_ts}/" "$ac"
                            sed -i "s/^EXPIRED=.*/EXPIRED=${new_exp_date}/" "$ac"
                        fi

                        # Update SERVER dan DOMAIN di conf dulu
                        sed -i "s/^SERVER=.*/SERVER=\"${target_srv}\"/" "$ac"
                        [[ -n "$new_domain" ]] && \
                            sed -i "s/^DOMAIN=.*/DOMAIN=\"${new_domain}\"/" "$ac"

                        # Copy conf dulu ke accounts/ sebelum agent dipanggil
                        cp "$ac" "${BASE_DIR}/accounts/ssh/${USERNAME}.conf"

                        if [[ "$is_local" == true ]]; then
                            if ! id "$USERNAME" &>/dev/null; then
                                useradd -M -s /bin/false "$USERNAME" 2>/dev/null
                                echo "$USERNAME:$PASSWORD" | chpasswd 2>/dev/null
                            fi
                        else
                            remote_agent "$target_srv" add "$USERNAME" "$PASSWORD" "$days_left" 2>/dev/null
                        fi

                        echo -e "    ${BGREEN}✓${NC} SSH: ${USERNAME}"
                        ssh_ok=$((ssh_ok+1))
                    done

                    echo ""
                    echo -e "  ${BYELLOW}Memproses akun VMess...${NC}"
                    local vmess_ok=0
                    # Hapus placeholder Xray sebelum restore VMess
                    if [[ "$is_local" == true ]]; then
                        /usr/local/bin/xray api rmu -s "127.0.0.1:10085" -inbound "vmess-ws"   -email "placeholder@vmess" &>/dev/null || true
                        /usr/local/bin/xray api rmu -s "127.0.0.1:10085" -inbound "vmess-grpc" -email "placeholder@vmess" &>/dev/null || true
                    fi

                    for vc in "${XTMP}/vmess-accounts"/*.conf; do
                        [[ -f "$vc" ]] || continue
                        USERNAME=$(grep "^USERNAME=" "$vc" | cut -d= -f2- | tr -d '"\n')
                        UUID=$(grep "^UUID=" "$vc" | cut -d= -f2- | tr -d '"\n')
                        EXPIRED_TS=$(grep "^EXPIRED_TS=" "$vc" | cut -d= -f2- | tr -d '"\n')
                        BW_LIMIT_GB=$(grep "^BW_LIMIT_GB=" "$vc" | cut -d= -f2- | tr -d '"\n')
                        [[ -z "$USERNAME" || -z "$UUID" ]] && continue

                        local now_ts days_left new_exp_ts new_exp_date
                        now_ts=$(date +%s)
                        days_left=$(( (EXPIRED_TS - now_ts) / 86400 ))
                        [[ $days_left -lt 1 ]] && days_left=1

                        # Jika sudah expired, extend dari sekarang
                        if [[ "$EXPIRED_TS" -lt "$now_ts" ]]; then
                            new_exp_ts=$(( now_ts + days_left * 86400 ))
                            new_exp_date=$(date -d "@${new_exp_ts}" +"%Y-%m-%d" 2>/dev/null || \
                                          date -r "${new_exp_ts}" +"%Y-%m-%d" 2>/dev/null)
                            sed -i "s/^EXPIRED_TS=.*/EXPIRED_TS=\"${new_exp_ts}\"/" "$vc"
                            sed -i "s/^EXPIRED_DATE=.*/EXPIRED_DATE=\"${new_exp_date}\"/" "$vc"
                        fi

                        # Update SERVER dan DOMAIN di conf dulu
                        sed -i "s/^SERVER=.*/SERVER=\"${target_srv}\"/" "$vc"
                        [[ -n "$new_domain" ]] && \
                            sed -i "s/^DOMAIN=.*/DOMAIN=\"${new_domain}\"/" "$vc"

                        if [[ "$is_local" == true ]]; then
                            cp "$vc" "${BASE_DIR}/accounts/vmess/${USERNAME}.conf"
                            /usr/local/bin/xray api adu -s "127.0.0.1:10085" -inbound "vmess-ws" \
                                -user "{\"vmess\":{\"id\":\"${UUID}\",\"email\":\"${USERNAME}@vmess\",\"alterId\":0}}" &>/dev/null || true
                            /usr/local/bin/xray api adu -s "127.0.0.1:10085" -inbound "vmess-grpc" \
                                -user "{\"vmess\":{\"id\":\"${UUID}\",\"email\":\"${USERNAME}@vmess\",\"alterId\":0}}" &>/dev/null || true
                        else
                            remote_vmess_agent "$target_srv" add \
                                "$USERNAME" "$UUID" "$days_left" "${BW_LIMIT_GB:-0}" 2>/dev/null
                            cp "$vc" "${BASE_DIR}/accounts/vmess/${USERNAME}.conf"
                        fi

                        echo -e "    ${BGREEN}✓${NC} VMess: ${USERNAME}"
                        vmess_ok=$((vmess_ok+1))
                    done

                    # Restart xray lokal supaya load config.json hasil rebuild dengan bersih
                    if [[ "$is_local" == true && $vmess_ok -gt 0 ]]; then
                        echo -e "  ${BYELLOW}Merestart Xray...${NC}"
                        bash /usr/local/bin/zv-vmess-agent rebuild-config 2>/dev/null || \
                            bash /etc/zv-manager/zv-vmess-agent.sh rebuild-config 2>/dev/null || true
                        systemctl restart zv-xray 2>/dev/null
                    fi

                    # Restart bot supaya cache counter akun (ssh/vmess) langsung fresh
                    echo -e "  ${BYELLOW}Merestart bot...${NC}"
                    systemctl restart zv-telegram 2>/dev/null
                    sleep 2

                    rm -rf "$XTMP"
                    echo ""
                    echo -e "  ${BGREEN}✓ Restore server selesai!${NC}"
                    echo -e "  ${BWHITE}SSH   : ${ssh_ok} akun dipush${NC}"
                    echo -e "  ${BWHITE}VMess : ${vmess_ok} akun dipush${NC}"
                    [[ -n "$new_domain" ]] && \
                        echo -e "  ${BWHITE}Domain akun diupdate ke: ${BGREEN}${new_domain}${NC}" || \
                        echo -e "  ${BYELLOW}⚠ Domain tidak ditemukan di server conf — periksa manual.${NC}"
                fi
                echo ""
                press_any_key
                ;;
            6)
                echo ""
                local deleted=0
                while IFS= read -r f; do
                    rm -f "$f"
                    deleted=$((deleted+1))
                done < <(find "$BACKUP_DIR" \( -name "zv-backup-*.tar.gz" -o -name "zv-ssh-*.tar.gz" \) -mtime +7)
                echo -e "  ${BGREEN}✓ ${deleted} file backup lama dihapus.${NC}"
                echo ""
                press_any_key
                ;;
            0) break ;;
            *) echo -e "  ${BRED}Tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}

backup_menu
