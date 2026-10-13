#!/bin/zsh
# Speed Test: the last internet speed test on a neon speedometer, download big and upload small; a tap runs a new test
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT
zmodload zsh/datetime
zmodload zsh/zselect

# One template for every face of the widget: the rest glyph, the measuring sweep, a result, a failure.
# speed_frame <rest|measure|result|fail> [download bit/s] [upload bit/s] [measuring frame number 0, 1, 2 …]
# (while measuring, the speeds are those of the previous test, 0 when there is none)
speed_frame() {
  emulate -L zsh
  export LC_ALL=C
  local mode=${1:-rest} dl=${2:-0} ul=${3:-0} k=${4:-0}
  [[ $mode == (rest|measure|result|fail) ]] || mode=rest
  [[ $dl == <->(|.<->) ]] || dl=0
  [[ $ul == <->(|.<->) ]] || ul=0
  [[ $k == <-> ]] || k=0

  # Every number, text and state colour comes from awk as "key value" pairs
  # (zsh float arithmetic would print 0.17999999999999999).
  local -A v
  v=( ${=$(awk -v mode=$mode -v dl=$dl -v ul=$ul -v k=$k '
    function hex(h,   i, n) { n = 0; h = toupper(h); for (i = 1; i <= length(h); i++) n = n * 16 + index("0123456789ABCDEF", substr(h, i, 1)) - 1; return n }
    function mix(a, b, s,   i, o, x, y) {
      o = "#"
      for (i = 2; i <= 6; i += 2) { x = hex(substr(a, i, 2)); y = hex(substr(b, i, 2)); o = o sprintf("%02X", int(x + (y - x) * s + 0.5)) }
      return o
    }
    function spectrum(s) {                     # the arc gradient: #FF375F → #BF5AF2 (.35) → #5E5CE6 (.7) → #64D2FF
      if (s <= 0)   return "#FF375F"
      if (s < 0.35) return mix("#FF375F", "#BF5AF2", s / 0.35)
      if (s < 0.7)  return mix("#BF5AF2", "#5E5CE6", (s - 0.35) / 0.35)
      if (s < 1)    return mix("#5E5CE6", "#64D2FF", (s - 0.7) / 0.3)
      return "#64D2FF"
    }
    function speed(m) {                        # Mbit/s in the unit of the big value: 5.6 · 94 · 940 · 1.2 (Gbit/s)
      if (giga) m = m / 1000
      if (m >= 9.95) return sprintf("%d", int(m + 0.5))
      return sprintf("%.1f", m)
    }
    # an arrow: a shaft with a chevron at the end it points to (dir 1 = down, -1 = up), s = scale
    function arrow(x, cy, s, dir,   tail, tip, wing) {
      tail = cy - dir * 30 * s; tip = cy + dir * 28 * s; wing = cy + dir * 14 * s
      return sprintf("M%.1f,%.1fL%.1f,%.1fM%.1f,%.1fL%.1f,%.1fL%.1f,%.1f", x, tail, x, tip, x - 14 * s, wing, x, tip, x + 14 * s, wing)
    }
    function kv(k, x) { printf "%s %s\n", k, x }
    function num(k, x) { printf "%s %.2f\n", k, x }
    BEGIN {
      L = 335.10                               # arc length: r 80 · 240° = 80 · 4π/3
      mb = dl / 1e6; ub = ul / 1e6
      st = mode                                # a result is ok / warn / critical by the download speed
      if (mode == "result") { st = "ok"; if (mb < 30) st = "warn"; if (mb < 10) st = "critical" }
      live = (mode == "measure" || mode == "result") ? 1 : 0

      # lit share on a log scale: 1 Mbit/s = empty, 10 = ⅓, 100 = ⅔, 1000 = full; slow sits at the pink end
      f = 0.5                                  # rest and failure: arc end, bead and glow parked at 12 o’clock
      if (mode == "result") { f = (mb > 1) ? log(mb) / log(1000) : 0; if (f > 1) f = 1 }
      # measuring: the needle revs from 12 o’clock to the top of the scale, back, down to the bottom, back —
      # one frame a second, glided linearly. Even frames sit at 12 o’clock, so the glow (a rotation) never
      # has to turn more than 120° to reach a result or to leave one: a longer turn would go the short way,
      # through the gap at the bottom.
      if (mode == "measure") f = (k % 4 == 1) ? 0.92 : (k % 4 == 3) ? 0.08 : 0.5
      d = L * f; if (d > L - 0.3) d = L - 0.3  # keep the bead’s dash on the path
      num("off", L * (1 - f))                  # lit dash covers 0 … L·f
      num("pos", -d)                           # bead: a 0.1-long dash starting at L·f
      ang = -120 + 240 * f                     # glow: degrees clockwise from 12 o’clock
      num("ang", ang)
      x = 100 + 80 * sin(ang * 3.14159265 / 180)
      gc = spectrum((x - 24) / 152)            # glow colour = the arc colour under the bead

      giga = (mb >= 999.5)
      val = "—"; up = "—"
      # a measuring frame carries the previous result (bit/s of the last test, 0 = none) at opacity 0:
      # text content swaps at once, so the old number fades out as itself instead of turning into "—"
      if ((mode == "result" || mode == "measure") && mb > 0) { val = speed(mb); if (ub > 0) up = speed(ub) }
      kv("val", val); kv("up", up); kv("unit", giga ? "Gbps" : "Mbps")
      kv("vs", length(val) >= 4 ? 56 : 60)     # "12.5" still clears the arc

      # state:        bloom centre / mid colour and opacity, radius   glow r, opacity   halo width, opacity   unit colour, opacity   value colour, opacity   upload opacity
      if (st == "rest")     { bC = "#BF5AF2"; bA = 0.12; mC = "#5E5CE6"; bM = 0.04; bR = 82; gR = 28; gA = 0;    hW = 18; hO = 0;    uC = "#FFFFFF"; uO = 0;    vC = "#FFFFFF"; vO = 0;    upO = 0 }
      if (st == "measure")  { bC = "#BF5AF2"; bA = 0.22; mC = "#5E5CE6"; bM = 0.08; bR = 88; gR = 28; gA = 0.55; hW = 18; hO = 0.45; uC = "#FFFFFF"; uO = 0;    vC = "#FFFFFF"; vO = 0;    upO = 0 }
      if (st == "ok")       { bC = "#BF5AF2"; bA = 0.20; mC = "#5E5CE6"; bM = 0.07; bR = 86; gR = 28; gA = 0.55; hW = 18; hO = 0.45; uC = "#FFFFFF"; uO = 0.6;  vC = "#FFFFFF"; vO = 1;    upO = 0.6 }
      if (st == "warn")     { bC = "#E0479E"; bA = 0.32; mC = "#BF5AF2"; bM = 0.10; bR = 90; gR = 28; gA = 0.70; hW = 20; hO = 0.50; uC = "#FFFFFF"; uO = 0.6;  vC = "#FFFFFF"; vO = 1;    upO = 0.6 }
      if (st == "critical") { bC = "#FF375F"; bA = 0.57; mC = "#BF5AF2"; bM = 0.16; bR = 98; gR = 32; gA = 0.95; hW = 22; hO = 0.60; uC = "#FF7A96"; uO = 0.95; vC = "#FFFFFF"; vO = 1;    upO = 0.6; gc = "#FF375F" }
      if (st == "fail")     { bC = "#FF375F"; bA = 0.45; mC = "#BF5AF2"; bM = 0.12; bR = 94; gR = 28; gA = 0;    hW = 18; hO = 0;    uC = "#FF7A96"; uO = 0;    vC = "#FF7A96"; vO = 0.95; upO = 0 }
      # track: a faint spectrum on the rest face, white 0.18 while live, hot pink when slow or failed
      if (st == "rest") { split("#FF375F #BF5AF2 #5E5CE6 #64D2FF", tc, " "); split("0.30 0.30 0.30 0.30", to, " ") }
      if (st == "measure" || st == "ok" || st == "warn") { split("#FFFFFF #FFFFFF #FFFFFF #FFFFFF", tc, " "); split("0.18 0.18 0.18 0.18", to, " ") }
      if (st == "critical" || st == "fail") { split("#FF375F #FF375F #FF375F #FF375F", tc, " "); split("0.30 0.24 0.20 0.20", to, " ") }
      for (i = 1; i <= 4; i++) { kv("tc" i, tc[i]); kv("to" i, to[i]) }

      kv("gc", gc); kv("bC", bC); num("bA", bA); kv("mC", mC); num("bM", bM); kv("bR", bR)
      kv("gR", gR); num("gA", live * gA); num("gM", live * 0.4 * gA); kv("hW", hW); num("hO", live * hO)
      kv("uC", uC); num("uO", uO); kv("vC", vC); num("vO", vO); num("upO", upO)
      num("tEO", (st == "critical" || st == "fail") ? 0 : 0.9)
      num("live", live); num("litGlowO", live * 0.2); num("coreO", live * 0.45)

      # the big ↓↑ glyph is the rest face; it breathes while measuring (the arrows part and meet, 2 s a breath)
      # and when a result arrives it sinks to the bottom and fades out (the result face has no glyph)
      if (mode == "rest")         { cy = 100; s = 1;    go = 0.75; bob = 0 }
      else if (mode == "measure") { cy = 100; s = 1;    go = 0.95; bob = (k % 2) ? 5 : -5 }
      else                        { cy = 170; s = 0.45; go = 0;    bob = 0 }
      kv("down", arrow(100 - 16 * s, cy + bob, s, 1)); kv("upA", arrow(100 + 16 * s, cy - bob, s, -1))
      num("gw", 6 * s); num("go", go)
    }')} )
  local arc='d="M 30.72 140 A 80 80 0 1 1 169.28 140" fill="none"'

  printf '%s\n' "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 200 200\">\
<defs>\
<linearGradient id=\"spec\" gradientUnits=\"userSpaceOnUse\" x1=\"24\" y1=\"0\" x2=\"176\" y2=\"0\">\
<stop offset=\"0\" stop-color=\"#FF375F\"/><stop offset=\"0.35\" stop-color=\"#BF5AF2\"/><stop offset=\"0.7\" stop-color=\"#5E5CE6\"/><stop offset=\"1\" stop-color=\"#64D2FF\"/>\
</linearGradient>\
<linearGradient id=\"trackG\" gradientUnits=\"userSpaceOnUse\" x1=\"24\" y1=\"0\" x2=\"176\" y2=\"0\">\
<stop offset=\"0\" stop-color=\"$v[tc1]\" stop-opacity=\"$v[to1]\"/><stop offset=\"0.35\" stop-color=\"$v[tc2]\" stop-opacity=\"$v[to2]\"/><stop offset=\"0.7\" stop-color=\"$v[tc3]\" stop-opacity=\"$v[to3]\"/><stop offset=\"1\" stop-color=\"$v[tc4]\" stop-opacity=\"$v[to4]\"/>\
</linearGradient>\
<linearGradient id=\"glyphG\" gradientUnits=\"userSpaceOnUse\" x1=\"66\" y1=\"0\" x2=\"134\" y2=\"0\"><stop offset=\"0\" stop-color=\"#BF5AF2\"/><stop offset=\"1\" stop-color=\"#64D2FF\"/></linearGradient>\
<radialGradient id=\"bloomG\"><stop offset=\"0\" stop-color=\"$v[bC]\" stop-opacity=\"$v[bA]\"/><stop offset=\"0.55\" stop-color=\"$v[mC]\" stop-opacity=\"$v[bM]\"/><stop offset=\"1\" stop-color=\"$v[mC]\" stop-opacity=\"0\"/></radialGradient>\
<radialGradient id=\"glowG\"><stop offset=\"0\" stop-color=\"$v[gc]\" stop-opacity=\"$v[gA]\"/><stop offset=\"0.4\" stop-color=\"$v[gc]\" stop-opacity=\"$v[gM]\"/><stop offset=\"1\" stop-color=\"$v[gc]\" stop-opacity=\"0\"/></radialGradient>\
</defs>\
<circle id=\"bloom\" cx=\"100\" cy=\"100\" r=\"$v[bR]\" fill=\"url(#bloomG)\"/>\
<path id=\"track\" $arc stroke=\"url(#trackG)\" stroke-width=\"6\" stroke-linecap=\"round\"/>\
<path id=\"ticks\" d=\"M 60.15 52.51 L 56.93 48.68 M 139.85 52.51 L 143.07 48.68\" fill=\"none\" stroke=\"#FFFFFF\" stroke-opacity=\"0.3\" stroke-width=\"2.5\" stroke-linecap=\"round\"/>\
<line id=\"tickE\" x1=\"46.31\" y1=\"131\" x2=\"41.98\" y2=\"133.5\" stroke=\"#FF375F\" stroke-opacity=\"$v[tEO]\" stroke-width=\"3\" stroke-linecap=\"round\"/>\
<line id=\"tickF\" x1=\"153.69\" y1=\"131\" x2=\"158.02\" y2=\"133.5\" stroke=\"#64D2FF\" stroke-opacity=\"0.9\" stroke-width=\"3\" stroke-linecap=\"round\"/>\
<path id=\"litGlow\" $arc stroke=\"url(#spec)\" stroke-opacity=\"$v[litGlowO]\" stroke-width=\"22\" stroke-linecap=\"round\" stroke-dasharray=\"335.1 335.1\" stroke-dashoffset=\"$v[off]\"/>\
<path id=\"lit\" $arc stroke=\"url(#spec)\" stroke-opacity=\"$v[live]\" stroke-width=\"9\" stroke-linecap=\"round\" stroke-dasharray=\"335.1 335.1\" stroke-dashoffset=\"$v[off]\"/>\
<path id=\"core\" $arc stroke=\"#FFFFFF\" stroke-opacity=\"$v[coreO]\" stroke-width=\"2.5\" stroke-linecap=\"round\" stroke-dasharray=\"335.1 335.1\" stroke-dashoffset=\"$v[off]\"/>\
<circle id=\"glow\" cx=\"100\" cy=\"26\" r=\"$v[gR]\" fill=\"url(#glowG)\" transform=\"rotate($v[ang] 100 100)\"/>\
<path id=\"halo\" $arc stroke=\"url(#spec)\" stroke-opacity=\"$v[hO]\" stroke-width=\"$v[hW]\" stroke-linecap=\"round\" stroke-dasharray=\"0.1 400\" stroke-dashoffset=\"$v[pos]\"/>\
<path id=\"bead\" $arc stroke=\"#FFFFFF\" stroke-opacity=\"$v[live]\" stroke-width=\"12\" stroke-linecap=\"round\" stroke-dasharray=\"0.1 400\" stroke-dashoffset=\"$v[pos]\"/>\
<text id=\"value\" x=\"100\" y=\"94\" font-size=\"$v[vs]\" font-weight=\"600\" text-anchor=\"middle\" dominant-baseline=\"middle\" fill=\"$v[vC]\" fill-opacity=\"$v[vO]\">$v[val]</text>\
<text id=\"unit\" x=\"100\" y=\"133\" font-size=\"26\" font-weight=\"600\" text-anchor=\"middle\" dominant-baseline=\"middle\" fill=\"$v[uC]\" fill-opacity=\"$v[uO]\">$v[unit]</text>\
<text id=\"upload\" x=\"100\" y=\"170\" font-size=\"26\" font-weight=\"600\" text-anchor=\"middle\" dominant-baseline=\"middle\" fill=\"#FFFFFF\" fill-opacity=\"$v[upO]\">↑ $v[up]</text>\
<path id=\"arrowDown\" d=\"$v[down]\" fill=\"none\" stroke=\"url(#glyphG)\" stroke-opacity=\"$v[go]\" stroke-width=\"$v[gw]\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>\
<path id=\"arrowUp\" d=\"$v[upA]\" fill=\"none\" stroke=\"url(#glyphG)\" stroke-opacity=\"$v[go]\" stroke-width=\"$v[gw]\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>\
</svg>"
}

api="http://127.0.0.1:9848/api"
cell="{{CELL_ID}}"
dir="$DESMAPTIC_STORAGE/gallery/{{CELL_ID}}"   # written by the tap script: result = "ok <down bit/s> <up bit/s> <epoch>" or "fail <epoch>"

nap() { zselect -t $(( $1 * 100 )); return 0 }   # sleep without starting a process

# The tap script is drawing (it posts a frame a second while networkQuality runs).
measuring() {
  local pid started
  [[ -r $dir/measuring ]] || return 1
  read -r pid started < "$dir/measuring"
  [[ $pid == <-> && $started == <-> ]] || return 1
  (( EPOCHSECONDS - started < 90 )) && kill -0 $pid 2>/dev/null
}

# The face of the last test, or the rest glyph before the first one.
saved_frame() {
  local kind dl ul rest
  read -r kind dl ul rest <<< "$1"
  case $kind in
    ok)   speed_frame result $dl $ul ;;
    fail) speed_frame fail ;;
    *)    speed_frame rest ;;
  esac
}

