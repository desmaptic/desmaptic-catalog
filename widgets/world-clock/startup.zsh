#!/bin/zsh
# World Clock: the time in another city on a 24-hour neon arch, with sun or moon and the offset from this Mac; tap for the next city
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT

# One frame of the face. Arguments: minute of the city's day (0…1439, or "rest"), the time "14:05",
# the city code, its offset from this Mac in minutes (or "none"), sun up there (1/0), sleeping hours there (1/0).
clock_frame() {
  emulate -L zsh
  export LC_ALL=C
  local minute=${1:-rest} hm=${2:-—} code=${3:-—} delta=${4:-none} sun=${5:-1} late=${6:-0}
  [[ $minute == <-> ]] && (( minute < 1440 )) || minute=rest
  [[ $delta == (|-)<-> ]] || delta=none
  [[ $sun == (0|1) ]] || sun=1
  [[ $late == (0|1) ]] || late=0
  [[ -z $hm ]] && hm=—
  [[ -z $code ]] && code=—
  hm=${hm//&/&amp;}; hm=${hm//</&lt;}
  code=${code//&/&amp;}; code=${code//</&lt;}

  # Every number, colour and the offset text come from awk as "key value" pairs
  # (zsh float arithmetic would print 0.17999999999999999).
  local -A v
  v=( ${=$(awk -v m=$minute -v sun=$sun -v late=$late -v dm=$delta '
    function hex(h,   i, n) { n = 0; h = toupper(h); for (i = 1; i <= length(h); i++) n = n * 16 + index("0123456789ABCDEF", substr(h, i, 1)) - 1; return n }
    function mix(a, b, t,   i, o, x, y) {
      o = "#"
      for (i = 2; i <= 6; i += 2) { x = hex(substr(a, i, 2)); y = hex(substr(b, i, 2)); o = o sprintf("%02X", int(x + (y - x) * t + 0.5)) }
      return o
    }
    function spectrum(t) {                     # the arch gradient: #FF375F → #BF5AF2 (.35) → #5E5CE6 (.7) → #64D2FF
      if (t <= 0)   return "#FF375F"
      if (t < 0.35) return mix("#FF375F", "#BF5AF2", t / 0.35)
      if (t < 0.7)  return mix("#BF5AF2", "#5E5CE6", (t - 0.35) / 0.35)
      if (t < 1)    return mix("#5E5CE6", "#64D2FF", (t - 0.7) / 0.3)
      return "#64D2FF"
    }
    function kv(k, x) { printf "%s %s\n", k, x }
    function num(k, x) { printf "%s %.2f\n", k, x }
    BEGIN {
      PI = 3.14159265
      live = (m == "rest") ? 0 : 1
      st = !live ? "rest" : (late ? "late" : (sun ? "day" : "dusk"))

      # The arch is the city day: midnight at both ends, noon at the crown, the bead is now.
      # At rest it is the family gauge round the centre (r 80); live it shrinks and rises above the time.
      if (live) { ay = 94; ar = 64 } else { ay = 100; ar = 80 }
      num("ax1", 100 - ar * 0.8660254); num("ax2", 100 + ar * 0.8660254); num("aye", ay + ar / 2); kv("ar", ar)
      L = ar * 4 * PI / 3                      # arch length: r · 240°
      f = live ? m / 1440 : 0.5                # share of the city day gone; rest parks the bead at noon
      d = L * f; if (d > L - 0.3) d = L - 0.3; if (d < 0.1) d = 0.1
      num("L", L); num("off", L * (1 - f)); num("pos", -d)
      ang = -120 + 240 * f                     # glow: degrees clockwise from the crown
      num("ang", ang); kv("ay", ay)
      num("gy1", ay + ar / 2); num("gy2", ay - ar)           # sky gradient: pink at the ends (midnight), cyan at the crown (noon)
      num("glowY", ay - ar + 6)
      num("tk1", ay - ar + (live ? 8 : 13)); num("tk2", ay - ar + (live ? 13 : 18))
      y = ay - ar * cos(ang * PI / 180)
      gc = spectrum((ay + ar / 2 - y) / (1.5 * ar))         # glow colour = the arch colour under the bead

      # state:   bloom centre / mid colour and opacity, radius
      if (st == "rest") { bC = "#BF5AF2"; bA = 0.12; mC = "#5E5CE6"; bM = 0.04; bR = 82 }
      if (st == "day")  { bC = "#5E5CE6"; bA = 0.20; mC = "#64D2FF"; bM = 0.06; bR = 86 }
      if (st == "dusk") { bC = "#BF5AF2"; bA = 0.22; mC = "#5E5CE6"; bM = 0.07; bR = 88 }
      if (st == "late") { bC = "#FF375F"; bA = 0.45; mC = "#BF5AF2"; bM = 0.14; bR = 96; gc = "#FF375F" }
      kv("bC", bC); num("bA", bA); kv("mC", mC); num("bM", bM); kv("bR", bR); kv("gc", gc)
      # track: a faint sky on the rest face, thin white while live
      if (live) split("#FFFFFF #FFFFFF #FFFFFF #FFFFFF", tc, " "); else split("#FF375F #BF5AF2 #5E5CE6 #64D2FF", tc, " ")
      for (i = 1; i <= 4; i++) kv("tc" i, tc[i])
      num("tO", live ? 0.18 : 0.30)
      num("live", live); num("litGlowO", live * 0.2); num("coreO", live * 0.45); num("gA", live * 0.55); num("gM", live * 0.22); num("hO", live * 0.45)
      # the city code turns hot pink in its sleeping hours
      kv("uC", late ? "#FF7A96" : "#FFFFFF"); num("uO", live * (late ? 0.95 : 0.75)); num("oO", live * 0.6)

      # offset text "+8", "−5", "+5½", "±0" and its width at 26 (digits and signs 16.4, fractions 20.6)
      if (dm == "none") { off = "\342\200\224"; w = 16.4 }
      else {
        a = (dm < 0) ? -dm : dm; hh = int(a / 60); mm = a % 60
        off = (dm > 0) ? "+" : ((dm < 0) ? "\342\210\222" : "\302\261")
        off = off hh; w = 16.4 * (1 + length(hh ""))
        if (mm == 15)      { off = off "\302\274"; w += 20.6 }
        else if (mm == 30) { off = off "\302\275"; w += 20.6 }
        else if (mm == 45) { off = off "\302\276"; w += 20.6 }
        else if (mm != 0)  { off = off ":" sprintf("%02d", mm); w += 40.3 }
      }
      kv("offset", off)

      # orb: a sun (disc + rays) or a moon (crescent) left of the offset; the pair is centred
      r = sun ? 9 : 13
      ow = sun ? 37 : 19                       # drawn width of the orb
      gap = 7; x0 = 100 - (ow + gap + w) / 2
      vx = x0 + ow / 2; vy = 70                # where the orb is seen
      num("vx", vx); kv("vy", vy); num("tx", x0 + ow + gap)
      # the moon is the right part of its circle turned by -28°: shift the circle so the crescent sits at vx, vy
      cx = sun ? vx : vx - 0.25 * r; cy = sun ? vy : vy + 0.08 * r
      num("cx", cx); num("cy", cy); num("top", cy - r); num("bot", cy + r)
      num("r", r); num("irx", sun ? r : r * 0.42); kv("sw", sun ? 1 : 0)
      num("orbO", live)
      # 8 rays from r+4.5 to r+9.5 for the sun; folded into the disc for the moon
      r1 = sun ? r + 4.5 : r * 0.4; r2 = sun ? r + 9.5 : r * 0.4
      for (i = 0; i < 8; i++) {
        a = i * PI / 4
        num("rx1" i, cx + r1 * sin(a)); num("ry1" i, cy - r1 * cos(a))
        num("rx2" i, cx + r2 * sin(a)); num("ry2" i, cy - r2 * cos(a))
      }
      num("rayO", live * sun)
      oc = (st == "late") ? "#FF375F" : (sun ? "#64D2FF" : "#BF5AF2")
      kv("oc", oc); num("oG", live * (sun ? 0.55 : 0.5)); kv("oR", sun ? 30 : 26)

      # the big globe is the rest face; when data arrives it sinks behind the time and fades out
      if (live) { gx = 100; gy = 150; gr = 14; go = 0 } else { gx = 100; gy = 100; gr = 36; go = 0.8 }
      kv("gx", gx); kv("gy", gy); num("gr", gr); num("gerx", gr * 0.42); num("go", go)
      num("glx1", gx - gr * 0.88); num("glx2", gx + gr * 0.88); num("gty", gy - gr * 0.88); num("gby", gy + gr * 0.88)
      num("lax1", gx - gr * 0.72); num("lax2", gx + gr * 0.72); num("lay1", gy - gr * 0.5); num("lay2", gy + gr * 0.5)
    }')} )

  local arc="d=\"M $v[ax1] $v[aye] A $v[ar] $v[ar] 0 1 1 $v[ax2] $v[aye]\" fill=\"none\""
  local dash="stroke-dasharray=\"$v[L] $v[L]\" stroke-dashoffset=\"$v[off]\""
  local i rays=""
  for i in {0..7}; do
    rays+="<line id=\"ray$i\" x1=\"$v[rx1$i]\" y1=\"$v[ry1$i]\" x2=\"$v[rx2$i]\" y2=\"$v[ry2$i]\" stroke=\"#FFFFFF\" stroke-opacity=\"$v[rayO]\" stroke-width=\"3\" stroke-linecap=\"round\"/>"
  done
  local globe="stroke=\"url(#globeG)\" stroke-opacity=\"$v[go]\" stroke-linecap=\"round\""

  printf '%s\n' "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 200 200\">\
<defs>\
<linearGradient id=\"sky\" gradientUnits=\"userSpaceOnUse\" x1=\"0\" y1=\"$v[gy1]\" x2=\"0\" y2=\"$v[gy2]\">\
<stop offset=\"0\" stop-color=\"#FF375F\"/><stop offset=\"0.35\" stop-color=\"#BF5AF2\"/><stop offset=\"0.7\" stop-color=\"#5E5CE6\"/><stop offset=\"1\" stop-color=\"#64D2FF\"/>\
</linearGradient>\
<linearGradient id=\"trackG\" gradientUnits=\"userSpaceOnUse\" x1=\"0\" y1=\"$v[gy1]\" x2=\"0\" y2=\"$v[gy2]\">\
<stop offset=\"0\" stop-color=\"$v[tc1]\" stop-opacity=\"$v[tO]\"/><stop offset=\"0.35\" stop-color=\"$v[tc2]\" stop-opacity=\"$v[tO]\"/><stop offset=\"0.7\" stop-color=\"$v[tc3]\" stop-opacity=\"$v[tO]\"/><stop offset=\"1\" stop-color=\"$v[tc4]\" stop-opacity=\"$v[tO]\"/>\
</linearGradient>\
<linearGradient id=\"globeG\" gradientUnits=\"userSpaceOnUse\" x1=\"60\" y1=\"0\" x2=\"140\" y2=\"0\"><stop offset=\"0\" stop-color=\"#BF5AF2\"/><stop offset=\"1\" stop-color=\"#64D2FF\"/></linearGradient>\
<radialGradient id=\"bloomG\"><stop offset=\"0\" stop-color=\"$v[bC]\" stop-opacity=\"$v[bA]\"/><stop offset=\"0.55\" stop-color=\"$v[mC]\" stop-opacity=\"$v[bM]\"/><stop offset=\"1\" stop-color=\"$v[mC]\" stop-opacity=\"0\"/></radialGradient>\
<radialGradient id=\"glowG\"><stop offset=\"0\" stop-color=\"$v[gc]\" stop-opacity=\"$v[gA]\"/><stop offset=\"0.4\" stop-color=\"$v[gc]\" stop-opacity=\"$v[gM]\"/><stop offset=\"1\" stop-color=\"$v[gc]\" stop-opacity=\"0\"/></radialGradient>\
<radialGradient id=\"orbG\"><stop offset=\"0\" stop-color=\"$v[oc]\" stop-opacity=\"$v[oG]\"/><stop offset=\"0.45\" stop-color=\"$v[oc]\" stop-opacity=\"0.15\"/><stop offset=\"1\" stop-color=\"$v[oc]\" stop-opacity=\"0\"/></radialGradient>\
</defs>\
<circle id=\"bloom\" cx=\"100\" cy=\"100\" r=\"$v[bR]\" fill=\"url(#bloomG)\"/>\
<path id=\"track\" $arc stroke=\"url(#trackG)\" stroke-width=\"6\" stroke-linecap=\"round\"/>\
<path id=\"tick\" d=\"M 100 $v[tk2] L 100 $v[tk1]\" fill=\"none\" stroke=\"#FFFFFF\" stroke-opacity=\"0.3\" stroke-width=\"2.5\" stroke-linecap=\"round\"/>\
<path id=\"litGlow\" $arc stroke=\"url(#sky)\" stroke-opacity=\"$v[litGlowO]\" stroke-width=\"22\" stroke-linecap=\"round\" $dash/>\
<path id=\"lit\" $arc stroke=\"url(#sky)\" stroke-opacity=\"$v[live]\" stroke-width=\"9\" stroke-linecap=\"round\" $dash/>\
<path id=\"core\" $arc stroke=\"#FFFFFF\" stroke-opacity=\"$v[coreO]\" stroke-width=\"2.5\" stroke-linecap=\"round\" $dash/>\
<circle id=\"glow\" cx=\"100\" cy=\"$v[glowY]\" r=\"26\" fill=\"url(#glowG)\" transform=\"rotate($v[ang] 100 $v[ay])\"/>\
<path id=\"halo\" $arc stroke=\"url(#sky)\" stroke-opacity=\"$v[hO]\" stroke-width=\"18\" stroke-linecap=\"round\" stroke-dasharray=\"0.1 400\" stroke-dashoffset=\"$v[pos]\"/>\
<path id=\"bead\" $arc stroke=\"#FFFFFF\" stroke-opacity=\"$v[live]\" stroke-width=\"12\" stroke-linecap=\"round\" stroke-dasharray=\"0.1 400\" stroke-dashoffset=\"$v[pos]\"/>\
<circle id=\"orbGlow\" cx=\"$v[vx]\" cy=\"$v[vy]\" r=\"$v[oR]\" fill=\"url(#orbG)\" fill-opacity=\"$v[orbO]\"/>\
$rays\
<path id=\"orb\" d=\"M $v[cx] $v[top] A $v[r] $v[r] 0 0 1 $v[cx] $v[bot] A $v[irx] $v[r] 0 0 $v[sw] $v[cx] $v[top] Z\" fill=\"#FFFFFF\" fill-opacity=\"$v[orbO]\" transform=\"rotate(-28 $v[cx] $v[cy])\"/>\
<text id=\"offset\" x=\"$v[tx]\" y=\"70\" font-size=\"26\" font-weight=\"600\" text-anchor=\"start\" dominant-baseline=\"middle\" fill=\"#FFFFFF\" fill-opacity=\"$v[oO]\">$v[offset]</text>\
<text id=\"code\" x=\"100\" y=\"111\" font-size=\"28\" font-weight=\"600\" text-anchor=\"middle\" dominant-baseline=\"middle\" fill=\"$v[uC]\" fill-opacity=\"$v[uO]\">$code</text>\
<text id=\"time\" x=\"100\" y=\"157\" font-size=\"58\" font-weight=\"600\" text-anchor=\"middle\" dominant-baseline=\"middle\" fill=\"#FFFFFF\" fill-opacity=\"$v[live]\">$hm</text>\
<circle id=\"globe\" cx=\"$v[gx]\" cy=\"$v[gy]\" r=\"$v[gr]\" fill=\"none\" $globe stroke-width=\"5\"/>\
<ellipse id=\"meridian\" cx=\"$v[gx]\" cy=\"$v[gy]\" rx=\"$v[gerx]\" ry=\"$v[gr]\" fill=\"none\" $globe stroke-width=\"4\"/>\
<line id=\"axis\" x1=\"$v[gx]\" y1=\"$v[gty]\" x2=\"$v[gx]\" y2=\"$v[gby]\" $globe stroke-width=\"4\"/>\
<line id=\"equator\" x1=\"$v[glx1]\" y1=\"$v[gy]\" x2=\"$v[glx2]\" y2=\"$v[gy]\" $globe stroke-width=\"4\"/>\
<line id=\"north\" x1=\"$v[lax1]\" y1=\"$v[lay1]\" x2=\"$v[lax2]\" y2=\"$v[lay1]\" $globe stroke-width=\"4\"/>\
<line id=\"south\" x1=\"$v[lax1]\" y1=\"$v[lay2]\" x2=\"$v[lax2]\" y2=\"$v[lay2]\" $globe stroke-width=\"4\"/>\
</svg>"
}

# The cities a tap cycles through (tap.zsh keeps the same order): code, time zone, latitude, longitude.
cities=(
  LON Europe/London        51.51    -0.13
  NYC America/New_York     40.71   -74.01
  SFO America/Los_Angeles  37.77  -122.42
  TYO Asia/Tokyo           35.68   139.69
  DXB Asia/Dubai           25.20    55.27
  SIN Asia/Singapore        1.35   103.82
  SYD Australia/Sydney    -33.87   151.21
  PAR Europe/Paris         48.86     2.35
  BER Europe/Berlin        52.52    13.40
  MOW Europe/Moscow        55.76    37.62
  IST Europe/Istanbul      41.01    28.98
  HKG Asia/Hong_Kong       22.32   114.17
)

# "<minute of day> <HH:MM> <offset from this Mac in minutes> <sun up 1/0> <sleeping hours 1/0>" for a city.
city_now() {
  local tz=$1 lat=$2 lon=$3 now=$4 there here
  there=$(TZ=$tz date -r $now '+%H %M %z' 2>/dev/null) || return 1
  here=$(date -r $now '+%z' 2>/dev/null) || return 1
  awk -v now=$now -v lat=$lat -v lon=$lon -v there="$there" -v here="$here" '
    function mins(z) { return (substr(z, 1, 1) == "-" ? -1 : 1) * (substr(z, 2, 2) * 60 + substr(z, 4, 2)) }
    BEGIN {
      split(there, t, " ")
      if (t[1] !~ /^[0-9][0-9]$/ || t[2] !~ /^[0-9][0-9]$/ || t[3] !~ /^[-+][0-9][0-9][0-9][0-9]$/ || here !~ /^[-+][0-9][0-9][0-9][0-9]$/) exit 1
      h = t[1] + 0; mi = t[2] + 0
      # the sun over the city (low-precision almanac): up while its centre is above -0.833°
      R = 3.14159265358979 / 180
      n = now / 86400 - 10957.5                # days since 2000-01-01 12:00 UTC
      g = (357.528 + 0.9856003 * n) * R
      lam = (280.460 + 0.9856474 * n + 1.915 * sin(g) + 0.020 * sin(2 * g)) * R
      eps = (23.439 - 0.0000004 * n) * R
      ra = atan2(cos(eps) * sin(lam), cos(lam))
      sd = sin(eps) * sin(lam); cd = sqrt(1 - sd * sd)
      H = ((280.46061837 + 360.98564736629 * n + lon) % 360) * R - ra
      alt = sin(lat * R) * sd + cos(lat * R) * cd * cos(H)
      up = (alt > -0.01454) ? 1 : 0
      late = (h >= 22 || h < 7) ? 1 : 0        # sleeping hours there
      printf "%d %02d:%02d %d %d %d\n", h * 60 + mi, h, mi, mins(t[3]) - mins(here), up, late
    }'
}

cell="{{CELL_ID}}"
api="http://127.0.0.1:9848/api"
store="${DESMAPTIC_STORAGE:-$HOME/Library/Application Support/Desmaptic/ScriptStorage}/gallery/$cell"
zmodload zsh/datetime
# nap <hundredths of a second>, without a process per nap
if zmodload zsh/zselect 2>/dev/null; then nap() { zselect -t $1 }; else nap() { sleep $(( $1 / 100.0 )) }; fi

# Sets `city` to the chosen code (tap.zsh writes it) and `i` to its row in `cities`; NYC until the first tap.
choose() {
  local c=""
  { read -r c < "$store/city" } 2>/dev/null
  i=${cities[(Ie)$c]}
  if [[ -n $c ]] && (( i % 4 == 1 )); then city=$c; else city=NYC; i=${cities[(Ie)NYC]}; fi
}

# post <frame> <transition fields>: sets `code` to the HTTP status, and `hidden` when nobody sees the button.
post() {
  local json=$1 reply body
  json=${json//\\/\\\\}; json=${json//\"/\\\"}; json=${json//$'\n'/}
  reply=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/update-button" \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}' -H "Content-Type: application/json" \
    -d "{\"cellId\":\"$cell\",\"svg\":{\"source\":\"$json\",$2}}")
  code=${reply##*$'\n'}
  body=${${reply%$'\n'*}//[[:space:]]/}
  if [[ $code == 200 ]]; then
    [[ $body == *'"visible":false'* ]] && hidden=1
  else
    print -r -- "update-button $code${body:+: $body}" >&2
  fi
}

# Is the button on the phone's screen? Unknown (an older app, the agent busy) counts as yes.
on_screen() {
  local reply ids
  reply=$(curl -q -s -m 5 "$api/view" --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}') || return 0
  reply=${reply//[[:space:]]/}
  [[ $reply == *'"visibleCellIds":['* ]] || return 0
  ids=${${reply#*\"visibleCellIds\":\[}%%\]*}
  [[ ${(L)ids} == *${(L)cell}* ]]
}

last="" lastMinute="" hidden=0 code=""
while true; do
  choose
  if (( ! hidden )); then
    reading=( $(city_now $cities[i+1] $cities[i+2] $cities[i+3] $EPOCHSECONDS) )
    if (( $#reading == 5 )); then
      minute=$reading[1]
      frame=$(clock_frame $reading[1] $reading[2] $city $reading[3] $reading[4] $reading[5])
    else
      print -r -- "cannot read the time in $city" >&2
      minute=""
      frame=$(clock_frame rest)
    fi
    if [[ $frame != $last ]]; then
      # The glow turns by the shortest arc: a jump over more than 3/4 of the day (midnight, some taps)
      # goes through the crown in two halves, or the glow would cut under the time.
      if [[ $minute == <-> && $lastMinute == <-> ]] && (( minute - lastMinute > 1080 || lastMinute - minute > 1080 )); then
        post "$(clock_frame $(( (minute + lastMinute) / 2 )) $reading[2] $city $reading[3] $reading[4] $reading[5])" '"duration":0.6,"easing":"linear"'
        nap 60
        post "$frame" '"duration":0.6,"easing":"linear"'
      else
        post "$frame" '"duration":1.2'
      fi
      if [[ $code == 200 ]]; then
        last=$frame lastMinute=$minute
      else
        sleep 10
        continue
      fi
    fi
  fi

  shown=$city
  if (( hidden )); then
    # Nobody sees the button: no drawing, a look at the screen every 3 s — or at once after a tap.
    for n in 1 2 3 4 5 6; do
      nap 50
      choose
      [[ $city != $shown ]] && { hidden=0; break }
    done
    (( hidden )) && on_screen && hidden=0
  else
    # Sleep to the next minute, watching for a tap.
    next=$(( (EPOCHSECONDS / 60 + 1) * 60 ))
    while (( EPOCHSECONDS < next )); do
      nap 50
      choose
      [[ $city != $shown ]] && break
    done
  fi
done
