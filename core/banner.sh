#!/bin/bash
# ============================================================
#   ZV-Manager - Banner Generator
#   Generate /etc/issue.net dari banner.conf
# ============================================================

BANNER_CONF="/etc/zv-manager/banner.conf"

_init_banner_conf() {
    [[ -f "$BANNER_CONF" ]] && return
    cat > "$BANNER_CONF" <<'CONFEOF'
BANNER_WELCOME="Selamat Datang!"
BANNER_SUBTITLE="! TERMS AND CONDITIONS !"
BANNER_RULE_1="NO SPAM"
BANNER_RULE_2="NO DDOS / SERANGAN"
BANNER_RULE_3="NO HACKING / CARDING"
BANNER_RULE_4="NO TORRENT"
BANNER_RULE_5="NO MULTI LOGIN"
BANNER_WARN="VIOLATION = PERMANENT BAN"
BANNER_WA=""
BANNER_TG=""
BANNER_THEME="magenta"
CONFEOF
}

_get_theme_colors() {
    local theme="$1"
    case "$theme" in
        magenta) CLR_GARIS="#ff4081"; CLR_WELCOME="#ffd600"; CLR_SUBTITLE="#ffffff"; CLR_RULES="#00e5ff"; CLR_WARN="#ff1744"; CLR_PROMO="#69ff47" ;;
        cyan)    CLR_GARIS="#00e5ff"; CLR_WELCOME="#ffd600"; CLR_SUBTITLE="#ffffff"; CLR_RULES="#69ff47"; CLR_WARN="#ff1744"; CLR_PROMO="#ffd600" ;;
        orange)  CLR_GARIS="#ff6d00"; CLR_WELCOME="#ffffff"; CLR_SUBTITLE="#ffd600"; CLR_RULES="#00e5ff"; CLR_WARN="#ff4081"; CLR_PROMO="#69ff47" ;;
        green)   CLR_GARIS="#69ff47"; CLR_WELCOME="#ffd600"; CLR_SUBTITLE="#ffffff"; CLR_RULES="#00e5ff"; CLR_WARN="#ff1744"; CLR_PROMO="#ffd600" ;;
        *)       CLR_GARIS="#ff4081"; CLR_WELCOME="#ffd600"; CLR_SUBTITLE="#ffffff"; CLR_RULES="#00e5ff"; CLR_WARN="#ff1744"; CLR_PROMO="#69ff47" ;;
    esac
}

# ── Center teks pakai &#160; (non-breaking space HTML) ────────
# Http.fromHtml() Android tidak collapse &#160; seperti spasi biasa
# sehingga padding kiri tetap terjaga → efek center
_center() {
    local text="$1"
    local width="${BANNER_WIDTH:-28}"
    local len=${#text}
    local pad=$(( (width - len) / 2 ))
    [[ $pad -lt 0 ]] && pad=0
    local spaces=""
    for (( i=0; i<pad; i++ )); do spaces+="&#160;"; done
    echo "${spaces}${text}"
}

# ── Baris garis: panjang = BANNER_WIDTH karakter ──────────────
_garis() {
    local w="${BANNER_WIDTH:-28}"
    local g=""
    for (( i=0; i<w; i++ )); do g+="═"; done
    echo "$g"
}

generate_banner() {
    _init_banner_conf

    unset BANNER_WELCOME BANNER_SUBTITLE BANNER_WARN BANNER_THEME BANNER_WA BANNER_TG
    unset BANNER_RULE_1 BANNER_RULE_2 BANNER_RULE_3 BANNER_RULE_4 BANNER_RULE_5
    source "$BANNER_CONF"

    _get_theme_colors "${BANNER_THEME:-magenta}"

    # Lebar banner — 28 cocok untuk layar HP rata-rata
    BANNER_WIDTH=28

    local rules=()
    for r in "$BANNER_RULE_1" "$BANNER_RULE_2" "$BANNER_RULE_3" "$BANNER_RULE_4" "$BANNER_RULE_5"; do
        [[ -n "$r" ]] && rules+=("$r")
    done

    local garis; garis=$(_garis)

    {
        echo "<font color=\"${CLR_GARIS}\">$(_center "$garis")</font><br>"
        echo "<font color=\"${CLR_WELCOME}\"><b>$(_center "✦ ${BANNER_WELCOME:-Selamat Datang!} ✦")</b></font><br>"
        echo "<font color=\"${CLR_GARIS}\">$(_center "$garis")</font><br>"
        echo "<font color=\"${CLR_SUBTITLE}\"><b>$(_center "${BANNER_SUBTITLE}")</b></font><br>"
        echo "<font color=\"${CLR_GARIS}\">$(_center "$garis")</font><br>"
        for rule in "${rules[@]}"; do
            echo "<font color=\"${CLR_RULES}\">$(_center "✗ ${rule}")</font><br>"
        done
        echo "<font color=\"${CLR_GARIS}\">$(_center "$garis")</font><br>"
        [[ -n "$BANNER_WARN" ]] && \
        echo "<font color=\"${CLR_WARN}\"><b>$(_center "⚠ ${BANNER_WARN}")</b></font><br>"
        echo "<font color=\"${CLR_GARIS}\">$(_center "$garis")</font><br>"
        [[ -n "$BANNER_WA" ]] && \
        echo "<font color=\"${CLR_PROMO}\">$(_center "📱 WA: ${BANNER_WA}")</font><br>"
        [[ -n "$BANNER_TG" ]] && \
        echo "<font color=\"${CLR_PROMO}\">$(_center "✈ TG: t.me/${BANNER_TG}")</font><br>"
        [[ -n "$BANNER_WA" || -n "$BANNER_TG" ]] && \
        echo "<font color=\"${CLR_GARIS}\">$(_center "$garis")</font><br>"
    } > /etc/issue.net
}
