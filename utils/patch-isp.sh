#!/bin/bash
# ============================================================
#   ZV-Manager - Patch ISP ke server conf yang belum punya
#   Jalankan sekali saja untuk server lama
# ============================================================

source /etc/zv-manager/utils/colors.sh 2>/dev/null || true
SERVER_DIR="/etc/zv-manager/servers"

echo ""
echo -e "${BCYAN}  Patch ISP ke server conf...${NC}"
echo ""

for conf in "${SERVER_DIR}"/*.conf; do
    [[ "$conf" == *.tg.conf ]] && continue
    [[ ! -f "$conf" ]] && continue

    # Cek apakah sudah ada ISP
    if grep -q "^ISP=" "$conf"; then
        name=$(grep "^NAME=" "$conf" | cut -d'"' -f2)
        isp=$(grep "^ISP=" "$conf" | cut -d'"' -f2)
        echo -e "  ${BYELLOW}Skip${NC} ${name} — ISP sudah ada: ${isp}"
        continue
    fi

    # Baca info server
    unset NAME IP PORT USER PASS
    source "$conf" 2>/dev/null

    echo -ne "  Fetching ISP untuk ${NAME} (${IP})... "

    isp=$(sshpass -p "$PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 \
        -o BatchMode=no \
        -p "${PORT:-22}" \
        "${USER:-root}@${IP}" \
        "curl -s --max-time 5 ipinfo.io/org 2>/dev/null | sed 's/^AS[0-9]* //'" 2>/dev/null)

    if [[ -z "$isp" ]]; then
        echo -e "${BRED}Gagal (SSH timeout/error)${NC}"
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
