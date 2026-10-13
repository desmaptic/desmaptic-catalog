#!/bin/zsh
# Disk Free: free space on the startup disk, as Finder counts it, drawn as a neon fuel gauge
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT

disk_frame() {
  emulate -L zsh
  export LC_ALL=C
  local used=${1:-0} value=${2:-0} unit=${3:-GB} state=${4:-rest}
  [[ $used == <-> ]] || used=0
  (( used > 1000 )) && used=1000
  [[ $state == (rest|ok|warn|critical) ]] || state=rest
  [[ -z $value ]] && value=0
  [[ -z $unit ]] && unit=GB
  local vsize=60
  (( ${#value} >= 4 )) && vsize=56              # "12.5" still clears the arc
  value=${value//&/&amp;}; value=${value//</&lt;}; value=${value//>/&gt;}
  unit=${unit//&/&amp;};   unit=${unit//</&lt;};   unit=${unit//>/&gt;}

  # Every number and state colour comes from awk as "key value" pairs
  # (zsh float arithmetic would print 0.17999999999999999).
  local -A v
  v=( ${=$(awk -v u=$used -v st=$state '
    function hex(h,   i, n) { n = 0; h = toupper(h); for (i = 1; i <= length(h); i++) n = n * 16 + index("0123456789ABCDEF", substr(h, i, 1)) - 1; return n }
    function mix(a, b, t,   i, o, x, y) {
      o = "#"
      for (i = 2; i <= 6; i += 2) { x = hex(substr(a, i, 2)); y = hex(substr(b, i, 2)); o = o sprintf("%02X", int(x + (y - x) * t + 0.5)) }
      return o
    }
    function spectrum(t) {                     # the arc gradient: #FF375F → #BF5AF2 (.35) → #5E5CE6 (.7) → #64D2FF
      if (t <= 0)   return "#FF375F"
      if (t < 0.35) return mix("#FF375F", "#BF5AF2", t / 0.35)
      if (t < 0.7)  return mix("#BF5AF2", "#5E5CE6", (t - 0.35) / 0.35)
      if (t < 1)    return mix("#5E5CE6", "#64D2FF", (t - 0.7) / 0.3)
      return "#64D2FF"
    }
    function kv(k, x) { printf "%s %s\n", k, x }
    function num(k, x) { printf "%s %.2f\n", k, x }
    BEGIN {
      L = 335.10                               # arc length: r 80 · 240° = 80 · 4π/3
      f = (1000 - u) / 1000                    # free share
      live = (st == "rest") ? 0 : 1
      if (!live) f = 0.5                       # rest: arc end, bead and glow parked at 12 o’clock
      d = L * f; if (d > L - 0.3) d = L - 0.3  # keep the bead’s dash on the path
      num("off", L * (1 - f))                  # lit dash covers 0 … L·f
      num("pos", -d)                           # bead: a 0.1-long dash starting at L·f
      ang = -120 + 240 * f                     # glow: degrees clockwise from 12 o’clock
      num("ang", ang)
      x = 100 + 80 * sin(ang * 3.14159265 / 180)
      gc = spectrum((x - 24) / 152)            # glow colour = the arc colour under the bead

      # state:       bloom centre / mid colour and opacity, radius   glow r, core opacity   halo width, opacity   LED   unit colour, opacity   drive-glyph gradient
      if (st == "rest")     { bC = "#BF5AF2"; bA = 0.12; mC = "#5E5CE6"; bM = 0.04; bR = 82; gR = 28; gA = 0.55; hW = 18; hO = 0.45; led = "#64D2FF"; uC = "#FFFFFF"; uO = 0.6;  d1 = "#BF5AF2"; d2 = "#64D2FF" }
      if (st == "ok")       { bC = "#BF5AF2"; bA = 0.20; mC = "#5E5CE6"; bM = 0.07; bR = 86; gR = 28; gA = 0.55; hW = 18; hO = 0.45; led = "#64D2FF"; uC = "#FFFFFF"; uO = 0.6;  d1 = "#BF5AF2"; d2 = "#64D2FF" }
      if (st == "warn")     { bC = "#E0479E"; bA = 0.32; mC = "#BF5AF2"; bM = 0.10; bR = 90; gR = 28; gA = 0.70; hW = 20; hO = 0.50; led = "#E24FC9"; uC = "#FFFFFF"; uO = 0.6;  d1 = "#FF6FA0"; d2 = "#BF5AF2" }
      if (st == "critical") { bC = "#FF375F"; bA = 0.57; mC = "#BF5AF2"; bM = 0.16; bR = 98; gR = 32; gA = 0.95; hW = 22; hO = 0.60; led = "#FF375F"; uC = "#FF7A96"; uO = 0.95; d1 = "#FF375F"; d2 = "#FF8FA8"; gc = "#FF375F" }
      # track: a faint spectrum on the rest face, white 0.14 while live, hot pink when critical
      if (st == "rest")     { split("#FF375F #BF5AF2 #5E5CE6 #64D2FF", tc, " "); split("0.30 0.30 0.30 0.30", to, " ") }
      if (st == "ok" || st == "warn") { split("#FFFFFF #FFFFFF #FFFFFF #FFFFFF", tc, " "); split("0.18 0.18 0.18 0.18", to, " ") }
      if (st == "critical") { split("#FF375F #FF375F #FF375F #FF375F", tc, " "); split("0.30 0.24 0.20 0.20", to, " ") }
      for (i = 1; i <= 4; i++) { kv("tc" i, tc[i]); kv("to" i, to[i]) }

      kv("gc", gc); kv("bC", bC); num("bA", bA); kv("mC", mC); num("bM", bM); kv("bR", bR)
      kv("gR", gR); num("gA", live * gA); num("gM", live * 0.4 * gA); kv("hW", hW); num("hO", live * hO)
      kv("led", led); num("tEO", st == "critical" ? 0 : 0.9); kv("uC", uC); num("uO", live * uO); kv("d1", d1); kv("d2", d2)
      num("live", live); num("litGlowO", live * 0.2); num("coreO", live * 0.45); num("driveO", 0)

      # the big drive glyph is the rest face; when data arrives it sinks to the bottom and fades out (the live face has no glyph)
      if (live) { bx = 82; by = 161; bw = 36; bh = 21; br = 6;  sx1 = 88; sx2 = 99; sy = 171.5; lx = 110.5; ly = 171.5; lr = 3; bo = 0 }
      else      { bx = 64; by = 79;  bw = 72; bh = 42; br = 11; sx1 = 76; sx2 = 98; sy = 100;   lx = 121;   ly = 100;   lr = 5; bo = 0.75 }
      kv("bx", bx); kv("by", by); kv("bw", bw); kv("bh", bh); kv("br", br)
      kv("sx1", sx1); kv("sx2", sx2); kv("sy", sy); kv("lx", lx); kv("ly", ly); kv("lr", lr); num("bo", bo); num("blo", bo > 0 ? 1 : 0)
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
<linearGradient id=\"driveG\" gradientUnits=\"userSpaceOnUse\" x1=\"60\" y1=\"0\" x2=\"140\" y2=\"0\"><stop offset=\"0\" stop-color=\"$v[d1]\"/><stop offset=\"1\" stop-color=\"$v[d2]\"/></linearGradient>\
<radialGradient id=\"bloomG\"><stop offset=\"0\" stop-color=\"$v[bC]\" stop-opacity=\"$v[bA]\"/><stop offset=\"0.55\" stop-color=\"$v[mC]\" stop-opacity=\"$v[bM]\"/><stop offset=\"1\" stop-color=\"$v[mC]\" stop-opacity=\"0\"/></radialGradient>\
<radialGradient id=\"glowG\"><stop offset=\"0\" stop-color=\"$v[gc]\" stop-opacity=\"$v[gA]\"/><stop offset=\"0.4\" stop-color=\"$v[gc]\" stop-opacity=\"$v[gM]\"/><stop offset=\"1\" stop-color=\"$v[gc]\" stop-opacity=\"0\"/></radialGradient>\
</defs>\
<circle id=\"bloom\" cx=\"100\" cy=\"100\" r=\"$v[bR]\" fill=\"url(#bloomG)\"/>\
<path id=\"track\" $arc stroke=\"url(#trackG)\" stroke-width=\"6\" stroke-linecap=\"round\"/>\
<path id=\"ticks\" d=\"M 100 38 L 100 33\" fill=\"none\" stroke=\"#FFFFFF\" stroke-opacity=\"0.3\" stroke-width=\"2.5\" stroke-linecap=\"round\"/>\
<line id=\"tickE\" x1=\"46.31\" y1=\"131\" x2=\"41.98\" y2=\"133.5\" stroke=\"#FF375F\" stroke-opacity=\"$v[tEO]\" stroke-width=\"3\" stroke-linecap=\"round\"/>\
<line id=\"tickF\" x1=\"153.69\" y1=\"131\" x2=\"158.02\" y2=\"133.5\" stroke=\"#64D2FF\" stroke-opacity=\"0.9\" stroke-width=\"3\" stroke-linecap=\"round\"/>\
<path id=\"litGlow\" $arc stroke=\"url(#spec)\" stroke-opacity=\"$v[litGlowO]\" stroke-width=\"22\" stroke-linecap=\"round\" stroke-dasharray=\"335.1 335.1\" stroke-dashoffset=\"$v[off]\"/>\
<path id=\"lit\" $arc stroke=\"url(#spec)\" stroke-opacity=\"$v[live]\" stroke-width=\"9\" stroke-linecap=\"round\" stroke-dasharray=\"335.1 335.1\" stroke-dashoffset=\"$v[off]\"/>\
<path id=\"core\" $arc stroke=\"#FFFFFF\" stroke-opacity=\"$v[coreO]\" stroke-width=\"2.5\" stroke-linecap=\"round\" stroke-dasharray=\"335.1 335.1\" stroke-dashoffset=\"$v[off]\"/>\
<circle id=\"glow\" cx=\"100\" cy=\"26\" r=\"$v[gR]\" fill=\"url(#glowG)\" transform=\"rotate($v[ang] 100 100)\"/>\
<path id=\"halo\" $arc stroke=\"url(#spec)\" stroke-opacity=\"$v[hO]\" stroke-width=\"$v[hW]\" stroke-linecap=\"round\" stroke-dasharray=\"0.1 400\" stroke-dashoffset=\"$v[pos]\"/>\
<path id=\"bead\" $arc stroke=\"#FFFFFF\" stroke-opacity=\"$v[live]\" stroke-width=\"12\" stroke-linecap=\"round\" stroke-dasharray=\"0.1 400\" stroke-dashoffset=\"$v[pos]\"/>\
<text id=\"value\" x=\"100\" y=\"97\" font-size=\"$vsize\" font-weight=\"600\" text-anchor=\"middle\" dominant-baseline=\"middle\" fill=\"#FFFFFF\" fill-opacity=\"$v[live]\">$value</text>\
<text id=\"unit\" x=\"100\" y=\"138\" font-size=\"26\" font-weight=\"600\" text-anchor=\"middle\" dominant-baseline=\"middle\" fill=\"$v[uC]\" fill-opacity=\"$v[uO]\">$unit</text>\
<rect id=\"drive\" x=\"82\" y=\"161\" width=\"36\" height=\"21\" rx=\"6\" fill=\"none\" stroke=\"url(#driveG)\" stroke-opacity=\"$v[driveO]\" stroke-width=\"3.5\"/>\
<line id=\"slot\" x1=\"88\" y1=\"171.5\" x2=\"99\" y2=\"171.5\" stroke=\"url(#driveG)\" stroke-opacity=\"$v[driveO]\" stroke-width=\"3.5\" stroke-linecap=\"round\"/>\
<circle id=\"led\" cx=\"110.5\" cy=\"171.5\" r=\"3\" fill=\"$v[led]\" fill-opacity=\"0\"/>\
<rect id=\"bigDrive\" x=\"$v[bx]\" y=\"$v[by]\" width=\"$v[bw]\" height=\"$v[bh]\" rx=\"$v[br]\" fill=\"none\" stroke=\"url(#driveG)\" stroke-opacity=\"$v[bo]\" stroke-width=\"5\"/>\
<line id=\"bigSlot\" x1=\"$v[sx1]\" y1=\"$v[sy]\" x2=\"$v[sx2]\" y2=\"$v[sy]\" stroke=\"url(#driveG)\" stroke-opacity=\"$v[bo]\" stroke-width=\"5\" stroke-linecap=\"round\"/>\
<circle id=\"bigLed\" cx=\"$v[lx]\" cy=\"$v[ly]\" r=\"$v[lr]\" fill=\"#64D2FF\" fill-opacity=\"$v[blo]\"/>\
</svg>"
}

api="http://127.0.0.1:9848/api/update-button"

# "<free bytes> <total bytes>" of the startup disk; free counts purgeable space, as Finder does.
read_disk() {
  /usr/bin/osascript -l JavaScript -e '
    ObjC.import("Foundation");
    const free = $.NSURLVolumeAvailableCapacityForImportantUsageKey, total = $.NSURLVolumeTotalCapacityKey;
    const v = $.NSURL.fileURLWithPath("/").resourceValuesForKeysError($([free, total]), null);
    ObjC.unwrap(v.objectForKey(free)) + " " + ObjC.unwrap(v.objectForKey(total))' 2>/dev/null
}

# "<used per mille> <value> <unit> <state>" in decimal units, as Finder: 412 GB, 7.4 GB, 1.2 TB.
describe() {
  awk -v f="$1" -v t="$2" 'BEGIN {
    gb = f / 1e9
    if (gb >= 1000)    { v = sprintf("%.1f", gb / 1000); u = "TB" }
    else if (gb >= 10) { v = sprintf("%d", gb); u = "GB" }
    else if (gb >= 1)  { v = sprintf("%.1f", gb); u = "GB" }
    else               { v = sprintf("%d", f / 1e6); u = "MB" }
    used = (t > 0) ? int((t - f) / t * 1000 + 0.5) : 0
    if (used < 0) used = 0
    if (used > 1000) used = 1000
    share = (t > 0) ? f / t : 1
    st = "ok"
    if (share < 0.15 || gb < 20) st = "warn"
    if (share < 0.05 || gb < 5) st = "critical"
    print used, v, u, st
  }'
}

post() {
  local json=$1
  json=${json//\\/\\\\}; json=${json//\"/\\\"}; json=${json//$'\n'/}
  curl -q -s -m 5 -o /dev/null -w '%{http_code}' "$api" \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}' -H "Content-Type: application/json" \
    -d "{\"cellId\":\"{{CELL_ID}}\",\"svg\":{\"source\":\"$json\",\"duration\":1.2}}"
}

last=""
while true; do
  reading=$(read_disk)
  free=${reading%% *}; total=${reading##* }
  if [[ $free == <-> && $total == <-> ]]; then
    read used value unit state <<< "$(describe $free $total)"
    frame=$(disk_frame $used $value $unit $state)
  else
    frame=$(disk_frame 0 "—" GB rest)
  fi
  if [[ $frame != $last ]]; then
    if [[ $(post "$frame") == 200 ]]; then
      last=$frame
    else
      sleep 10
      continue
    fi
  fi
  sleep 60
done
