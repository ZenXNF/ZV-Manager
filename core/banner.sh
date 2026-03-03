#!/bin/bash
# ============================================================
#   ZV-Manager - Banner Generator
#   Generate /etc/issue.net dari banner.conf
# ============================================================

BANNER_CONF="/etc/zv-manager/banner.conf"

# Default config kalau belum ada
_init_banner_conf() {
    [[ -f "$BANNER_CONF" ]] && return
    cat > "$BANNER_CONF" <<'CONFEOF'
BANNER_TITLE="ZV-Manager SSH Tunnel"
BANNER_SUBTITLE="! TERM OF SERVICE !"
BANNER_RULE_1="NO SPAM"
BANNER_RULE_2="NO DDOS / SERANGAN"
BANNER_RULE_3="NO HACKING / CARDING"
BANNER_RULE_4="NO TORRENT"
BANNER_RULE_5="NO MULTI LOGIN"
BANNER_WARN="VIOLATION = PERMANENT BAN"
BANNER_THEME="magenta"
CONFEOF
}

# Ambil warna berdasarkan tema
_get_theme_colors() {
    local theme="$1"
    case "$theme" in
        magenta)
            CLR_GARIS="#ff4081"
            CLR_TITLE="#ffd600"
            CLR_SUBTITLE="#ffffff"
            CLR_RULES="#00e5ff"
            CLR_WARN="#ff1744"
            ;;
        cyan)
            CLR_GARIS="#00e5ff"
            CLR_TITLE="#ffd600"
            CLR_SUBTITLE="#ffffff"
            CLR_RULES="#69ff47"
            CLR_WARN="#ff1744"
            ;;
        orange)
            CLR_GARIS="#ff6d00"
            CLR_TITLE="#ffffff"
            CLR_SUBTITLE="#ffd600"
            CLR_RULES="#00e5ff"
            CLR_WARN="#ff4081"
            ;;
        green)
            CLR_GARIS="#69ff47"
            CLR_TITLE="#ffd600"
            CLR_SUBTITLE="#ffffff"
            CLR_RULES="#00e5ff"
            CLR_WARN="#ff1744"
            ;;
        *)  # default magenta
            CLR_GARIS="#ff4081"
            CLR_TITLE="#ffd600"
            CLR_SUBTITLE="#ffffff"
            CLR_RULES="#00e5ff"
            CLR_WARN="#ff1744"
            ;;
    esac
}

# Generate /etc/issue.net dari config
generate_banner() {
    _init_banner_conf

    # Load config
    unset BANNER_TITLE BANNER_SUBTITLE BANNER_WARN BANNER_THEME
    unset BANNER_RULE_1 BANNER_RULE_2 BANNER_RULE_3 BANNER_RULE_4 BANNER_RULE_5
    source "$BANNER_CONF"

    _get_theme_colors "${BANNER_THEME:-magenta}"

    # Kumpulkan rules yang tidak kosong
    local rules=()
    for r in "$BANNER_RULE_1" "$BANNER_RULE_2" "$BANNER_RULE_3" "$BANNER_RULE_4" "$BANNER_RULE_5"; do
        [[ -n "$r" ]] && rules+=("$r")
    done

    # Tulis ke /etc/issue.net
    {
        echo "<font color=\"${CLR_GARIS}\">　　　▬▬▬ஜ۩۞۩ஜ▬▬▬</font><br>"
        echo "<font color=\"${CLR_TITLE}\">　　--- ${BANNER_TITLE} ---</font><br>"
        echo "<font color=\"${CLR_GARIS}\">　　　▬▬▬ஜ۩۞۩ஜ▬▬▬</font><br>"
        echo "<font color=\"${CLR_SUBTITLE}\">　　　${BANNER_SUBTITLE}</font><br>"
        for rule in "${rules[@]}"; do
            echo "<font color=\"${CLR_RULES}\">　　　✗  ${rule}</font><br>"
        done
        [[ -n "$BANNER_WARN" ]] && \
        echo "<font color=\"${CLR_WARN}\">　　　✔  ${BANNER_WARN}</font><br>"
        echo "<font color=\"${CLR_GARIS}\">　　　▬▬▬ஜ۩۞۩ஜ▬▬▬</font>"
    } > /etc/issue.net
}
