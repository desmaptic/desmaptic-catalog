#!/bin/zsh
# Battery: the MacBook's charge as a neon gauge with a bolt while charging; a Mac without a battery shows a calm plug
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
pspid=""; psfd=""
stop_pslog() {
  [[ -n $pspid ]] && kill $pspid 2>/dev/null
  [[ -n $psfd ]] && exec {psfd}<&-
  pspid=""; psfd=""
}
trap 'stop_pslog; exit 0' TERM INT
zmodload zsh/datetime zsh/system zsh/zselect || { print -u2 -- "battery: zsh modules datetime/system/zselect are missing"; exit 1 }

# One frame of the gauge.
# batt_frame <rest|desk|live> <charge 0…100> <chg|ac|bat> <time left "3:42" or ->
#   desk: a Mac without a battery (the plug); chg: charging, ac: on power and not charging, bat: on battery.
batt_frame() {
  emulate -L zsh
  export LC_ALL=C
  local state=${1:-rest} charge=${2:-0} power=${3:-bat} left=${4:--}
  [[ $state == (rest|desk|live) ]] || state=rest
  [[ $charge == <-> ]] || charge=0
  (( charge > 100 )) && charge=100
  [[ $power == (chg|ac|bat) ]] || power=bat
  [[ $left == <->:<-> ]] || left=-
  local value=$charge time=$left
  [[ $state == live ]] || value="—"
  [[ $left == - ]] && time="0:00"              # never an empty <text>: a hidden one keeps a stand-in

  # Every number and state colour comes from awk as "key value" pairs
  # (zsh float arithmetic would print 0.17999999999999999). Paths come without spaces.
  local -A v
  v=( ${=$(awk -v st=$state -v c=$charge -v pw=$power -v tl=$left '
    function hex(h,   i, n) { n = 0; h = toupper(h); for (i = 1; i <= length(h); i++) n = n * 16 + index("0123456789ABCDEF", substr(h, i, 1)) - 1; return n }
    function mix(a, b, t,   i, o, x, y) {
      o = "#"
      for (i = 2; i <= 6; i += 2) { x = hex(substr(a, i, 2)); y = hex(substr(b, i, 2)); o = o sprintf("%02X", int(x + (y - x) * t + 0.5)) }
      return o
    }
    function spectrum(t) {                     # the arc gradient, empty left → full right: #FF375F → #BF5AF2 (.35) → #5E5CE6 (.7) → #64D2FF
      if (t <= 0)   return "#FF375F"
      if (t < 0.35) return mix("#FF375F", "#BF5AF2", t / 0.35)
      if (t < 0.7)  return mix("#BF5AF2", "#5E5CE6", (t - 0.35) / 0.35)
      if (t < 1)    return mix("#5E5CE6", "#64D2FF", (t - 0.7) / 0.3)
      return "#64D2FF"
    }
    function clamp(x) { return x < 0 ? 0 : (x > 1 ? 1 : x) }
    function kv(k, x) { printf "%s %s\n", k, x }
    function num(k, x) { printf "%s %.2f\n", k, x }
    function P(x, y) { return sprintf("%.2f,%.2f", gx + (x - 100) * gk, gy + (y - 100) * gk) }   # a glyph point, drawn around 100,100
    BEGIN {
      L = 335.10                               # arc length: r 80 · 240° = 80 · 4π/3
      live = (st == "live") ? 1 : 0
      f = live ? c / 100 : 0.5                 # rest and desk: arc end, bead and glow parked at 12 o’clock
      crit = live && c <= 20 && pw != "chg"
      warn = live && !crit && c <= 30 && pw == "bat"
      lv = live ? (crit ? "critical" : (warn ? "warn" : "ok")) : "rest"
      d = L * f; if (d > L - 0.3) d = L - 0.3  # keep the bead’s dash on the path
      num("off", L * (1 - f))                  # lit dash covers 0 … L·f
      num("pos", -d)                           # bead: a 0.1-long dash starting at L·f
      ang = -120 + 240 * f                     # glow: degrees clockwise from 12 o’clock
      # the glow rides the bead as two halves (left of 12 o’clock, right of it): a rotation glides the
      # shortest way, so one circle would cut through the bottom gap on a jump from 10 % to 95 %
      num("angA", ang < 0 ? ang : 0); num("angB", ang > 0 ? ang : 0)
      wA = clamp(0.5 - ang / 4); num("wA", wA); num("wB", 1 - wA)
      x = 100 + 80 * sin(ang * 3.14159265 / 180)
      gc = spectrum((x - 24) / 152)            # glow colour = the arc colour under the bead

      # state:       bloom centre / mid colour and opacity, radius   glow r, core opacity   halo width, opacity   unit colour, opacity   glyph gradient
      if (lv == "rest")     { bC = "#BF5AF2"; bA = 0.12; mC = "#5E5CE6"; bM = 0.04; bR = 82; gR = 28; gA = 0.55; hW = 18; hO = 0.45; uC = "#FFFFFF"; uO = 0.6;  g1 = "#BF5AF2"; g2 = "#64D2FF" }
      if (lv == "ok")       { bC = "#BF5AF2"; bA = 0.20; mC = "#5E5CE6"; bM = 0.07; bR = 86; gR = 28; gA = 0.55; hW = 18; hO = 0.45; uC = "#FFFFFF"; uO = 0.6;  g1 = "#BF5AF2"; g2 = "#64D2FF" }
      if (lv == "warn")     { bC = "#E0479E"; bA = 0.32; mC = "#BF5AF2"; bM = 0.10; bR = 90; gR = 28; gA = 0.70; hW = 20; hO = 0.50; uC = "#FFFFFF"; uO = 0.6;  g1 = "#FF6FA0"; g2 = "#BF5AF2" }
      if (lv == "critical") { bC = "#FF375F"; bA = 0.57; mC = "#BF5AF2"; bM = 0.16; bR = 98; gR = 32; gA = 0.95; hW = 22; hO = 0.60; uC = "#FF7A96"; uO = 0.95; g1 = "#FF375F"; g2 = "#FF8FA8"; gc = "#FF375F" }
      # track: a faint spectrum at rest and on a desk Mac, white 0.18 while live, hot pink when low
      if (lv == "rest")     { split("#FF375F #BF5AF2 #5E5CE6 #64D2FF", tc, " "); split("0.30 0.30 0.30 0.30", to, " ") }
      if (lv == "ok" || lv == "warn") { split("#FFFFFF #FFFFFF #FFFFFF #FFFFFF", tc, " "); split("0.18 0.18 0.18 0.18", to, " ") }
      if (lv == "critical") { split("#FF375F #FF375F #FF375F #FF375F", tc, " "); split("0.30 0.24 0.20 0.20", to, " ") }
      for (i = 1; i <= 4; i++) { kv("tc" i, tc[i]); kv("to" i, to[i]) }

      kv("gc", gc); kv("bC", bC); num("bA", bA); kv("mC", mC); num("bM", bM); num("bR", bR)
      num("gR", gR); num("gA", live * gA); num("gM", live * 0.4 * gA); num("hW", hW); num("hO", live * hO)
      kv("uC", uC); num("uO", live * uO); kv("g1", g1); kv("g2", g2)
      num("live", live); num("litGlowO", live * 0.2); num("coreO", live * 0.45)
      # end ticks step aside when the bead sits on them; the empty one goes when the track itself is pink
      num("tEO", crit ? 0 : (live ? 0.9 * clamp((f - 0.03) / 0.05) : 0.9))
      num("tFO", live ? 0.9 * clamp((0.97 - f) / 0.05) : 0.9)
      # time left (to empty on battery, to full while charging), when macOS has an estimate
      num("tO", (live && tl != "-" && pw != "ac") ? 0.5 : 0)

      # above the number: a bolt while charging, a small plug on power; each with a soft glow behind
      iy = 56
      bolt = live && pw == "chg"; plug = live && pw == "ac"
      kv("ic", crit ? "#FF375F" : "#64D2FF"); num("iA", bolt ? 0.45 : (plug ? 0.25 : 0))
      bk = bolt ? 1 : 0.5; num("boltO", bolt)
      num("tkO", (bolt || plug) ? 0 : 0.3)       # the 50 % tick makes room for the icon
      pts = sprintf("M%.2f,%.2fL%.2f,%.2fL%.2f,%.2fL%.2f,%.2fL%.2f,%.2fL%.2f,%.2fZ", \
        100 + 3.5 * bk, iy - 15 * bk, 100 - 9.5 * bk, iy + 3 * bk, 100 - 1 * bk, iy + 3 * bk, \
        100 - 3.5 * bk, iy + 15 * bk, 100 + 9.5 * bk, iy - 3 * bk, 100 + 1 * bk, iy - 3 * bk)
      kv("bolt", pts)

      # the plug: big in the middle on a Mac without a battery, small above the number on power, hidden otherwise
      if (st == "desk") { gx = 100; gy = 100; gk = 1;   pw2 = 5;   po = 0.75 }
      else              { gx = 100; gy = iy;  gk = 0.4; pw2 = 3.2; po = plug ? 0.9 : 0 }
      r = 22 * gk
      # one path, so the prongs and the cable do not double the glow where they meet the body
      kv("plug", "M" P(78, 78) "L" P(122, 78) "L" P(122, 96) sprintf("A%.2f,%.2f,0,0,1,", r, r) P(100, 118) sprintf("A%.2f,%.2f,0,0,1,", r, r) P(78, 96) "Z" \
        "M" P(90, 78) "L" P(90, 62) "M" P(110, 78) "L" P(110, 62) "M" P(100, 118) "L" P(100, 138))
      num("psw", pw2); num("po", po)
      num("px1", gx - 24 * gk); num("px2", gx + 24 * gk)

      # the big battery is the rest face; when data arrives it sinks to the bottom and fades out
      if (st == "rest") { gx = 100; gy = 100; gk = 1;   bw = 5; bo = 0.75; lo = 1 }
      else              { gx = 100; gy = 172; gk = 0.3; bw = 2; bo = 0;    lo = 0 }
      num("cx", gx - 40 * gk); num("cy", gy - 19 * gk); num("cw", 70 * gk); num("ch", 38 * gk); num("cr", 10 * gk)
      num("nx", gx + 34 * gk); num("ny", gy - 8 * gk);  num("nw", 6 * gk);  num("nh", 16 * gk); num("nr", 3 * gk)
      num("lx", gx - 32 * gk); num("ly", gy - 11 * gk); num("lw", 34 * gk); num("lh", 22 * gk); num("lr", 4 * gk)
      num("bsw", bw); num("bo", bo); num("lo", lo)
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
<linearGradient id=\"battG\" gradientUnits=\"userSpaceOnUse\" x1=\"60\" y1=\"0\" x2=\"140\" y2=\"0\"><stop offset=\"0\" stop-color=\"#BF5AF2\"/><stop offset=\"1\" stop-color=\"#64D2FF\"/></linearGradient>\
<linearGradient id=\"plugG\" gradientUnits=\"userSpaceOnUse\" x1=\"$v[px1]\" y1=\"0\" x2=\"$v[px2]\" y2=\"0\"><stop offset=\"0\" stop-color=\"$v[g1]\"/><stop offset=\"1\" stop-color=\"$v[g2]\"/></linearGradient>\
<radialGradient id=\"bloomG\"><stop offset=\"0\" stop-color=\"$v[bC]\" stop-opacity=\"$v[bA]\"/><stop offset=\"0.55\" stop-color=\"$v[mC]\" stop-opacity=\"$v[bM]\"/><stop offset=\"1\" stop-color=\"$v[mC]\" stop-opacity=\"0\"/></radialGradient>\
<radialGradient id=\"glowG\"><stop offset=\"0\" stop-color=\"$v[gc]\" stop-opacity=\"$v[gA]\"/><stop offset=\"0.4\" stop-color=\"$v[gc]\" stop-opacity=\"$v[gM]\"/><stop offset=\"1\" stop-color=\"$v[gc]\" stop-opacity=\"0\"/></radialGradient>\
<radialGradient id=\"iconG\"><stop offset=\"0\" stop-color=\"$v[ic]\" stop-opacity=\"$v[iA]\"/><stop offset=\"1\" stop-color=\"$v[ic]\" stop-opacity=\"0\"/></radialGradient>\
</defs>\
<circle id=\"bloom\" cx=\"100\" cy=\"100\" r=\"$v[bR]\" fill=\"url(#bloomG)\"/>\
<path id=\"track\" $arc stroke=\"url(#trackG)\" stroke-width=\"6\" stroke-linecap=\"round\"/>\
<path id=\"ticks\" d=\"M 100 38 L 100 33\" fill=\"none\" stroke=\"#FFFFFF\" stroke-opacity=\"$v[tkO]\" stroke-width=\"2.5\" stroke-linecap=\"round\"/>\
<line id=\"tickE\" x1=\"46.31\" y1=\"131\" x2=\"41.98\" y2=\"133.5\" stroke=\"#FF375F\" stroke-opacity=\"$v[tEO]\" stroke-width=\"3\" stroke-linecap=\"round\"/>\
<line id=\"tickF\" x1=\"153.69\" y1=\"131\" x2=\"158.02\" y2=\"133.5\" stroke=\"#64D2FF\" stroke-opacity=\"$v[tFO]\" stroke-width=\"3\" stroke-linecap=\"round\"/>\
<path id=\"litGlow\" $arc stroke=\"url(#spec)\" stroke-opacity=\"$v[litGlowO]\" stroke-width=\"22\" stroke-linecap=\"round\" stroke-dasharray=\"335.1 400\" stroke-dashoffset=\"$v[off]\"/>\
<path id=\"lit\" $arc stroke=\"url(#spec)\" stroke-opacity=\"$v[live]\" stroke-width=\"9\" stroke-linecap=\"round\" stroke-dasharray=\"335.1 400\" stroke-dashoffset=\"$v[off]\"/>\
<path id=\"core\" $arc stroke=\"#FFFFFF\" stroke-opacity=\"$v[coreO]\" stroke-width=\"2.5\" stroke-linecap=\"round\" stroke-dasharray=\"335.1 400\" stroke-dashoffset=\"$v[off]\"/>\
<circle id=\"glowA\" cx=\"100\" cy=\"26\" r=\"$v[gR]\" fill=\"url(#glowG)\" fill-opacity=\"$v[wA]\" transform=\"rotate($v[angA] 100 100)\"/>\
<circle id=\"glowB\" cx=\"100\" cy=\"26\" r=\"$v[gR]\" fill=\"url(#glowG)\" fill-opacity=\"$v[wB]\" transform=\"rotate($v[angB] 100 100)\"/>\
<path id=\"halo\" $arc stroke=\"url(#spec)\" stroke-opacity=\"$v[hO]\" stroke-width=\"$v[hW]\" stroke-linecap=\"round\" stroke-dasharray=\"0.1 400\" stroke-dashoffset=\"$v[pos]\"/>\
<path id=\"bead\" $arc stroke=\"#FFFFFF\" stroke-opacity=\"$v[live]\" stroke-width=\"12\" stroke-linecap=\"round\" stroke-dasharray=\"0.1 400\" stroke-dashoffset=\"$v[pos]\"/>\
<circle id=\"iconGlow\" cx=\"100\" cy=\"56\" r=\"26\" fill=\"url(#iconG)\"/>\
<path id=\"bolt\" d=\"$v[bolt]\" fill=\"#FFFFFF\" fill-opacity=\"$v[boltO]\" stroke=\"$v[ic]\" stroke-opacity=\"$v[boltO]\" stroke-width=\"3\" stroke-linejoin=\"round\"/>\
<path id=\"plug\" d=\"$v[plug]\" fill=\"none\" stroke=\"url(#plugG)\" stroke-opacity=\"$v[po]\" stroke-width=\"$v[psw]\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>\
<rect id=\"battery\" x=\"$v[cx]\" y=\"$v[cy]\" width=\"$v[cw]\" height=\"$v[ch]\" rx=\"$v[cr]\" fill=\"none\" stroke=\"url(#battG)\" stroke-opacity=\"$v[bo]\" stroke-width=\"$v[bsw]\"/>\
<rect id=\"nub\" x=\"$v[nx]\" y=\"$v[ny]\" width=\"$v[nw]\" height=\"$v[nh]\" rx=\"$v[nr]\" fill=\"url(#battG)\" fill-opacity=\"$v[bo]\"/>\
<rect id=\"level\" x=\"$v[lx]\" y=\"$v[ly]\" width=\"$v[lw]\" height=\"$v[lh]\" rx=\"$v[lr]\" fill=\"#64D2FF\" fill-opacity=\"$v[lo]\"/>\
<text id=\"value\" x=\"100\" y=\"97\" font-size=\"60\" font-weight=\"600\" text-anchor=\"middle\" dominant-baseline=\"middle\" fill=\"#FFFFFF\" fill-opacity=\"$v[live]\">$value</text>\
<text id=\"unit\" x=\"100\" y=\"138\" font-size=\"26\" font-weight=\"600\" text-anchor=\"middle\" dominant-baseline=\"middle\" fill=\"$v[uC]\" fill-opacity=\"$v[uO]\">%</text>\
<text id=\"left\" x=\"100\" y=\"174\" font-size=\"26\" font-weight=\"600\" text-anchor=\"middle\" dominant-baseline=\"middle\" fill=\"#FFFFFF\" fill-opacity=\"$v[tO]\">$time</text>\
</svg>"
}

cell="{{CELL_ID}}"
api="http://127.0.0.1:9848/api"

# Reads `pmset -g batt` into has (1 when the Mac has a battery), charge, power and left. The line it wants:
#    -InternalBattery-0 (id=1234567)	85%; discharging; 3:42 remaining present: true
# Other states: "charging; 1:05 remaining", "finishing charge", "charged; 0:00 remaining", "AC attached; not charging",
# "(no estimate)". Batteries of a UPS or of Bluetooth devices are not the Mac's and are skipped.
read_batt() {
  local out line st
  has=0 charge=0 power=bat left=-
  out=$(pmset -g batt 2>/dev/null)
  for line in ${(f)out}; do
    [[ $line == *InternalBattery* && $line != *'present: false'* ]] || continue
    [[ $line =~ '([0-9]+)%; *([^;]*)' ]] || continue
    has=1; charge=$match[1]; st=$match[2]
    (( charge > 100 )) && charge=100
    case $st in
      charging|'finishing charge') power=chg ;;
      charged|'AC attached') power=ac ;;
      discharging) power=bat ;;
      *) [[ $out == *"'AC Power'"* ]] && power=ac ;;
    esac
    if [[ $line =~ ' ([0-9]{1,2}):([0-5][0-9]) remaining' ]] && (( match[1] * 60 + match[2] > 0 )); then
      left="$match[1]:$match[2]"
    fi
    break
  done
  return 0
}

