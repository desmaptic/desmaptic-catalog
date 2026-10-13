#!/bin/zsh
# Stopwatch tap: start, pause or resume where it stopped, and draw it at once
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap '[[ -n $state_file ]] && rm -f -- "$state_file.$$"; exit 0' TERM INT
zmodload zsh/datetime || { print -u2 -- "stopwatch: zsh module datetime is missing"; exit 1 }

# ---- sw_frame: identical in startup.zsh, tap.zsh and hold.zsh ----
# sw_frame <rest|reset|running|paused> <elapsed, ms>
# running draws the second the face shows and aims the arc at the next one; paused draws the exact time.
sw_frame() {
  emulate -L zsh
  export LC_ALL=C
  local state=${1:-rest} ms=${2:-0}
  [[ $state == (rest|reset|running|paused) ]] || state=rest
  [[ $ms == <-> && ${#ms} -le 15 ]] || ms=0

  # Every number and state colour comes from awk as "key value" pairs
  # (zsh float arithmetic would print 0.17999999999999999).
  local -A v
  v=( ${=$(awk -v st=$state -v ms=$ms '
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
    function pt(x, y) { return sprintf("%.2f,%.2f", x, y) }
    BEGIN {
      L = 335.10                               # arc length: r 80 · 240° = 80 · 4π/3
      if (st == "rest" || st == "reset") ms = 0
      sec = int(ms / 1000)
      if (sec < 3600) txt = sprintf("%d:%02d", int(sec / 60), sec % 60)
      else            txt = sprintf("%d:%02d:%02d", int(sec / 3600), int(sec / 60) % 60, sec % 60)
      kv("txt", txt)

      # the lit arc is the second within the minute: it fills once a minute and flies back at the next one.
      # While running it aims at the next second, which the 1.1 s linear glide reaches as that second comes.
      f = 0
      if (st == "paused")  f = (ms % 60000) / 60000
      if (st == "running") f = (sec % 60 + 1) / 60
      if (f > 1) f = 1
      d = L * f; if (d > L - 0.3) d = L - 0.3  # keep the bead’s dash on the path
      num("off", L * (1 - f))                  # lit dash covers 0 … L·f
      num("pos", -d)                           # bead: a 0.1-long dash starting at L·f
      ang = -120 + 240 * f                     # glow: degrees clockwise from 12 o’clock
      # the glow rides the bead as two halves (left of 12 o’clock, right of it): a rotation glides the
      # shortest way, so one circle would cut through the bottom gap when the arc flies back to zero
      num("angA", ang < 0 ? ang : 0); num("angB", ang > 0 ? ang : 0)
      wA = 0.5 - ang / 4; if (wA < 0) wA = 0; if (wA > 1) wA = 1
      num("wA", wA); num("wB", 1 - wA)
      x = 100 + 80 * sin(ang * 3.14159265 / 180)
      gc = spectrum((x - 24) / 152)            # glow colour = the arc colour under the bead

      # state:       bloom centre / mid colour and opacity, radius   glow r, opacity   halo width, opacity   lit, bead   value opacity   play/pause glyph opacity, shape
      if (st == "rest")    { bC = "#BF5AF2"; bA = 0.12; mC = "#5E5CE6"; bM = 0.04; bR = 82; gR = 28; gA = 0;    hW = 18; hO = 0;    lit = 0;   bead = 0;    vO = 0;   cO = 0;    play = 1 }
      if (st == "reset")   { bC = "#BF5AF2"; bA = 0.16; mC = "#5E5CE6"; bM = 0.05; bR = 84; gR = 28; gA = 0.25; hW = 18; hO = 0.25; lit = 1;   bead = 1;    vO = 1;   cO = 0.6;  play = 1 }
      if (st == "running") { bC = "#BF5AF2"; bA = 0.20; mC = "#5E5CE6"; bM = 0.07; bR = 86; gR = 28; gA = 0.55; hW = 18; hO = 0.45; lit = 1;   bead = 1;    vO = 1;   cO = 0.6;  play = 0 }
      if (st == "paused")  { bC = "#BF5AF2"; bA = 0.10; mC = "#5E5CE6"; bM = 0.03; bR = 82; gR = 28; gA = 0.22; hW = 18; hO = 0.15; lit = 0.4; bead = 0.55; vO = 0.5; cO = 0.85; play = 1 }
      # track: a faint spectrum on the rest face, white while live, fainter while paused
      if (st == "rest")    { split("#FF375F #BF5AF2 #5E5CE6 #64D2FF", tc, " "); split("0.30 0.30 0.30 0.30", to, " ") }
      if (st == "reset" || st == "running") { split("#FFFFFF #FFFFFF #FFFFFF #FFFFFF", tc, " "); split("0.18 0.18 0.18 0.18", to, " ") }
      if (st == "paused")  { split("#FFFFFF #FFFFFF #FFFFFF #FFFFFF", tc, " "); split("0.14 0.14 0.14 0.14", to, " ") }
      for (i = 1; i <= 4; i++) { kv("tc" i, tc[i]); kv("to" i, to[i]) }

      kv("gc", gc); kv("bC", bC); num("bA", bA); kv("mC", mC); num("bM", bM); num("bR", bR)
      kv("gR", gR); num("gA", gA); num("gM", 0.4 * gA); kv("hW", hW); num("hO", hO)
      num("lit", lit); num("litGlowO", 0.2 * lit); num("coreO", 0.45 * lit); num("bead", bead)
      num("vO", vO); num("cO", cO)

      # play ▶ / pause ❚❚ as two four-point shapes, so one glides into the other
      if (play) kv("ctl", "M" pt(92, 128) "L" pt(102, 133.5) "L" pt(102, 144.5) "L" pt(92, 150) "ZM" pt(102, 133.5) "L" pt(112, 139) "L" pt(112, 139) "L" pt(102, 144.5) "Z")
      else      kv("ctl", "M" pt(89, 128) "L" pt(96, 128) "L" pt(96, 150) "L" pt(89, 150) "ZM" pt(104, 128) "L" pt(111, 128) "L" pt(111, 150) "L" pt(104, 150) "Z")

      # the big stopwatch (two pushers, a lit sweep inside) is the rest face; when the stopwatch wakes up
      # it sinks to the bottom and fades out
      if (st == "rest") { k = 1;    cy = 106; wo = 0.75; ho = 1 }
      else              { k = 0.27; cy = 172; wo = 0;    ho = 0 }
      num("wcy", cy); num("wr", 30 * k); num("wsw", 5 * k)
      num("sy1", cy - 30 * k); num("sy2", cy - 37.5 * k)
      num("capX", 100 - 9 * k); num("capY", cy - 45 * k); num("capW", 18 * k); num("capH", 7.5 * k); num("capR", 3.75 * k)
      num("rx1", 100 + 24.04 * k); num("lx1", 100 - 24.04 * k); num("py1", cy - 24.04 * k)
      num("rx2", 100 + 28.28 * k); num("lx2", 100 - 28.28 * k); num("py2", cy - 28.28 * k)
      kv("sweep", "M" pt(100, cy - 17 * k) "A" sprintf("%.2f,%.2f", 17 * k, 17 * k) ",0,0,1," pt(100 + 14.72 * k, cy + 8.5 * k))
      num("tipX", 100 + 14.72 * k); num("tipY", cy + 8.5 * k); num("tipR", 4.5 * k)
      num("wo", wo); num("ho", ho)
    }')} )
  local value=$v[txt] vsize=60
  [[ $state == rest ]] && value="—"
  case ${#value} in                           # the widest that stays inside the lit arc
    5) vsize=52 ;;                            # 25:00
    6|7) vsize=40 ;;                          # 1:25:00
    8) vsize=33 ;;                            # 12:25:00
    <9->) vsize=29 ;;                         # 100:25:00
  esac
  local arc='d="M 30.72 140 A 80 80 0 1 1 169.28 140" fill="none"'

  printf '%s\n' "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 200 200\">\
<defs>\
<linearGradient id=\"spec\" gradientUnits=\"userSpaceOnUse\" x1=\"24\" y1=\"0\" x2=\"176\" y2=\"0\">\
<stop offset=\"0\" stop-color=\"#FF375F\"/><stop offset=\"0.35\" stop-color=\"#BF5AF2\"/><stop offset=\"0.7\" stop-color=\"#5E5CE6\"/><stop offset=\"1\" stop-color=\"#64D2FF\"/>\
</linearGradient>\
<linearGradient id=\"trackG\" gradientUnits=\"userSpaceOnUse\" x1=\"24\" y1=\"0\" x2=\"176\" y2=\"0\">\
<stop offset=\"0\" stop-color=\"$v[tc1]\" stop-opacity=\"$v[to1]\"/><stop offset=\"0.35\" stop-color=\"$v[tc2]\" stop-opacity=\"$v[to2]\"/><stop offset=\"0.7\" stop-color=\"$v[tc3]\" stop-opacity=\"$v[to3]\"/><stop offset=\"1\" stop-color=\"$v[tc4]\" stop-opacity=\"$v[to4]\"/>\
</linearGradient>\
<linearGradient id=\"watchG\" gradientUnits=\"userSpaceOnUse\" x1=\"66\" y1=\"0\" x2=\"134\" y2=\"0\"><stop offset=\"0\" stop-color=\"#BF5AF2\"/><stop offset=\"1\" stop-color=\"#64D2FF\"/></linearGradient>\
<radialGradient id=\"bloomG\"><stop offset=\"0\" stop-color=\"$v[bC]\" stop-opacity=\"$v[bA]\"/><stop offset=\"0.55\" stop-color=\"$v[mC]\" stop-opacity=\"$v[bM]\"/><stop offset=\"1\" stop-color=\"$v[mC]\" stop-opacity=\"0\"/></radialGradient>\
<radialGradient id=\"glowG\"><stop offset=\"0\" stop-color=\"$v[gc]\" stop-opacity=\"$v[gA]\"/><stop offset=\"0.4\" stop-color=\"$v[gc]\" stop-opacity=\"$v[gM]\"/><stop offset=\"1\" stop-color=\"$v[gc]\" stop-opacity=\"0\"/></radialGradient>\
</defs>\
<circle id=\"bloom\" cx=\"100\" cy=\"100\" r=\"$v[bR]\" fill=\"url(#bloomG)\"/>\
<path id=\"track\" $arc stroke=\"url(#trackG)\" stroke-width=\"6\" stroke-linecap=\"round\"/>\
<path id=\"ticks\" d=\"M 100 38 L 100 33\" fill=\"none\" stroke=\"#FFFFFF\" stroke-opacity=\"0.3\" stroke-width=\"2.5\" stroke-linecap=\"round\"/>\
<line id=\"tickE\" x1=\"46.31\" y1=\"131\" x2=\"41.98\" y2=\"133.5\" stroke=\"#FF375F\" stroke-opacity=\"0.9\" stroke-width=\"3\" stroke-linecap=\"round\"/>\
<line id=\"tickF\" x1=\"153.69\" y1=\"131\" x2=\"158.02\" y2=\"133.5\" stroke=\"#64D2FF\" stroke-opacity=\"0.9\" stroke-width=\"3\" stroke-linecap=\"round\"/>\
<path id=\"litGlow\" $arc stroke=\"url(#spec)\" stroke-opacity=\"$v[litGlowO]\" stroke-width=\"22\" stroke-linecap=\"round\" stroke-dasharray=\"335.1 400\" stroke-dashoffset=\"$v[off]\"/>\
<path id=\"lit\" $arc stroke=\"url(#spec)\" stroke-opacity=\"$v[lit]\" stroke-width=\"9\" stroke-linecap=\"round\" stroke-dasharray=\"335.1 400\" stroke-dashoffset=\"$v[off]\"/>\
<path id=\"core\" $arc stroke=\"#FFFFFF\" stroke-opacity=\"$v[coreO]\" stroke-width=\"2.5\" stroke-linecap=\"round\" stroke-dasharray=\"335.1 400\" stroke-dashoffset=\"$v[off]\"/>\
<circle id=\"glowA\" cx=\"100\" cy=\"26\" r=\"$v[gR]\" fill=\"url(#glowG)\" fill-opacity=\"$v[wA]\" transform=\"rotate($v[angA] 100 100)\"/>\
<circle id=\"glowB\" cx=\"100\" cy=\"26\" r=\"$v[gR]\" fill=\"url(#glowG)\" fill-opacity=\"$v[wB]\" transform=\"rotate($v[angB] 100 100)\"/>\
<path id=\"halo\" $arc stroke=\"url(#spec)\" stroke-opacity=\"$v[hO]\" stroke-width=\"$v[hW]\" stroke-linecap=\"round\" stroke-dasharray=\"0.1 400\" stroke-dashoffset=\"$v[pos]\"/>\
<path id=\"bead\" $arc stroke=\"#FFFFFF\" stroke-opacity=\"$v[bead]\" stroke-width=\"12\" stroke-linecap=\"round\" stroke-dasharray=\"0.1 400\" stroke-dashoffset=\"$v[pos]\"/>\
<text id=\"value\" x=\"100\" y=\"97\" font-size=\"$vsize\" font-weight=\"600\" text-anchor=\"middle\" dominant-baseline=\"middle\" fill=\"#FFFFFF\" fill-opacity=\"$v[vO]\">$value</text>\
<path id=\"ctl\" d=\"$v[ctl]\" fill=\"#FFFFFF\" fill-opacity=\"$v[cO]\"/>\
<circle id=\"watch\" cx=\"100\" cy=\"$v[wcy]\" r=\"$v[wr]\" fill=\"none\" stroke=\"url(#watchG)\" stroke-opacity=\"$v[wo]\" stroke-width=\"$v[wsw]\"/>\
<line id=\"stem\" x1=\"100\" y1=\"$v[sy1]\" x2=\"100\" y2=\"$v[sy2]\" stroke=\"url(#watchG)\" stroke-opacity=\"$v[wo]\" stroke-width=\"$v[wsw]\" stroke-linecap=\"round\"/>\
<rect id=\"crown\" x=\"$v[capX]\" y=\"$v[capY]\" width=\"$v[capW]\" height=\"$v[capH]\" rx=\"$v[capR]\" fill=\"url(#watchG)\" fill-opacity=\"$v[wo]\"/>\
<line id=\"pushR\" x1=\"$v[rx1]\" y1=\"$v[py1]\" x2=\"$v[rx2]\" y2=\"$v[py2]\" stroke=\"url(#watchG)\" stroke-opacity=\"$v[wo]\" stroke-width=\"$v[wsw]\" stroke-linecap=\"round\"/>\
<line id=\"pushL\" x1=\"$v[lx1]\" y1=\"$v[py1]\" x2=\"$v[lx2]\" y2=\"$v[py2]\" stroke=\"url(#watchG)\" stroke-opacity=\"$v[wo]\" stroke-width=\"$v[wsw]\" stroke-linecap=\"round\"/>\
<path id=\"sweep\" d=\"$v[sweep]\" fill=\"none\" stroke=\"#FFFFFF\" stroke-opacity=\"$v[wo]\" stroke-width=\"$v[wsw]\" stroke-linecap=\"round\"/>\
<circle id=\"tip\" cx=\"$v[tipX]\" cy=\"$v[tipY]\" r=\"$v[tipR]\" fill=\"#64D2FF\" fill-opacity=\"$v[ho]\"/>\
</svg>"
}

# ---- state and posting: identical in startup.zsh, tap.zsh and hold.zsh ----
cell="{{CELL_ID}}"
api="http://127.0.0.1:9848/api"
dir="${DESMAPTIC_STORAGE:-$HOME/Library/Application Support/Desmaptic/ScriptStorage}/gallery/$cell"
state_file="$dir/state"

# REPLY = now, epoch milliseconds (zsh/datetime, no process)
now_ms() { REPLY=$(( epochtime[1] * 1000 + epochtime[2] / 1000000 )) }

# The state file is one line: "<reset|running|paused> <time counted before the last start, ms> <last start, epoch ms>".
# Parsed field by field (never sourced); anything unreadable is a stopwatch at zero.
read_state() {
  local line="" ; local -a f
  [[ -r $state_file ]] && IFS= read -r line < $state_file
  state_line=$line
  f=( ${=line} )
  st=reset acc=0 start=0
  [[ $f[1] == (reset|running|paused) ]] && st=$f[1]
  [[ $f[2] == <-> && ${#f[2]} -le 15 ]] && acc=$f[2]
  [[ $f[3] == <-> && ${#f[3]} -le 15 ]] && start=$f[3]
  [[ $st == running ]] && (( start == 0 )) && st=paused
  [[ $st == paused ]] && (( acc == 0 )) && st=reset
  [[ $st == reset ]] && acc=0 start=0
  return 0
}

# REPLY = the time on the stopwatch at $1 (epoch ms); a clock set back never makes it run backwards.
elapsed_at() {
  local run=0
  [[ $st == running ]] && run=$(( $1 - start ))
  (( run < 0 )) && run=0
  REPLY=$(( acc + run ))
}

# Replaces the state file in one step, so a reader never sees half a line.
write_state() {
  mkdir -p "$dir" || return 1
  print -r -- "$1" > "$state_file.$$" && mv -f "$state_file.$$" "$state_file"
}

# post <frame> <duration> <easing>: sets post_code and post_seen (0 when the button is not on screen).
# The token goes in through a descriptor, not the command line, where any user of the Mac could read it.
post() {
  local json=$1 answer
  json=${json//\\/\\\\}; json=${json//\"/\\\"}; json=${json//$'\n'/}
  answer=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/update-button" -H @/dev/fd/3 \
    -H "Content-Type: application/json" --data-binary @- \
    3<<< "Authorization: Bearer $DESMAPTIC_TOKEN" \
    <<< "{\"cellId\":\"$cell\",\"svg\":{\"source\":\"$json\",\"duration\":$2,\"easing\":\"$3\"}}")
  post_code=${answer##*$'\n'}
  post_seen=1
  [[ $answer == *'"visible":false'* ]] && post_seen=0
  [[ $post_code == 200 ]] || print -u2 -- "stopwatch: update-button answered ${post_code:-nothing}: ${${answer%$'\n'*}[1,300]}"
  return 0
}

# ---- tap ----
read_state
now_ms; now=$REPLY
elapsed_at $now; shown=$REPLY
if [[ $st == running ]]; then
  st=paused acc=$shown start=0
else
  st=running acc=$shown start=$now                        # from zero or from where it was paused
fi
write_state "$st $acc $start" || { print -u2 -- "stopwatch: cannot write $state_file"; exit 1 }
post "$(sw_frame $st $shown)" 0.5 easeInOut
exit 0
