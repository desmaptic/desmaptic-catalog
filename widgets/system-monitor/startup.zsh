#!/bin/zsh
# System Monitor: CPU gauge, memory pressure and disk bars, and the Mac's network traffic right now, down and up,
# with 3 minutes of history on a fixed log scale; every 4 s while on screen
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
zmodload zsh/datetime                          # EPOCHREALTIME, EPOCHSECONDS
cpu_pid=""
trap '[[ -n $cpu_pid ]] && kill $cpu_pid 2>/dev/null; exit 0' TERM INT

# ---- frame ----
# One template for every frame: the rest face, every value, every state. Only numbers, colours and text change,
# so the phone glides between frames. Attribute quotes are written as ` and turned into " at the end.
read -r -d '' SYSMON_AWK <<'AWK'
function hex(h,   i, n) { n = 0; h = toupper(h); for (i = 1; i <= length(h); i++) n = n * 16 + index("0123456789ABCDEF", substr(h, i, 1)) - 1; return n }
function mix(a, b, t,   i, o, x, y) {
  o = "#"
  for (i = 2; i <= 6; i += 2) { x = hex(substr(a, i, 2)); y = hex(substr(b, i, 2)); o = o sprintf("%02X", int(x + (y - x) * t + 0.5)) }
  return o
}
function heat(t) {                             # the lit gradient, calm → hot: #64D2FF → #5E5CE6 (.3) → #BF5AF2 (.65) → #FF375F
  if (t <= 0)    return "#64D2FF"
  if (t < 0.3)   return mix("#64D2FF", "#5E5CE6", t / 0.3)
  if (t < 0.65)  return mix("#5E5CE6", "#BF5AF2", (t - 0.3) / 0.35)
  if (t < 1)     return mix("#BF5AF2", "#FF375F", (t - 0.65) / 0.35)
  return "#FF375F"
}
function f(x) { return sprintf("%.2f", x) }
function clamp(x, lo, hi) { return x < lo ? lo : (x > hi ? hi : x) }
function tip(t, level) { return level >= 2 ? "#FF375F" : (level == 1 ? "#E24FC9" : heat(t)) }
function glowGrad(id, c, a) {
  return "<radialGradient id=`" id "`><stop offset=`0` stop-color=`" c "` stop-opacity=`" f(a) "`/>" \
    "<stop offset=`0.4` stop-color=`" c "` stop-opacity=`" f(0.4 * a) "`/><stop offset=`1` stop-color=`" c "` stop-opacity=`0`/></radialGradient>"
}
function pct(v) { return v >= 0 ? sprintf("%d%%", v + 0.5) : "—" }
# the traffic chart's fixed log scale: 0.1 Mbps (and less) on the base line y 184, a decade every 10.5, 1000 Mbps at the top y 142
function ly(v,   t) { t = v > 0.1 ? log(v / 0.1) / log(10) / 4 : 0; return 184 - 42 * (t > 1 ? 1 : t) }
function valueText(id, x, y, anchor, size, v, level, o) {
  return "<text id=`" id "` x=`" x "` y=`" y "` font-size=`" size "` font-weight=`600` text-anchor=`" anchor \
    "` dominant-baseline=`middle` fill=`" (level >= 2 ? "#FF7A96" : "#FFFFFF") "` fill-opacity=`" f(o) "`>" pct(v) "</text>"
}
# a neon bar: white track, gradient glow + lit + white core, a heat glow, halo and bead at the tip
function bar(id, y, v, level,   s, x2, o, out) {
  s = v >= 0 ? clamp(v / 100, 0.01, 1) : 0.01
  x2 = f(112 + 74 * s)
  o = live * (v >= 0)
  out = "<line id=`" id "Track` x1=`112` y1=`" y "` x2=`186` y2=`" y "` stroke=`" (level >= 2 ? "#FF375F" : "#FFFFFF") \
    "` stroke-opacity=`" f(live * (level >= 2 ? 0.3 : 0.18)) "` stroke-width=`3` stroke-linecap=`round`/>"
  out = out "<line id=`" id "Glow` x1=`112` y1=`" y "` x2=`" x2 "` y2=`" y "` stroke=`url(#barG)` stroke-opacity=`" f(0.2 * o) "` stroke-width=`11` stroke-linecap=`round`/>"
  out = out "<line id=`" id "Lit` x1=`112` y1=`" y "` x2=`" x2 "` y2=`" y "` stroke=`url(#barG)` stroke-opacity=`" f(o) "` stroke-width=`4.5` stroke-linecap=`round`/>"
  out = out "<line id=`" id "Core` x1=`112` y1=`" y "` x2=`" x2 "` y2=`" y "` stroke=`#FFFFFF` stroke-opacity=`" f(0.45 * o) "` stroke-width=`1.3` stroke-linecap=`round`/>"
  out = out "<circle id=`" id "Heat` cx=`" x2 "` cy=`" y "` r=`" (level ? 15 : 12) "` fill=`url(#" id "HeatG)`/>"
  out = out "<circle id=`" id "Halo` cx=`" x2 "` cy=`" y "` r=`4.5` fill=`url(#barG)` fill-opacity=`" f(0.45 * o) "`/>"
  out = out "<circle id=`" id "Bead` cx=`" x2 "` cy=`" y "` r=`3` fill=`#FFFFFF` fill-opacity=`" f(o) "`/>"
  return out
}
BEGIN {
  pi = 3.14159265
  live = (st == "live") ? 1 : 0
  if (!live) { cpu = 0; mem = 0; dsk = 0; cl = 0; ml = 0; dl = 0 }
  cpu += 0; mem += 0; dsk += 0; cl += 0; ml += 0; dl += 0
  go = live ? 0.6 : 0                          # glyphs and units: white 0.6, like every unit of the family

  # bloom: a soft violet glow; it heats up and moves onto the worst value in attention
  bX = 100; bY = 100; bR = 92; bC = "#BF5AF2"; bA = 0.12; mC = "#5E5CE6"; bM = 0.04
  if (live) {
    bR = 96; bA = 0.14; bM = 0.05
    top = 0
    if (cl > top) { top = cl; bX = 52;  bY = 58 }
    if (ml > top) { top = ml; bX = 150; bY = 40 }
    if (dl > top) { top = dl; bX = 150; bY = 80 }
    if (top == 1) { bR = 80; bC = "#E0479E"; bA = 0.30; mC = "#BF5AF2"; bM = 0.10 }
    if (top >= 2) { bR = 86; bC = "#FF375F"; bA = 0.50; mC = "#BF5AF2"; bM = 0.15 }
  }

  # CPU gauge: 240° arc, r 40 around (52, 58); the lit dash grows from the left end
  L = 167.55
  cs = cpu >= 0 ? clamp(cpu / 100, 0.004, 1) : 0.004
  co = live * (cpu >= 0)
  off = L * (1 - cs)
  d = L * cs; if (d > L - 0.3) d = L - 0.3
  ang = -120 + 240 * cs
  # the heat glow at the tip moves by position, not by rotate(): a jump of more than 180° (idle → full load)
  # would turn it the short way, through the gap at the bottom, away from the bead
  gx = 52 + 40 * sin(ang * pi / 180); gy = 58 - 40 * cos(ang * pi / 180)
  gc = tip((gx - 12) / 80, cl)

  # traffic chart: 46 samples 4 apart from x 10 (45 on screen = 3 min at 4 s); the newest sits in a slot at x 190
  # outside the clip until the slide. Download is the bright spectrum line, upload the dim white one under it.
  nd = split(ds, pd, " "); nu = split(us, pu, " ")
  for (i = 1; i <= 46; i++) {
    cx[i] = 10 + 4 * (i - 1)
    cy[i] = ly(live && i <= nd ? pd[i] + 0 : 0)
    uy[i] = ly(live && i <= nu ? pu[i] + 0 : 0)
  }
  line = ""; uline = ""; area = "M 10 184"
  for (i = 1; i <= 46; i++) {
    line = line (i > 1 ? " " : "") cx[i] "," f(cy[i]); uline = uline (i > 1 ? " " : "") cx[i] "," f(uy[i])
    area = area " L " cx[i] " " f(cy[i])
  }
  area = area " L 190 184 Z"
  tx = ph ? -4 : 0                             # the slide moves the samples one step left
  headY = ph ? cy[46] : cy[45]                 # the samples under the right edge (x 186)
  upY = ph ? uy[46] : uy[45]

  # the rest glyph: a big neon pulse; with data it sinks into the chart and dissolves
  split("-62 -28 -16 -1 13 22 62", ex, " "); split("0 0 -30 34 -18 0 0", ey, " ")
  if (live) { kx = 100; ky = 170; k = 0.4; pw = 2; po = 0 } else { kx = 100; ky = 100; k = 1; pw = 4.5; po = 0.8 }
  pulse = ""
  for (i = 1; i <= 7; i++) pulse = pulse (i > 1 ? " L " : "M ") f(kx + k * ex[i]) " " f(ky + k * ey[i])

  arc = "d=`M 17.36 78 A 40 40 0 1 1 86.64 78` fill=`none`"
  hot = "<stop offset=`0` stop-color=`#64D2FF`/><stop offset=`0.3` stop-color=`#5E5CE6`/><stop offset=`0.65` stop-color=`#BF5AF2`/><stop offset=`1` stop-color=`#FF375F`/>"

  s = "<svg xmlns=`http://www.w3.org/2000/svg` viewBox=`0 0 200 200`><defs>"
  s = s "<linearGradient id=`gaugeG` gradientUnits=`userSpaceOnUse` x1=`12` y1=`0` x2=`92` y2=`0`>" hot "</linearGradient>"
  s = s "<linearGradient id=`barG` gradientUnits=`userSpaceOnUse` x1=`112` y1=`0` x2=`186` y2=`0`>" hot "</linearGradient>"
  s = s "<linearGradient id=`lineG` gradientUnits=`userSpaceOnUse` x1=`" (10 + 4 * ph) "` y1=`0` x2=`" (186 + 4 * ph) "` y2=`0`>" \
        "<stop offset=`0` stop-color=`#BF5AF2`/><stop offset=`0.55` stop-color=`#5E5CE6`/><stop offset=`1` stop-color=`#64D2FF`/></linearGradient>"
  s = s "<linearGradient id=`areaG` gradientUnits=`userSpaceOnUse` x1=`0` y1=`142` x2=`0` y2=`184`>" \
        "<stop offset=`0` stop-color=`#64D2FF` stop-opacity=`0.28`/><stop offset=`1` stop-color=`#5E5CE6` stop-opacity=`0`/></linearGradient>"
  s = s "<linearGradient id=`pulseG` gradientUnits=`userSpaceOnUse` x1=`40` y1=`0` x2=`160` y2=`0`><stop offset=`0` stop-color=`#BF5AF2`/><stop offset=`1` stop-color=`#64D2FF`/></linearGradient>"
  s = s "<radialGradient id=`bloomG`><stop offset=`0` stop-color=`" bC "` stop-opacity=`" f(bA) "`/><stop offset=`0.55` stop-color=`" mC "` stop-opacity=`" f(bM) "`/>" \
        "<stop offset=`1` stop-color=`" mC "` stop-opacity=`0`/></radialGradient>"
  s = s glowGrad("gHeatG", gc, co * (cl ? 0.8 : 0.55))
  s = s glowGrad("memHeatG", tip(clamp(mem / 100, 0, 1), ml), live * (mem >= 0) * (ml ? 0.8 : 0.5))
  s = s glowGrad("dskHeatG", tip(clamp(dsk / 100, 0, 1), dl), live * (dsk >= 0) * (dl ? 0.8 : 0.5))
  s = s glowGrad("netHeatG", "#64D2FF", live * 0.5)
  s = s "<clipPath id=`chartClip`><rect x=`10` y=`100` width=`176` height=`92`/></clipPath></defs>"

  s = s "<circle id=`bloom` cx=`" bX "` cy=`" bY "` r=`" bR "` fill=`url(#bloomG)`/>"

  # CPU
  s = s "<path id=`gTrack` " arc " stroke=`" (cl >= 2 ? "#FF375F" : "#FFFFFF") "` stroke-opacity=`" f(live * (cl >= 2 ? 0.3 : 0.18)) "` stroke-width=`3` stroke-linecap=`round`/>"
  s = s "<path id=`gGlow` " arc " stroke=`url(#gaugeG)` stroke-opacity=`" f(0.2 * co) "` stroke-width=`11` stroke-linecap=`round` stroke-dasharray=`167.55 167.55` stroke-dashoffset=`" f(off) "`/>"
  s = s "<path id=`gLit` " arc " stroke=`url(#gaugeG)` stroke-opacity=`" f(co) "` stroke-width=`4.5` stroke-linecap=`round` stroke-dasharray=`167.55 167.55` stroke-dashoffset=`" f(off) "`/>"
  s = s "<path id=`gCore` " arc " stroke=`#FFFFFF` stroke-opacity=`" f(0.45 * co) "` stroke-width=`1.3` stroke-linecap=`round` stroke-dasharray=`167.55 167.55` stroke-dashoffset=`" f(off) "`/>"
  s = s "<circle id=`gHeat` cx=`" f(gx) "` cy=`" f(gy) "` r=`" (cl ? 18 : 14) "` fill=`url(#gHeatG)`/>"
  s = s "<path id=`gHalo` " arc " stroke=`url(#gaugeG)` stroke-opacity=`" f(0.45 * co) "` stroke-width=`9` stroke-linecap=`round` stroke-dasharray=`0.1 300` stroke-dashoffset=`" f(-d) "`/>"
  s = s "<path id=`gBead` " arc " stroke=`#FFFFFF` stroke-opacity=`" f(co) "` stroke-width=`6` stroke-linecap=`round` stroke-dasharray=`0.1 300` stroke-dashoffset=`" f(-d) "`/>"
  s = s valueText("cpuValue", 52, 57, "middle", (cpu >= 99.5 ? 25 : 28), (live ? cpu : -1), cl, live * (cpu >= 0 ? 1 : 0.6))
  s = s "<rect id=`chip` x=`45` y=`82` width=`14` height=`14` rx=`3` fill=`none` stroke=`#FFFFFF` stroke-opacity=`" f(go) "` stroke-width=`2`/>"
  s = s "<path id=`chipPins` d=`M 49.5 82 L 49.5 79 M 54.5 82 L 54.5 79 M 49.5 96 L 49.5 99 M 54.5 96 L 54.5 99 M 45 86.5 L 42 86.5 M 45 91.5 L 42 91.5 M 59 86.5 L 62 86.5 M 59 91.5 L 62 91.5` " \
        "fill=`none` stroke=`#FFFFFF` stroke-opacity=`" f(go) "` stroke-width=`2` stroke-linecap=`round`/>"

  # memory pressure
  s = s "<rect id=`memChip` x=`110` y=`24` width=`22` height=`10` rx=`2` fill=`none` stroke=`#FFFFFF` stroke-opacity=`" f(go) "` stroke-width=`2`/>"
  s = s "<path id=`memPins` d=`M 114.5 34 L 114.5 38 M 119 34 L 119 38 M 123 34 L 123 38 M 127.5 34 L 127.5 38` fill=`none` stroke=`#FFFFFF` stroke-opacity=`" f(go) "` stroke-width=`2` stroke-linecap=`round`/>"
  s = s valueText("memValue", 188, 30, "end", 22, (live ? mem : -1), ml, live * (mem >= 0 ? 1 : 0.6))
  s = s bar("mem", 50, (live ? mem : -1), ml)

  # startup disk, used
  s = s "<rect id=`drive` x=`110` y=`64` width=`22` height=`13` rx=`3.5` fill=`none` stroke=`#FFFFFF` stroke-opacity=`" f(go) "` stroke-width=`2`/>"
  s = s "<line id=`driveSlot` x1=`114.5` y1=`70.5` x2=`120.5` y2=`70.5` stroke=`#FFFFFF` stroke-opacity=`" f(go) "` stroke-width=`2` stroke-linecap=`round`/>"
  s = s "<circle id=`driveLed` cx=`126.5` cy=`70.5` r=`1.6` fill=`#FFFFFF` fill-opacity=`" f(go) "`/>"
  s = s valueText("dskValue", 188, 70, "end", 22, (live ? dsk : -1), dl, live * (dsk >= 0 ? 1 : 0.6))
  s = s bar("dsk", 90, (live ? dsk : -1), dl)

  # network traffic right now: ↓ value (cyan arrow = the bright line), ↑ value (white arrow = the dim line), one unit
  s = s "<path id=`downArrow` d=`M 16 113 L 16 131 M 10.5 125.5 L 16 131 L 21.5 125.5` fill=`none` stroke=`#64D2FF` stroke-opacity=`" f(live * 0.9) "` stroke-width=`2.2` stroke-linecap=`round` stroke-linejoin=`round`/>"
  s = s "<text id=`downValue` x=`27` y=`122` font-size=`22` font-weight=`600` dominant-baseline=`middle` fill=`#FFFFFF` fill-opacity=`" f(live * (dt == "—" ? 0.6 : 1)) "`>" dt "</text>"
  s = s "<path id=`upArrow` d=`M 82 131 L 82 113 M 76.5 118.5 L 82 113 L 87.5 118.5` fill=`none` stroke=`#FFFFFF` stroke-opacity=`" f(go) "` stroke-width=`2.2` stroke-linecap=`round` stroke-linejoin=`round`/>"
  s = s "<text id=`upValue` x=`93` y=`122` font-size=`22` font-weight=`600` dominant-baseline=`middle` fill=`#FFFFFF` fill-opacity=`" f(live * (ut == "—" ? 0.6 : 1)) "`>" ut "</text>"
  s = s "<text id=`netUnit` x=`188` y=`122` font-size=`16` font-weight=`600` text-anchor=`end` dominant-baseline=`middle` fill=`#FFFFFF` fill-opacity=`" f(go) "`>" un "</text>"
  # quiet guides at 1, 10 and 100 Mbps; the base line is 0.1 Mbps
  s = s "<path id=`chartGuides` d=`M 10 173.5 L 186 173.5 M 10 163 L 186 163 M 10 152.5 L 186 152.5` fill=`none` stroke=`#FFFFFF` stroke-opacity=`" f(live * 0.1) "` stroke-width=`1` stroke-dasharray=`1 4` stroke-linecap=`round`/>"
  s = s "<line id=`chartBase` x1=`10` y1=`184` x2=`186` y2=`184` stroke=`#FFFFFF` stroke-opacity=`" f(live * 0.18) "` stroke-width=`1.5` stroke-linecap=`round`/>"
  s = s "<g id=`chart` clip-path=`url(#chartClip)`><g id=`scroll` transform=`translate(" tx " 0)`>"
  s = s "<path id=`area` d=`" area "` fill=`url(#areaG)` fill-opacity=`" f(live) "`/>"
  s = s "<polyline id=`upLine` points=`" uline "` fill=`none` stroke=`#FFFFFF` stroke-opacity=`" f(0.4 * live) "` stroke-width=`1.75` stroke-linecap=`round` stroke-linejoin=`round`/>"
  s = s "<polyline id=`lineGlow` points=`" line "` fill=`none` stroke=`url(#lineG)` stroke-opacity=`" f(0.2 * live) "` stroke-width=`9` stroke-linecap=`round` stroke-linejoin=`round`/>"
  s = s "<polyline id=`line` points=`" line "` fill=`none` stroke=`url(#lineG)` stroke-opacity=`" f(live) "` stroke-width=`3` stroke-linecap=`round` stroke-linejoin=`round`/>"
  s = s "<polyline id=`lineCore` points=`" line "` fill=`none` stroke=`#FFFFFF` stroke-opacity=`" f(0.4 * live) "` stroke-width=`1` stroke-linecap=`round` stroke-linejoin=`round`/>"
  s = s "</g></g>"
  s = s "<circle id=`upBead` cx=`186` cy=`" f(upY) "` r=`2.25` fill=`#FFFFFF` fill-opacity=`" f(0.6 * live) "`/>"
  s = s "<circle id=`netHeat` cx=`186` cy=`" f(headY) "` r=`10` fill=`url(#netHeatG)`/>"
  s = s "<circle id=`netHalo` cx=`186` cy=`" f(headY) "` r=`4.5` fill=`#64D2FF` fill-opacity=`" f(0.45 * live) "`/>"
  s = s "<circle id=`netBead` cx=`186` cy=`" f(headY) "` r=`2.75` fill=`#FFFFFF` fill-opacity=`" f(live) "`/>"

  s = s "<path id=`pulse` d=`" pulse "` fill=`none` stroke=`url(#pulseG)` stroke-opacity=`" f(po) "` stroke-width=`" pw "` stroke-linecap=`round` stroke-linejoin=`round`/>"
  s = s "</svg>"
  gsub(/`/, "\"", s)
  printf "%s", s
}
AWK

# sysmon_frame <rest|live> <phase 0|1> <cpu %> <cpu level> <memory %> <memory level> <disk %> <disk level>
#              <download text> <upload text> <unit> <download samples> <upload samples>
# A percent of -1 means unknown and shows "—". Levels: 0 calm, 1 warning, 2 critical.
# Samples: 46 rates in Mbps, oldest first, in one space-separated argument; the last one waits off the right edge.
sysmon_frame() {
  emulate -L zsh
  export LC_ALL=C
  local dt=${9:-—} ut=${10:-—} un=${11:-Mbps}
  dt=${dt//&/&amp;}; dt=${dt//</&lt;}; dt=${dt//>/&gt;}
  ut=${ut//&/&amp;}; ut=${ut//</&lt;}; ut=${ut//>/&gt;}
  un=${un//&/&amp;}; un=${un//</&lt;}; un=${un//>/&gt;}
  awk -v st="${1:-rest}" -v ph="${2:-0}" -v cpu="${3:--1}" -v cl="${4:-0}" -v mem="${5:--1}" -v ml="${6:-0}" \
      -v dsk="${7:--1}" -v dl="${8:-0}" -v dt="$dt" -v ut="$ut" -v un="$un" -v ds="${12}" -v us="${13}" "$SYSMON_AWK"
}
# ---- end frame ----

api="http://127.0.0.1:9848/api"
# The token stays off the command line, where any app on the Mac can read it: curl takes it from its
# environment ({{DESMAPTIC_TOKEN}} is curl's own syntax).
auth=(--variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}')

# -- readers -------------------------------------------------------------------------------------------------

# CPU: one long-lived iostat, a row every 4 s; its first row is the average since boot and is skipped.
start_sampling() {
  coproc iostat -n 0 -w 4
  cpu_pid=$!
  cpu_fresh=1
  net_baseline
}
stop_sampling() {
  [[ -n $cpu_pid ]] && kill $cpu_pid 2>/dev/null
  cpu_pid=""
}
read_cpu() {                                   # waits for the next row; sets cpu (busy %), returns 1 when iostat is gone
  local line
  local -a w
  while read -t 10 -p line; do
    w=( ${=line} )
    [[ ${w[1]} == <-> && ${w[2]} == <-> && ${w[3]} == <-> ]] || continue
    if (( cpu_fresh )); then cpu_fresh=0; continue; fi
    cpu=$(( 100 - w[3] )); (( cpu < 0 )) && cpu=0
    cpu_level=0; (( cpu >= 75 )) && cpu_level=1; (( cpu >= 90 )) && cpu_level=2
    return 0
  done
  return 1
}

# Memory: kern.memorystatus_level is the share of memory still available; the pressure level is what
# Activity Monitor colours its graph by (1 normal, 2 warning, 4 critical).
read_memory() {
  local -a m
  m=( $(sysctl -n kern.memorystatus_level kern.memorystatus_vm_pressure_level 2>/dev/null) )
  if [[ ${m[1]} == <-> ]] && (( m[1] <= 100 )); then
    mem=$(( 100 - m[1] ))
  else
    mem=-1
  fi
  case ${m[2]} in
    4) mem_level=2 ;;
    2) mem_level=1 ;;
    *) mem_level=0 ;;
  esac
}

# Startup disk: the share of the APFS container in use, with the thresholds of the Disk Free widget.
read_disk() {
  local -a r
  r=( $(df -k / 2>/dev/null | awk 'NR == 2 && $2 > 0 {
    free = $4 / $2; gb = $4 * 1024 / 1e9
    level = 0; if (free < 0.15 || gb < 20) level = 1; if (free < 0.05 || gb < 5) level = 2
    printf "%.1f %d\n", 100 - free * 100, level }') )
  if [[ ${r[1]} == <->.<-> ]]; then
    disk=${r[1]}; disk_level=${r[2]}
  else
    disk=-1; disk_level=0
    print -u2 "df gave no size for /"
  fi
}

# Network: the Mac's traffic right now, received and sent, summed over every physical interface (en0, en1, …:
# Ethernet, Wi-Fi, Thunderbolt), whichever carries the default route. Tunnels (utun), bridges, AWDL, the
# loopback and the like carry the same bytes a second time and are left out. A counter that went back
# (reset, interface re-created) counts 0 for that sample; an interface that just appeared counts from the next one.
typeset -A net_rx net_tx
net_counters() {                               # "<interface> <bytes in> <bytes out>" per en interface
  netstat -ibn 2>/dev/null | awk '$3 ~ /^<Link#/ {
    n = $1; sub(/\*$/, "", n)
    if (n !~ /^en[0-9]+$/ || (n in seen)) next
    seen[n] = 1
    if ($(NF - 4) ~ /^[0-9]+$/ && $(NF - 1) ~ /^[0-9]+$/) print n, $(NF - 4), $(NF - 1) }'
}
net_baseline() {
  net_rx=(); net_tx=()
  read_net
}
read_net() {                                   # sets rate_down and rate_up (Mbps), -1 when there is no reading
  local name rx tx now
  local -A seen
  integer down=0 up=0 d known=0
  now=$EPOCHREALTIME
  rate_down=-1; rate_up=-1
  # too soon after the last reading (rows that queued up while the Mac was busy): keep the counters,
  # the next reading covers this time too
  (( ${#net_rx} && now - net_at <= 0.5 )) && return
  for name rx tx in $(net_counters); do
    seen[$name]=1
    if (( ${+net_rx[$name]} )); then
      known=1
      d=$(( rx - ${net_rx[$name]} )); (( d > 0 )) && (( down += d ))
      d=$(( tx - ${net_tx[$name]} )); (( d > 0 )) && (( up += d ))
    fi
    net_rx[$name]=$rx; net_tx[$name]=$tx
  done
  for name in ${(k)net_rx}; do
    (( ${+seen[$name]} )) || unset "net_rx[$name]" "net_tx[$name]"
  done
  if (( known && now - net_at > 0.5 )); then
    printf -v rate_down '%.3f' $(( down * 8.0 / (now - net_at) / 1e6 ))
    printf -v rate_up '%.3f' $(( up * 8.0 / (now - net_at) / 1e6 ))
  fi
  net_at=$now
}

# "<down> <up> <unit>" of two rates in Mbps, in one unit: 0.4 · 7.5 · 42 Mbps, or 1.2 · 0.04 Gbps; — when unknown
rate_texts() {
  awk -v d="$1" -v u="$2" 'function fm(r, g) {
      if (r < 0) return "—"
      if (!g)    return r < 9.95 ? sprintf("%.1f", r) : sprintf("%d", r + 0.5)
      r /= 1000
      return r < 0.995 ? sprintf("%.2f", r) : (r < 9.95 ? sprintf("%.1f", r) : sprintf("%d", r + 0.5))
    }
    BEGIN { g = (d >= 999.5 || u >= 999.5); print fm(d, g), fm(u, g), (g ? "Gbps" : "Mbps") }'
}

# -- posting --------------------------------------------------------------------------------------------------

# post_frames <frame> <svg options> [<frame> <svg options>]… — posts in order over one curl run.
# Sets answer; returns 0 when every frame got 200.
post_frames() {
  local -a args
  local frame codes
  while (( $# >= 2 )); do
    frame=$1
    frame=${frame//\\/\\\\}; frame=${frame//\"/\\\"}; frame=${frame//$'\n'/}
    (( ${#args} )) && args+=(--next)
    args+=(-s -m 5 -w '\n%{http_code}\n' "$api/update-button" "${auth[@]}" -H "Content-Type: application/json"
           -d "{\"cellId\":\"{{CELL_ID}}\",\"svg\":{\"source\":\"$frame\",$2}}")
    shift 2
  done
  answer=$(curl -q "${args[@]}" 2>/dev/null)
  codes=${(j: :)${(M)${(f)answer}:#[0-9][0-9][0-9]}}
  [[ -n $codes && ${codes//200/} == ${codes//[0-9]/} ]] && return 0
  print -u2 "update-button answered: ${answer//$'\n'/ }"
  return 1
}

# While the button is off screen: no sampling, no frames, one look at the phone every 3 s.
wait_until_visible() {
  local view
  local me="{{CELL_ID}}"
  me=${(L)me}
  while true; do
    sleep 3
    view=$(curl -q -s -m 5 "$api/view" "${auth[@]}" 2>/dev/null) || continue
    [[ $view == *'"view":'* ]] || continue
    [[ $view == *'"view":null'* || $view != *'"visibleCellIds"'* ]] && return   # an app that does not say
    [[ ${(L)view} == *$me* ]] && return
  done
}

# -- loop -----------------------------------------------------------------------------------------------------

hist_down=(); repeat 46 hist_down+=(0)          # Mbps, oldest first; [46] waits off the right edge until the slide
hist_up=( $hist_down )
hist_real=0                                    # the histories hold a real reading (until then they are padded)
shown=0                                        # a live frame is on the button
shown_vals=()                                  # what the last slide shows: cpu level mem level disk level down up unit
last_slide=""
last_post=0
last_pair=0
hold_down=0
hold_up=0

read_disk; disk_at=$EPOCHSECONDS
start_sampling

while true; do
  if ! read_cpu; then
    print -u2 "iostat stopped; starting it again"
    stop_sampling; sleep 2; start_sampling
    continue
  fi
  if (( EPOCHSECONDS - disk_at >= 60 )); then read_disk; disk_at=$EPOCHSECONDS; fi
  read_memory
  read_net
  (( rate_down >= 0 )) && { hold_down=$rate_down; hold_up=$rate_up }   # no reading: the chart holds its last value
  if (( rate_down >= 0 && ! hist_real )); then
    # a young history is padded with its first reading, so the chart does not climb out of an invented zero
    hist_down=(); repeat 46 hist_down+=($hold_down)
    hist_up=(); repeat 46 hist_up+=($hold_up)
    hist_real=1
  else
    hist_down=( ${hist_down[2,-1]} $hold_down )
    hist_up=( ${hist_up[2,-1]} $hold_up )
  fi
  # the values hold their last reading too; "—" only until the first one
  if (( hist_real )); then nt=( $(rate_texts $hold_down $hold_up) ); else nt=( $(rate_texts -1 -1) ); fi
  vals=( $cpu $cpu_level $mem $mem_level $disk $disk_level $nt[1] $nt[2] $nt[3] )

  slide=$(sysmon_frame live 1 $vals "${(j: :)hist_down}" "${(j: :)hist_up}")
  now=$EPOCHREALTIME
  if (( ! shown )); then
    post_frames "$slide" '"duration":1.2'               # the first frame glides out of the saved face
    ok=$?
  elif [[ $slide == "$last_slide" ]] && (( EPOCHSECONDS - last_post < 30 )); then
    shown_vals=( $vals )
    continue                                             # nothing on the button would change
  else
    # rest: the samples re-indexed one step, drawn exactly as the last slide ended; slide: one step left, new values
    rest=$(sysmon_frame live 0 $shown_vals "${(j: :)hist_down}" "${(j: :)hist_up}")
    period=4.0
    (( last_pair > 0 && now - last_pair < 6.4 )) && period=$(( now - last_pair ))
    (( period < 3.6 )) && period=3.6
    printf -v slide_opts '"duration":%.2f,"easing":"linear"' $(( period * 1.05 ))
    post_frames "$rest" '"duration":0.01' "$slide" "$slide_opts"
    ok=$?
  fi

  if (( ok == 0 )); then
    shown=1; shown_vals=( $vals )
    last_slide=$slide; last_post=$EPOCHSECONDS; last_pair=$now
    if [[ $answer == *'"visible":false'* ]]; then
      stop_sampling
      wait_until_visible
      last_pair=0
      start_sampling
    fi
  else
    stop_sampling
    sleep 10
    last_pair=0
    start_sampling
  fi
done