# post <frame>: sets post_code and post_seen (0 when the button is not on the phone's screen).
# The token goes in through a descriptor, not the command line, where any user of the Mac could read it.
post() {
  local json=$1 answer
  json=${json//\\/\\\\}; json=${json//\"/\\\"}; json=${json//$'\n'/}
  answer=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/update-button" -H @/dev/fd/3 \
    -H "Content-Type: application/json" --data-binary @- \
    3<<< "Authorization: Bearer $DESMAPTIC_TOKEN" \
    <<< "{\"cellId\":\"$cell\",\"svg\":{\"source\":\"$json\",\"duration\":1.2}}")
  post_code=${answer##*$'\n'}
  post_seen=1
  [[ ${answer// /} == *'"visible":false'* ]] && post_seen=0
  [[ $post_code == 200 ]] || print -u2 -- "battery: update-button answered ${post_code:-nothing}: ${${answer%$'\n'*}[1,300]}"
  return 0
}

# 0 when the button is on the phone's screen, or when nobody can tell (an older app, the agent busy).
on_screen() {
  local answer
  answer=$(curl -q -s -m 5 "$api/view" -H @/dev/fd/3 3<<< "Authorization: Bearer $DESMAPTIC_TOKEN") || return 0
  [[ $answer == *'"visibleCellIds"'* ]] || return 0
  [[ ${(L)answer} == *${(L)cell}* ]]
}

last=""          # the frame on the phone
retry_at=0       # after a failed post: not before this (epoch seconds)
seen=1           # the button was on screen at the last post

# Draws the reading when it changed.
show() {
  local frame
  if (( has )); then frame=$(batt_frame live $charge $power $left); else frame=$(batt_frame desk 0 ac -); fi
  [[ $frame == "$last" ]] && return 0
  (( EPOCHSECONDS < retry_at )) && return 0
  post "$frame"
  if [[ $post_code == 200 ]]; then
    last=$frame; seen=$post_seen; retry_at=0
  else
    retry_at=$(( EPOCHSECONDS + 10 ))
  fi
}

# `pmset -g pslog` prints a block on every power change (plug, unplug, a new percent or estimate) and on wake.
# It only wakes the loop; the values come from `pmset -g batt`, which prints the same line in full.
started=0; quick=0
start_pslog() {
  coproc pmset -g pslog 2>/dev/null
  pspid=$!
  exec {psfd}<&p
  started=$EPOCHSECONDS
}

read_batt
while true; do
  if (( ! has )); then                         # no battery (a desktop Mac): the plug, and a look every 10 minutes
    stop_pslog
    show
    if (( retry_at )); then zselect -t 1000; else zselect -t 60000; fi
    read_batt
    continue
  fi

  show
  if (( ! seen )); then                        # nobody sees it: stop reading until the button is back
    stop_pslog
    until on_screen; do zselect -t 300; done
    seen=1; last=""
    read_batt
    continue
  fi

  # Wait for pslog's next block, a pending retry, or 60 s (a new estimate pslog might not announce).
  nap=60
  (( retry_at )) && nap=$(( retry_at - EPOCHSECONDS ))
  (( nap < 1 )) && nap=1
  if (( quick >= 3 )); then                    # pslog keeps dying right after it starts: read every 30 s instead
    (( nap > 30 )) && nap=30
    zselect -t $(( nap * 100 ))
  else
    [[ -n $pspid ]] || start_pslog
    buf=""
    sysread -t $nap -i $psfd buf
    case $? in
      0) for i in {1..20}; do sysread -t 0.5 -i $psfd buf || break; done ;;   # let the rest of the block arrive
      4) ;;                                    # nothing new in $nap seconds
      *) if (( EPOCHSECONDS - started < 30 )); then (( quick++ )); else quick=0; fi
         print -u2 -- "battery: pmset -g pslog stopped; starting it again"
         (( quick >= 3 )) && print -u2 -- "battery: pmset -g pslog keeps stopping; reading pmset -g batt every 30 s instead"
         stop_pslog
         zselect -t 500 ;;
    esac
  fi
  read_batt
done
