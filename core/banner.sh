#!/bin/bash
# ============================================================
#   ZV-Manager - Banner Generator
#   Generate /etc/issue.net dari banner.conf
#   NOTE: HTTP Custom auto-center semua teks banner di level
#         app-nya — tidak perlu padding manual sama sekali.
# ============================================================

BANNER_CONF="/etc/zv-manager/banner.conf"

_init_banner_conf() {
    [[ -f "$BANNER_CONF" ]] && return
    cat > "$BANNER_CONF" <<'CONFEOF'
BANNER_WELCOME="Selamat Datang!"
BANNER_SUBTITLE="TERMS AND CONDITIONS"
BANNER_RULE_1="NO SPAM"
BANNER_RULE_2="NO DDOS / SERANGAN"
BANNER_RULE_3="NO HACKING / CARDING"
BANNER_RULE_4="NO TORRENT"
BANNER_RULE_5="NO MULTI LOGIN"
BANNER_WARN="VIOLATION = BAN"
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

generate_banner() {
    _init_banner_conf

    unset BANNER_WELCOME BANNER_SUBTITLE BANNER_WARN BANNER_THEME BANNER_WA BANNER_TG
    unset BANNER_RULE_1 BANNER_RULE_2 BANNER_RULE_3 BANNER_RULE_4 BANNER_RULE_5
    source "$BANNER_CONF"

    _get_theme_colors "${BANNER_THEME:-magenta}"

    local rules=()
    for r in "$BANNER_RULE_1" "$BANNER_RULE_2" "$BANNER_RULE_3" "$BANNER_RULE_4" "$BANNER_RULE_5"; do
        [[ -n "$r" ]] && rules+=("$r")
    done

    {
        echo "<font color=\"${CLR_GARIS}\">▬▬▬ஜ۩۞۩ஜ▬▬▬</font><br>"
        echo "<font color=\"${CLR_WELCOME}\"><b>✦ ${BANNER_WELCOME:-Selamat Datang!} ✦</b></font><br>"
        [[ -n "$BANNER_SUBTITLE" ]] && \
        echo "<font color=\"${CLR_SUBTITLE}\"><b>! ${BANNER_SUBTITLE} !</b></font><br>"
        for rule in "${rules[@]}"; do
            echo "<font color=\"${CLR_RULES}\"><b>${rule}</b></font><br>"
        done
        [[ -n "$BANNER_WARN" ]] && \
        echo "<font color=\"${CLR_WARN}\"><b>${BANNER_WARN}</b></font><br>"
        echo "<font color=\"${CLR_GARIS}\">▬▬▬ஜ۩۞۩ஜ▬▬▬</font><br>"
        [[ -n "$BANNER_WA" ]] && \
        echo "<font color=\"${CLR_PROMO}\">📱 WA: ${BANNER_WA}</font><br>"
        [[ -n "$BANNER_TG" ]] && \
        echo "<font color=\"${CLR_PROMO}\">✈ TG: t.me/${BANNER_TG}</font><br>"
        [[ -n "$BANNER_WA" || -n "$BANNER_TG" ]] && \
        echo "<font color=\"${CLR_GARIS}\">▬▬▬ஜ۩۞۩ஜ▬▬▬</font><br>"
    } > /etc/issue.net
}
