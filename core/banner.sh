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

# Gradient HTML per karakter: _html_grad "text" r1 g1 b1 r2 g2 b2
_html_grad() {
    local text="$1" r1=$2 g1=$3 b1=$4 r2=$5 g2=$6 b2=$7
    python3 -c "
text = '''$text'''
r1,g1,b1 = $r1,$g1,$b1
r2,g2,b2 = $r2,$g2,$b2
n = max(len([c for c in text if c != ' ']), 2)
i = 0
out = ''
for ch in text:
    if ch == ' ':
        out += ' '
    else:
        r = r1 + (r2-r1)*i//(n-1)
        g = g1 + (g2-g1)*i//(n-1)
        b = b1 + (b2-b1)*i//(n-1)
        out += f'<font color=\"#{r:02x}{g:02x}{b:02x}\"><b>{ch}</b></font>'
        i += 1
print(out)
" 2>/dev/null
}

_get_theme_colors() {
    local theme="$1"
    case "$theme" in
        magenta) CLR_GARIS="#ff4081"; CLR_RULES="#00e5ff"; CLR_WARN="#ff1744"; CLR_PROMO="#69ff47"
                 GR_WELCOME="255 0 128   0 210 255"   # pink → cyan
                 GR_SUBTITLE="255 214 0  255 100 200" # kuning → pink
                 GR_GARIS="255 64 129   255 64 129"   ;;
        cyan)    CLR_GARIS="#00e5ff"; CLR_RULES="#69ff47"; CLR_WARN="#ff1744"; CLR_PROMO="#ffd600"
                 GR_WELCOME="0 229 255   0 255 128"
                 GR_SUBTITLE="255 214 0  0 229 255"
                 GR_GARIS="0 229 255    0 229 255"    ;;
        orange)  CLR_GARIS="#ff6d00"; CLR_RULES="#00e5ff"; CLR_WARN="#ff4081"; CLR_PROMO="#69ff47"
                 GR_WELCOME="255 109 0   255 214 0"
                 GR_SUBTITLE="255 255 255  255 109 0"
                 GR_GARIS="255 109 0    255 109 0"    ;;
        green)   CLR_GARIS="#69ff47"; CLR_RULES="#00e5ff"; CLR_WARN="#ff1744"; CLR_PROMO="#ffd600"
                 GR_WELCOME="105 255 71   0 210 255"
                 GR_SUBTITLE="255 214 0   105 255 71"
                 GR_GARIS="105 255 71   105 255 71"   ;;
        *)       CLR_GARIS="#ff4081"; CLR_RULES="#00e5ff"; CLR_WARN="#ff1744"; CLR_PROMO="#69ff47"
                 GR_WELCOME="255 0 128   0 210 255"
                 GR_SUBTITLE="255 214 0  255 100 200"
                 GR_GARIS="255 64 129   255 64 129"   ;;
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
        echo "$(_html_grad "✦ ${BANNER_WELCOME:-Selamat Datang!} ✦" $GR_WELCOME)<br>"
        [[ -n "$BANNER_SUBTITLE" ]] && \
        echo "$(_html_grad "! ${BANNER_SUBTITLE} !" $GR_SUBTITLE)<br>"
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
