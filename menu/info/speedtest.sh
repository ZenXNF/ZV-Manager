#!/bin/bash
# ============================================================
#   ZV-Manager - Speedtest
#   Pakai librespeed-cli (lebih akurat, open source)
# ============================================================

source /etc/zv-manager/utils/colors.sh
source /etc/zv-manager/utils/helpers.sh

LIBRESPEED_BIN="/usr/local/bin/librespeed-cli"

_install_librespeed() {
    echo ""
    echo -e "  $(cyn '>>') librespeed-cli belum terinstall, menginstall..."
    echo ""
    local tmp; tmp=$(mktemp -d)
    # Ambil versi terbaru dari GitHub API
    local ver
    ver=$(curl -sf --max-time 10 "https://api.github.com/repos/librespeed/speedtest-cli/releases/latest" \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'].lstrip('v'))" 2>/dev/null)
    [[ -z "$ver" ]] && ver="1.0.12"  # fallback ke versi stabil terakhir

    local url="https://github.com/librespeed/speedtest-cli/releases/download/v${ver}/librespeed-cli_${ver}_linux_amd64.tar.gz"

    if curl -sL --max-time 30 "$url" -o "$tmp/librespeed.tar.gz" 2>/dev/null; then
        tar -xzf "$tmp/librespeed.tar.gz" -C "$tmp" 2>/dev/null
        local bin; bin=$(find "$tmp" -name "librespeed-cli" -type f 2>/dev/null | head -1)
        if [[ -n "$bin" ]]; then
            cp "$bin" "$LIBRESPEED_BIN"
            chmod +x "$LIBRESPEED_BIN"
            rm -rf "$tmp"
            echo -e "  ${BGREEN}✔${NC} librespeed-cli v${ver} berhasil diinstall"
            return 0
        fi
    fi
    rm -rf "$tmp"
    echo -e "  ${BRED}✘${NC} Gagal install librespeed-cli"
    return 1
}

run_speedtest() {
    clear
    _sep
    _grad " SPEEDTEST VPS" 255 0 127 0 210 255
    _sep
    echo ""
    echo -e "  $(dim 'IP VPS  :') $(bold "$(cat /etc/zv-manager/accounts/ipvps 2>/dev/null || echo '?')")"
    echo -e "  $(dim 'Waktu   :') $(bold "$(TZ='Asia/Jakarta' date '+%d %b %Y %H:%M WIB')")"
    echo ""
    _sep
    echo ""

    # Install kalau belum ada
    if [[ ! -x "$LIBRESPEED_BIN" ]]; then
        _install_librespeed || { press_any_key; return; }
        echo ""
    fi

    echo -e "  $(yel '>>') Menjalankan speedtest, mohon tunggu..."
    echo ""

    # Jalankan speedtest
    local result
    result=$("$LIBRESPEED_BIN" --json 2>/dev/null)

    if [[ -z "$result" ]]; then
        echo -e "  ${BRED}✘${NC} Speedtest gagal dijalankan"
        press_any_key
        return
    fi

    # Parse hasil JSON
    local ping dl ul server
    ping=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"{d.get('Ping',0):.1f}\")" 2>/dev/null || echo "?")
    dl=$(echo "$result"   | python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"{d.get('Download',0):.2f}\")" 2>/dev/null || echo "?")
    ul=$(echo "$result"   | python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"{d.get('Upload',0):.2f}\")" 2>/dev/null || echo "?")
    server=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('Server',{}).get('Name','?'))" 2>/dev/null || echo "?")

    _sep
    echo -e "  $(dim '≥') $(bold 'Server  :') $(cyn "$server")"
    echo -e "  $(dim '≥') $(bold 'Ping    :') $(yel "${ping} ms")"
    echo -e "  $(dim '≥') $(bold 'Download:') $(grn "${dl} Mbps")"
    echo -e "  $(dim '≥') $(bold 'Upload  :') $(_grad "${ul} Mbps" 0 210 255 160 80 255)"
    _sep
    echo ""

    press_any_key
}

# Definisi warna inline kalau tidak ada dari colors.sh
cyn()  { echo -e "\e[1;36m$1\e[0m"; }
grn()  { echo -e "\e[1;32m$1\e[0m"; }
yel()  { echo -e "\e[1;33m$1\e[0m"; }
bold() { echo -e "\e[1;97m$1\e[0m"; }
dim()  { echo -e "\e[0;37m$1\e[0m"; }

run_speedtest
