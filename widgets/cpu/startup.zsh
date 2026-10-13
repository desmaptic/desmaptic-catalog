#!/bin/zsh
# CPU Load: how busy the processor is, in percent, drawn as a neon gauge that turns hot pink under heavy load
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

iopid=""
stop_iostat() { [[ -n $iopid ]] && kill $iopid 2>/dev/null; iopid="" }
trap 'stop_iostat; exit 0' TERM INT

# One frame of the gauge. load: 0…100; heat: 0…1000 (0 calm, 500 busy, 1000 hot); value: the text; state: rest | live.
cpu_frame() {
  emulate -L zsh
  export LC_ALL=C
  local load=${1:-0} heat=${2:-0} value=${3:-0} state=${4:-rest}
  [[ $load == <-> ]] || load=0
  [[ $heat == <-> ]] || heat=0
  (( load > 100 )) && load=100
  (( heat > 1000 )) && heat=1000
  [[ $state == (rest|live) ]] || state=rest
  [[ -z $value ]] && value=0
  local vsize=60
  (( ${#value} >= 4 )) && vsize=56
  value=${value//&/&amp;}; value=${value//</&lt;}; value=${value//>/&gt;}

  # Every number and colour comes from awk as "key value" pairs
  # (zsh float arithmetic would print 0.17999999999999999).
  local -A v
  v=( ${=$(awk -v s=$load -v h=$heat -v st=$state '
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
    function p3(a, b, c) { return (H < 0.5) ? lerp(a, b, H * 2) : lerp(b, c, H * 2 - 1) }   # calm → busy → hot
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

      # bloom, glow, halo and unit heat up with the load; the rest face is the cool one
      if (live) {
        bC = c3("#BF5AF2", "#E0479E", "#FF375F"); bA = p3(0.20, 0.32, 0.57); mC = c3("#5E5CE6", "#BF5AF2", "#BF5AF2"); bM = p3(0.07, 0.10, 0.16); bR = p3(86, 90, 98)
        gR = p3(28, 28, 32); gA = p3(0.55, 0.70, 0.95); hW = p3(18, 20, 22); hO = p3(0.45, 0.50, 0.60)
        led = c3("#64D2FF", "#E24FC9", "#FF375F"); uC = c3("#FFFFFF", "#FFFFFF", "#FF7A96"); uO = p3(0.6, 0.6, 0.95)
        g1 = c3("#64D2FF", "#BF5AF2", "#FF8FA8"); g2 = c3("#BF5AF2", "#FF6FA0", "#FF375F")
        split("0.20 0.20 0.24 0.30", hot, " ")
        for (i = 1; i <= 4; i++) { kv("tc" i, c3("#FFFFFF", "#FFFFFF", "#FF375F")); num("to" i, p3(0.18, 0.18, hot[i])) }
      } else {
        bC = "#BF5AF2"; bA = 0.12; mC = "#5E5CE6"; bM = 0.04; bR = 82; gR = 28; gA = 0.55; hW = 18; hO = 0.45
        led = "#64D2FF"; uC = "#FFFFFF"; uO = 0.6; g1 = "#64D2FF"; g2 = "#BF5AF2"
        split("#64D2FF #5E5CE6 #BF5AF2 #FF375F", tc, " ")
        for (i = 1; i <= 4; i++) { kv("tc" i, tc[i]); num("to" i, 0.30) }
      }
      kv("gc", gc); kv("bC", bC); num("bA", bA); kv("mC", mC); num("bM", bM); num("bR", bR)
      num("gR", gR); num("gA", live * gA); num("gM", live * 0.4 * gA); num("hW", hW); num("hO", live * hO)
      kv("uC", uC); num("uO", live * uO); kv("g1", g1); kv("g2", g2); kv("led", led)
      num("live", live); num("litGlowO", live * 0.2); num("coreO", live * 0.45)
      # end ticks step aside when the bead sits on them
      num("tLO", live ? 0.9 * clamp((f - 0.03) / 0.05) : 0.9)
      num("tRO", live ? 0.9 * clamp((0.97 - f) / 0.05) : 0.9)

      # the chip: big in the middle on the rest face; when data arrives it sinks below the unit and stays as a small mark
      # (it is drawn under the text, so the number fades in over it while it sinks)
      if (live) { cx = 100; cy = 172; k = 0.3; w = 2.6; o = 0.6; lo = 0.9 } else { cx = 100; cy = 100; k = 1; w = 5; o = 0.75; lo = 1 }
      num("bx", cx - 30 * k); num("by", cy - 30 * k); num("bw", 60 * k); num("br", 10 * k)
      num("dx", cx - 12 * k); num("dy", cy - 12 * k); num("dw", 24 * k); num("dr", 4 * k)
      num("gx1", cx - 44 * k); num("gx2", cx + 44 * k); num("sw", w); num("go", o); num("lo", lo)
      p = ""
      for (j = -1; j <= 1; j++) {
        q = 16 * j * k
        p = p sprintf("M %.2f %.2f L %.2f %.2f ", cx + q, cy - 30 * k, cx + q, cy - 41 * k)
        p = p sprintf("M %.2f %.2f L %.2f %.2f ", cx + q, cy + 30 * k, cx + q, cy + 41 * k)
        p = p sprintf("M %.2f %.2f L %.2f %.2f ", cx - 30 * k, cy + q, cx - 41 * k, cy + q)
        p = p sprintf("M %.2f %.2f L %.2f %.2f ", cx + 30 * k, cy + q, cx + 41 * k, cy + q)
      }
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
<linearGradient id=\"chipG\" gradientUnits=\"userSpaceOnUse\" x1=\"$v[gx1]\" y1=\"0\" x2=\"$v[gx2]\" y2=\"0\"><stop offset=\"0\" stop-color=\"$v[g1]\"/><stop offset=\"1\" stop-color=\"$v[g2]\"/></linearGradient>\
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
<path id=\"pins\" d=\"${v[pins]//_/ }\" fill=\"none\" stroke=\"url(#chipG)\" stroke-opacity=\"$v[go]\" stroke-width=\"$v[sw]\" stroke-linecap=\"round\"/>\
<rect id=\"chip\" x=\"$v[bx]\" y=\"$v[by]\" width=\"$v[bw]\" height=\"$v[bw]\" rx=\"$v[br]\" fill=\"none\" stroke=\"url(#chipG)\" stroke-opacity=\"$v[go]\" stroke-width=\"$v[sw]\"/>\
<rect id=\"die\" x=\"$v[dx]\" y=\"$v[dy]\" width=\"$v[dw]\" height=\"$v[dw]\" rx=\"$v[dr]\" fill=\"$v[led]\" fill-opacity=\"$v[lo]\"/>\
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

# heat: calm up to 50 %, hot at 95 % and above
live_frame() {
  local heat=0
  (( $1 > 50 )) && heat=$(( ($1 - 50) * 1000 / 45 ))
  cpu_frame $1 $heat $1 live
}

# One long-lived sampler: a line of "us sy id 1m 5m 15m" every 2 s (the first line is the average since boot).
start_iostat() {
  coproc iostat -n 0 -w 2 2>/dev/null
  iopid=$!; fresh=1
}

last=""; drawn=""; retry_at=0
start_iostat
while true; do
  if ! read -t 10 -p line; then
    print -u2 "iostat stopped answering; starting it again"
    stop_iostat; sleep 5; start_iostat; continue
  fi
  set -- ${=line}
  [[ $1 == <-> && $3 == <-> ]] || continue          # the header, repeated now and then
  if (( fresh )); then fresh=0; continue; fi
  load=$(( 100 - $3 )); (( load < 0 )) && load=0; (( load > 100 )) && load=100
  frame=$(live_frame $load)
  [[ $frame == "$last" ]] && continue
  (( SECONDS < retry_at )) && continue
  # A jump of more than 70 points turns the glow more than 168°: the phone would take the short way,
  # under the gauge. Stop halfway first, so every leg runs along the arc.
  if [[ -n $drawn ]] && (( load - drawn > 70 || drawn - load > 70 )); then
    post "$(live_frame $(( (load + drawn) / 2 )))" 0.6
    [[ $code == 200 ]] && sleep 0.6
  fi
  post "$frame" 1.2
  if [[ $code != 200 ]]; then
    last=""; retry_at=$(( SECONDS + 10 )); continue
  fi
  last=$frame; drawn=$load
  if (( hidden )); then                               # nobody sees it: stop sampling until the button is back
    stop_iostat
    until on_screen; do sleep 3; done
    last=""; start_iostat
  fi
done
