#!/bin/zsh
# Memory: how much memory is in use, drawn as a neon gauge that glows hot pink when macOS reports memory pressure
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT

# One frame of the gauge. used: 0…100; heat: 0…1000 (0 normal, 500 warning, 1000 critical); value: the text; state: rest | live.
memory_frame() {
  emulate -L zsh
  export LC_ALL=C
  local used=${1:-0} heat=${2:-0} value=${3:-0} state=${4:-rest}
  [[ $used == <-> ]] || used=0
  [[ $heat == <-> ]] || heat=0
  (( used > 100 )) && used=100
  (( heat > 1000 )) && heat=1000
  [[ $state == (rest|live) ]] || state=rest
  [[ -z $value ]] && value=0
  local vsize=60
  (( ${#value} >= 4 )) && vsize=56
  value=${value//&/&amp;}; value=${value//</&lt;}; value=${value//>/&gt;}

  # Every number and colour comes from awk as "key value" pairs
  # (zsh float arithmetic would print 0.17999999999999999).
  local -A v
  v=( ${=$(awk -v s=$used -v h=$heat -v st=$state '
    function hex(x,   i, n) { n = 0; x = toupper(x); for (i = 1; i <= length(x); i++) n = n * 16 + index("0123456789ABCDEF", substr(x, i, 1)) - 1; return n }
    function mix(a, b, t,   i, o, x, y) {
      o = "#"
      for (i = 2; i <= 6; i += 2) { x = hex(substr(a, i, 2)); y = hex(substr(b, i, 2)); o = o sprintf("%02X", int(x + (y - x) * t + 0.5)) }
      return o
    }
    function spectrum(t) {                     # the arc gradient, calm left → attention right: #64D2FF → #5E5CE6 (.3) → #BF5AF2 (.65) → #FF375F
      if (t <= 0)    return "#64D2FF"
      if (t < 0.3)   return mix("#64D2FF", "#5E5CE6", t / 0.3)
      if (t < 0.65)  return mix("#5E5CE6", "#BF5AF2", (t - 0.3) / 0.35)
      if (t < 1)     return mix("#BF5AF2", "#FF375F", (t - 0.65) / 0.35)
      return "#FF375F"
    }
    function lerp(a, b, t) { return a + (b - a) * t }
    function p3(a, b, c) { return (H < 0.5) ? lerp(a, b, H * 2) : lerp(b, c, H * 2 - 1) }   # normal → warning → critical
    function c3(a, b, c) { return (H < 0.5) ? mix(a, b, H * 2) : mix(b, c, H * 2 - 1) }
    function clamp(x) { return x < 0 ? 0 : (x > 1 ? 1 : x) }
    function kv(k, x) { printf "%s %s\n", k, x }
    function num(k, x) { printf "%s %.2f\n", k, x }
    BEGIN {
      L = 335.10                               # arc length: r 80 · 240° = 80 · 4π/3
      live = (st == "rest") ? 0 : 1
      f = clamp(s / 100); H = live ? clamp(h / 1000) : 0
      if (!live) f = 0.5                       # rest: arc end, bead and glow parked at 12 o’clock
      d = L * f; if (d > L - 0.3) d = L - 0.3  # keep the bead’s dash on the path
      num("off", L * (1 - f))                  # lit dash covers 0 … L·f
      num("pos", -d)                           # bead: a 0.1-long dash starting at L·f
      ang = -120 + 240 * f                     # glow: degrees clockwise from 12 o’clock
      num("ang", ang)
      x = 100 + 80 * sin(ang * 3.14159265 / 180)
      gc = mix(spectrum((x - 24) / 152), "#FF375F", H > 0.5 ? H * 2 - 1 : 0)

      # bloom, glow, halo and unit heat up with the pressure; the rest face is the cool one
      if (live) {
        bC = c3("#BF5AF2", "#E0479E", "#FF375F"); bA = p3(0.20, 0.32, 0.57); mC = c3("#5E5CE6", "#BF5AF2", "#BF5AF2"); bM = p3(0.07, 0.10, 0.16); bR = p3(86, 90, 98)
        gR = p3(28, 28, 32); gA = p3(0.55, 0.70, 0.95); hW = p3(18, 20, 22); hO = p3(0.45, 0.50, 0.60)
        uC = c3("#FFFFFF", "#FFFFFF", "#FF7A96"); uO = p3(0.6, 0.6, 0.95)
        g1 = c3("#64D2FF", "#BF5AF2", "#FF8FA8"); g2 = c3("#BF5AF2", "#FF6FA0", "#FF375F")
        split("0.20 0.20 0.24 0.30", hot, " ")
        for (i = 1; i <= 4; i++) { kv("tc" i, c3("#FFFFFF", "#FFFFFF", "#FF375F")); num("to" i, p3(0.18, 0.18, hot[i])) }
      } else {
        bC = "#BF5AF2"; bA = 0.12; mC = "#5E5CE6"; bM = 0.04; bR = 82; gR = 28; gA = 0.55; hW = 18; hO = 0.45
        uC = "#FFFFFF"; uO = 0.6; g1 = "#64D2FF"; g2 = "#BF5AF2"
        split("#64D2FF #5E5CE6 #BF5AF2 #FF375F", tc, " ")
        for (i = 1; i <= 4; i++) { kv("tc" i, tc[i]); num("to" i, 0.30) }
      }
      kv("gc", gc); kv("bC", bC); num("bA", bA); kv("mC", mC); num("bM", bM); num("bR", bR)
      num("gR", gR); num("gA", live * gA); num("gM", live * 0.4 * gA); num("hW", hW); num("hO", live * hO)
      kv("uC", uC); num("uO", live * uO); kv("g1", g1); kv("g2", g2)
      num("live", live); num("litGlowO", live * 0.2); num("coreO", live * 0.45)
      # end ticks step aside when the bead sits on them
      num("tLO", live ? 0.9 * clamp((f - 0.03) / 0.05) : 0.9)
      num("tRO", live ? 0.9 * clamp((0.97 - f) / 0.05) : 0.9)

      # the memory module: big in the middle on the rest face; when data arrives it sinks below the unit and stays as a small mark
      # (it is drawn under the text, so the number fades in over it while it sinks)
      if (live) { cx = 100; cy = 172.5; k = 0.36; w = 2.6; o = 0.6; lo = 0.85 } else { cx = 100; cy = 102; k = 1; w = 5; o = 0.75; lo = 0.5 }
      num("bx", cx - 46 * k); num("by", cy - 25 * k); num("bw", 92 * k); num("bh", 36 * k); num("br", 7 * k)
      num("gx1", cx - 50 * k); num("gx2", cx + 50 * k); num("sw", w); num("go", o); num("lo", lo)
      c = ""                                   # three memory chips on the board
      for (j = -1; j <= 1; j++) {
        x0 = cx + (26 * j - 9) * k
        c = c sprintf("M %.2f %.2f H %.2f V %.2f H %.2f Z ", x0, cy - 14 * k, x0 + 18 * k, cy, x0)
      }
      sub(/ $/, "", c); gsub(/ /, "_", c); kv("chips", c)
      p = ""                                   # contacts along the bottom edge, the key notch in the middle
      split("-36 -25 -14 14 25 36", px, " ")
      for (j = 1; j <= 6; j++) p = p sprintf("M %.2f %.2f L %.2f %.2f ", cx + px[j] * k, cy + 11 * k, cx + px[j] * k, cy + 20 * k)
      sub(/ $/, "", p); gsub(/ /, "_", p); kv("pins", p)
    }')} )
  local arc='d="M 30.72 140 A 80 80 0 1 1 169.28 140" fill="none"'

  printf '%s\n' "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 200 200\">\
<defs>\
<linearGradient id=\"spec\" gradientUnits=\"userSpaceOnUse\" x1=\"24\" y1=\"0\" x2=\"176\" y2=\"0\">\
<stop offset=\"0\" stop-color=\"#64D2FF\"/><stop offset=\"0.3\" stop-color=\"#5E5CE6\"/><stop offset=\"0.65\" stop-color=\"#BF5AF2\"/><stop offset=\"1\" stop-color=\"#FF375F\"/>\
</linearGradient>\
<linearGradient id=\"trackG\" gradientUnits=\"userSpaceOnUse\" x1=\"24\" y1=\"0\" x2=\"176\" y2=\"0\">\
<stop offset=\"0\" stop-color=\"$v[tc1]\" stop-opacity=\"$v[to1]\"/><stop offset=\"0.3\" stop-color=\"$v[tc2]\" stop-opacity=\"$v[to2]\"/><stop offset=\"0.65\" stop-color=\"$v[tc3]\" stop-opacity=\"$v[to3]\"/><stop offset=\"1\" stop-color=\"$v[tc4]\" stop-opacity=\"$v[to4]\"/>\
</linearGradient>\
<linearGradient id=\"ramG\" gradientUnits=\"userSpaceOnUse\" x1=\"$v[gx1]\" y1=\"0\" x2=\"$v[gx2]\" y2=\"0\"><stop offset=\"0\" stop-color=\"$v[g1]\"/><stop offset=\"1\" stop-color=\"$v[g2]\"/></linearGradient>\
<radialGradient id=\"bloomG\"><stop offset=\"0\" stop-color=\"$v[bC]\" stop-opacity=\"$v[bA]\"/><stop offset=\"0.55\" stop-color=\"$v[mC]\" stop-opacity=\"$v[bM]\"/><stop offset=\"1\" stop-color=\"$v[mC]\" stop-opacity=\"0\"/></radialGradient>\
<radialGradient id=\"glowG\"><stop offset=\"0\" stop-color=\"$v[gc]\" stop-opacity=\"$v[gA]\"/><stop offset=\"0.4\" stop-color=\"$v[gc]\" stop-opacity=\"$v[gM]\"/><stop offset=\"1\" stop-color=\"$v[gc]\" stop-opacity=\"0\"/></radialGradient>\
</defs>\
<circle id=\"bloom\" cx=\"100\" cy=\"100\" r=\"$v[bR]\" fill=\"url(#bloomG)\"/>\
<path id=\"track\" $arc stroke=\"url(#trackG)\" stroke-width=\"6\" stroke-linecap=\"round\"/>\
<path id=\"ticks\" d=\"M 100 38 L 100 33\" fill=\"none\" stroke=\"#FFFFFF\" stroke-opacity=\"0.3\" stroke-width=\"2.5\" stroke-linecap=\"round\"/>\
<line id=\"tickL\" x1=\"46.31\" y1=\"131\" x2=\"41.98\" y2=\"133.5\" stroke=\"#64D2FF\" stroke-opacity=\"$v[tLO]\" stroke-width=\"3\" stroke-linecap=\"round\"/>\
<line id=\"tickR\" x1=\"153.69\" y1=\"131\" x2=\"158.02\" y2=\"133.5\" stroke=\"#FF375F\" stroke-opacity=\"$v[tRO]\" stroke-width=\"3\" stroke-linecap=\"round\"/>\
<path id=\"litGlow\" $arc stroke=\"url(#spec)\" stroke-opacity=\"$v[litGlowO]\" stroke-width=\"22\" stroke-linecap=\"round\" stroke-dasharray=\"335.1 335.1\" stroke-dashoffset=\"$v[off]\"/>\
<path id=\"lit\" $arc stroke=\"url(#spec)\" stroke-opacity=\"$v[live]\" stroke-width=\"9\" stroke-linecap=\"round\" stroke-dasharray=\"335.1 335.1\" stroke-dashoffset=\"$v[off]\"/>\
<path id=\"core\" $arc stroke=\"#FFFFFF\" stroke-opacity=\"$v[coreO]\" stroke-width=\"2.5\" stroke-linecap=\"round\" stroke-dasharray=\"335.1 335.1\" stroke-dashoffset=\"$v[off]\"/>\
<circle id=\"glow\" cx=\"100\" cy=\"26\" r=\"$v[gR]\" fill=\"url(#glowG)\" transform=\"rotate($v[ang] 100 100)\"/>\
<path id=\"halo\" $arc stroke=\"url(#spec)\" stroke-opacity=\"$v[hO]\" stroke-width=\"$v[hW]\" stroke-linecap=\"round\" stroke-dasharray=\"0.1 400\" stroke-dashoffset=\"$v[pos]\"/>\
<path id=\"bead\" $arc stroke=\"#FFFFFF\" stroke-opacity=\"$v[live]\" stroke-width=\"12\" stroke-linecap=\"round\" stroke-dasharray=\"0.1 400\" stroke-dashoffset=\"$v[pos]\"/>\
<path id=\"contacts\" d=\"${v[pins]//_/ }\" fill=\"none\" stroke=\"url(#ramG)\" stroke-opacity=\"$v[go]\" stroke-width=\"$v[sw]\" stroke-linecap=\"round\"/>\
<rect id=\"board\" x=\"$v[bx]\" y=\"$v[by]\" width=\"$v[bw]\" height=\"$v[bh]\" rx=\"$v[br]\" fill=\"none\" stroke=\"url(#ramG)\" stroke-opacity=\"$v[go]\" stroke-width=\"$v[sw]\"/>\
<path id=\"chips\" d=\"${v[chips]//_/ }\" fill=\"url(#ramG)\" fill-opacity=\"$v[lo]\"/>\
<text id=\"value\" x=\"100\" y=\"97\" font-size=\"$vsize\" font-weight=\"600\" text-anchor=\"middle\" dominant-baseline=\"middle\" fill=\"#FFFFFF\" fill-opacity=\"$v[live]\">$value</text>\
<text id=\"unit\" x=\"100\" y=\"138\" font-size=\"26\" font-weight=\"600\" text-anchor=\"middle\" dominant-baseline=\"middle\" fill=\"$v[uC]\" fill-opacity=\"$v[uO]\">%</text>\
</svg>"
}

api="http://127.0.0.1:9848/api"
cell="{{CELL_ID}}"; cell=${(L)cell}

# Posts a frame with a glide of $2 seconds. Sets code (HTTP status) and hidden (1 when the button is off screen).
post() {
  local json=$1 out body
  json=${json//\\/\\\\}; json=${json//\"/\\\"}; json=${json//$'\n'/}
  out=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/update-button" \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}' -H "Content-Type: application/json" \
    -d "{\"cellId\":\"{{CELL_ID}}\",\"svg\":{\"source\":\"$json\",\"duration\":${2:-1.2}}}")
  code=${out##*$'\n'}; body=${out%$'\n'*}
  hidden=0
  [[ ${body// /} == *'"visible":false'* ]] && hidden=1
  [[ $code == 200 ]] || print -u2 "update-button: HTTP $code ${body[1,300]}"
}

# True while the phone shows this button — or cannot say (older app, agent busy): then draw.
on_screen() {
  local out
  out=$(curl -q -s -m 5 "$api/view" --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}') || return 0
  out=${(L)out// /}
  [[ $out != *visiblecellids* ]] && return 0
  [[ $out == *\"$cell\"* ]]
}

last=""; drawn=""; complained=0
while true; do
  # kern.memorystatus_level: percent of memory available; kern.memorystatus_vm_pressure_level: 1 normal, 2 warning, 4 critical
  level=""; pressure=""
  for line in ${(f)"$(sysctl kern.memorystatus_level kern.memorystatus_vm_pressure_level 2>/dev/null)"}; do
    case $line in
      (kern.memorystatus_level:*) level=${line##* } ;;
      (kern.memorystatus_vm_pressure_level:*) pressure=${line##* } ;;
    esac
  done
  if [[ $level == <-> ]]; then
    used=$(( 100 - level )); (( used < 0 )) && used=0; (( used > 100 )) && used=100
    case $pressure in
      (4) heat=1000 ;;
      (2) heat=500 ;;
      (*) heat=0 ;;
    esac
    frame=$(memory_frame $used $heat $used live)
  else
    (( complained++ )) || print -u2 "kern.memorystatus_level is not readable on this Mac"
    used=""; frame=$(memory_frame 50 0 "—" rest)
  fi
  if [[ $frame != "$last" ]]; then
    # A jump of more than 70 points turns the glow more than 168°: the phone would take the short way,
    # under the gauge. Stop halfway first, so every leg runs along the arc.
    if [[ -n $used && -n $drawn ]] && (( used - drawn > 70 || drawn - used > 70 )); then
      mid=$(( (used + drawn) / 2 ))
      post "$(memory_frame $mid $heat $mid live)" 0.6
      [[ $code == 200 ]] && sleep 0.6
    fi
    post "$frame" 1.2
    if [[ $code != 200 ]]; then
      last=""; sleep 10; continue
    fi
    last=$frame; drawn=$used
    if (( hidden )); then                             # nobody sees it: stop sampling until the button is back
      until on_screen; do sleep 3; done
      last=""; continue
    fi
  fi
  sleep 5
done
