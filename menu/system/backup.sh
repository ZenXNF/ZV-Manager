#!/bin/bash
# ============================================================
#   ZV-Manager - Menu Backup & Restore
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/helpers.sh
source /etc/zv-manager/core/telegram.sh

BACKUP_DIR="/var/backups/zv-manager"
mkdir -p "$BACKUP_DIR"

backup_menu() {
    while true; do
        clear
        echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
        echo -e " │           ${BWHITE}BACKUP & RESTORE${NC}                  │"
        echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
        echo ""

        # Tampilkan backup terakhir
        local last_backup
        last_backup=$(ls -t "$BACKUP_DIR"/zv-backup-*.tar.gz 2>/dev/null | head -1)
        if [[ -n "$last_backup" ]]; then
            local last_size last_date
            last_size=$(du -sh "$last_backup" | cut -f1)
            last_date=$(basename "$last_backup" | sed 's/zv-backup-//;s/.tar.gz//' | tr '_' ' ')
            echo -e "  ${BWHITE}Backup terakhir :${NC} ${BGREEN}${last_date}${NC} (${last_size})"
        else
            echo -e "  ${BWHITE}Backup terakhir :${NC} ${BYELLOW}Belum ada${NC}"
        fi
        echo ""

        echo -e "  ${BGREEN}[1]${NC} Backup sekarang (kirim ke Telegram)"
        echo -e "  ${BGREEN}[2]${NC} Backup lokal saja (tidak kirim TG)"
        echo -e "  ${BGREEN}[3]${NC} List backup tersimpan"
        echo -e "  ${BGREEN}[4]${NC} Restore dari backup"
        echo -e "  ${BGREEN}[5]${NC} Hapus backup lama (> 7 hari)"
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
                # Backup tanpa kirim TG — set token kosong sementara
                TMP_DIR="/tmp/zv-backup-manual-$$"
                DATE=$(TZ="Asia/Jakarta" date +"%Y-%m-%d_%H-%M")
                FILE="${BACKUP_DIR}/zv-backup-${DATE}.tar.gz"
                mkdir -p "$TMP_DIR"

                [[ -d /etc/zv-manager/accounts ]] && cp -r /etc/zv-manager/accounts "$TMP_DIR/"
                [[ -d /etc/zv-manager/servers  ]] && cp -r /etc/zv-manager/servers  "$TMP_DIR/"
                for f in telegram.conf config.conf license.info; do
                    [[ -f "/etc/zv-manager/${f}" ]] && cp "/etc/zv-manager/${f}" "$TMP_DIR/"
                done

                tar -czf "$FILE" -C "$TMP_DIR" . 2>/dev/null
                rm -rf "$TMP_DIR"
                SIZE=$(du -sh "$FILE" | cut -f1)
                echo -e "  ${BGREEN}✓ Backup disimpan: ${FILE} (${SIZE})${NC}"
                echo ""
                press_any_key
                ;;
            3)
                clear
                echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
                echo -e " │              ${BWHITE}DAFTAR BACKUP${NC}                  │"
                echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
                echo ""
                local found=0
                for f in $(ls -t "$BACKUP_DIR"/zv-backup-*.tar.gz 2>/dev/null); do
                    local sz; sz=$(du -sh "$f" | cut -f1)
                    local nm; nm=$(basename "$f" | sed 's/zv-backup-//;s/.tar.gz//' | tr '_' ' ')
                    echo -e "  ${BGREEN}${nm}${NC} — ${sz}"
                    found=$((found+1))
                done
                [[ $found -eq 0 ]] && echo -e "  ${BYELLOW}Belum ada backup.${NC}"
                echo ""
                press_any_key
                ;;
            4)
                clear
                echo -e "${BCYAN} ┌──────────────────────────────────────────────┐${NC}"
                echo -e " │              ${BWHITE}RESTORE BACKUP${NC}                 │"
                echo -e "${BCYAN} └──────────────────────────────────────────────┘${NC}"
                echo ""
                echo -e "  ${BYELLOW}⚠ Restore akan MENIMPA data yang ada sekarang!${NC}"
                echo ""

                # List file backup
                local files=()
                while IFS= read -r f; do files+=("$f"); done < <(ls -t "$BACKUP_DIR"/zv-backup-*.tar.gz 2>/dev/null)

                if [[ ${#files[@]} -eq 0 ]]; then
                    echo -e "  ${BRED}Tidak ada file backup.${NC}"
                    echo ""
                    press_any_key
                    continue
                fi

                local i=1
                for f in "${files[@]}"; do
                    local nm; nm=$(basename "$f" | sed 's/zv-backup-//;s/.tar.gz//' | tr '_' ' ')
                    local sz; sz=$(du -sh "$f" | cut -f1)
                    echo -e "  ${BGREEN}[${i}]${NC} ${nm} (${sz})"
                    i=$((i+1))
                done
                echo ""
                read -rp "  Pilih nomor backup: " num
                [[ ! "$num" =~ ^[0-9]+$ ]] && continue
                local selected="${files[$((num-1))]}"
                [[ -z "$selected" ]] && continue

                echo ""
                if confirm "Restore dari $(basename $selected)?"; then
                    echo -e "  ${BYELLOW}Merestore...${NC}"
                    # Stop bot dulu
                    systemctl stop zv-telegram &>/dev/null
                    # Restore
                    tar -xzf "$selected" -C /etc/zv-manager/ \
                        --strip-components=0 2>/dev/null
                    # Start bot lagi
                    systemctl start zv-telegram &>/dev/null
                    echo -e "  ${BGREEN}✓ Restore selesai!${NC}"
                fi
                echo ""
                press_any_key
                ;;
            5)
                echo ""
                local deleted=0
                while IFS= read -r f; do
                    rm -f "$f"
                    deleted=$((deleted+1))
                done < <(find "$BACKUP_DIR" -name "zv-backup-*.tar.gz" -mtime +7)
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