hidden=0
post() {
  local json=$1 reply code
  json=${json//\\/\\\\}; json=${json//\"/\\\"}; json=${json//$'\n'/}
  reply=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/update-button" \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}' -H "Content-Type: application/json" \
    -d "{\"cellId\":\"$cell\",\"svg\":{\"source\":\"$json\",\"duration\":1.2}}")
  code=${reply##*$'\n'}
  if [[ $code != 200 ]]; then
    print -u2 "Speed Test: update-button answered ${code:-nothing}: ${${reply%$'\n'*}[1,300]}"
    return 1
  fi
  [[ ${reply// /} == *'"visible":false'* ]] && hidden=1 || hidden=0
  return 0
}

# The phone shows this button (or is too old to say).
on_screen() {
  local view
  view=$(curl -q -s -m 5 "$api/view" --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}') || return 0
  view=${view// /}
  [[ $view == *'"view":null'* ]] && return 0
  [[ ${(L)view} == *${(L)cell}* ]]
}

shown=$'\0'      # the saved result line the face shows now; \0 = draw again
while true; do
  if measuring; then
    shown=$'\0'  # afterwards the saved face is posted once more (a stopped tap leaves the rest face)
    nap 2
    [[ -f $dir/measuring ]] || nap 2   # let the result glide finish before posting it again
    continue
  fi
  state=""
  [[ -r $dir/result ]] && read -r state < "$dir/result"
  if [[ $state != "$shown" ]]; then
    if post "$(saved_frame "$state")"; then
      shown=$state
      if (( hidden )); then
        # nobody sees the button: look every 3 s whether it is back, then draw it again
        until on_screen; do nap 3; done
        shown=$'\0'
        continue
      fi
    else
      nap 10
      continue
    fi
  fi
  nap 3
done
