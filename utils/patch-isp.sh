#!/bin/bash
# ============================================================
#   ZV-Manager - Patch ISP ke server conf yang belum punya
#   Jalankan sekali saja untuk server lama
# ============================================================

source /etc/zv-manager/utils/colors.sh 2>/dev/null || true
SERVER_DIR="/etc/zv-manager/servers"
LOCAL_IP=$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null || curl -s --max-time 5 ipinfo.io/ip)

echo ""
echo -e "${BCYAN}  Patch ISP ke server conf...${NC}"
echo ""

for conf in "${SERVER_DIR}"/*.conf; do
    [[ "$conf" == *.tg.conf ]] && continue
    [[ ! -f "$conf" ]] && continue

    # Baca info server
    unset NAME IP PORT USER PASS ISP SERVER_TYPE
    source "$conf" 2>/dev/null

    # Cek apakah sudah ada ISP dan bukan placeholder
    if grep -q "^ISP=" "$conf"; then
        cur_isp=$(grep "^ISP=" "$conf" | cut -d'"' -f2)
        if [[ -n "$cur_isp" && "$cur_isp" != "Nama ISP VPS" && "$cur_isp" != "Unknown" ]]; then
            echo -e "  ${BYELLOW}Skip${NC} ${NAME} — ISP sudah ada: ${cur_isp}"
            continue
        fi
        # Hapus ISP lama yang placeholder
        sed -i '/^ISP=/d' "$conf"
        echo -e "  ${BYELLOW}Reset${NC} ${NAME} — ISP placeholder dihapus, fetch ulang..."
    fi

    echo -ne "  Fetching ISP untuk ${NAME} (${IP})... "

    # Server lokal — curl langsung
    if [[ "$IP" == "$LOCAL_IP" ]]; then
        isp=$(curl -s --max-time 5 ipinfo.io/org 2>/dev/null | sed 's/^AS[0-9]* //')
    else
        isp=$(sshpass -p "$PASS" ssh \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=10 \
            -o BatchMode=no \
            -p "${PORT:-22}" \
            "${USER:-root}@${IP}" \
            "curl -s --max-time 5 ipinfo.io/org 2>/dev/null | sed 's/^AS[0-9]* //'" 2>/dev/null)
    fi

    if [[ -z "$isp" ]]; then
        echo -e "${BRED}Gagal${NC}"
        echo -e "  ${BYELLOW}Tambah manual: echo 'ISP=\"Nama ISP\"' >> ${conf}${NC}"
        continue
    fi

    # Tambah ISP ke conf setelah baris SERVER_TYPE
    sed -i "/^SERVER_TYPE=/a ISP=\"${isp}\"" "$conf"
    echo -e "${BGREEN}${isp}${NC}"
done

echo ""
echo -e "${BGREEN}  Selesai!${NC} Restart bot: systemctl restart zv-telegram"
echo ""
