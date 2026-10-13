#!/bin/zsh
# Timer: a countdown ring with mm:ss that rings on the phone and the Mac at zero
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
sound_pid=""
trap '[[ -n $sound_pid ]] && kill $sound_pid 2>/dev/null; exit 0' TERM INT
zmodload zsh/datetime zsh/zselect || { print -u2 -- "timer: zsh modules datetime/zselect are missing"; exit 1 }

# ---- timer_frame: identical in startup.zsh, tap.zsh and hold.zsh ----
# timer_frame <rest|ready|running|paused|finished> <length, min> <remaining, ms>
timer_frame() {
  emulate -L zsh
  export LC_ALL=C
  local state=${1:-rest} len=${2:-25} rem=${3:-0}
  [[ $state == (rest|ready|running|paused|finished) ]] || state=rest
  [[ $len == (5|15|25|50) ]] || len=25
  [[ $rem == <-> ]] || rem=0

  # Every number and state colour comes from awk as "key value" pairs
  # (zsh float arithmetic would print 0.17999999999999999).
  local -A v
  v=( ${=$(awk -v st=$state -v len=$len -v rem=$rem '
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
      total = len * 60000
      if (rem > total) rem = total
      shown = int((rem + 999) / 1000)          # seconds on the face, rounded up: 25:00 … 0:01, then 0:00
      if (st == "ready") { rem = total; shown = len * 60 }
      if (st == "rest" || st == "finished") { rem = 0; shown = 0 }
      kv("txt", sprintf("%d:%02d", int(shown / 60), shown % 60))

      # the lit arc is the time left; while running it aims at the next second, which the 1.1 s linear glide reaches
      f = 0
      if (st == "ready")   f = 1
      if (st == "paused")  f = rem / total
      if (st == "running") f = (shown > 1 ? shown - 1 : 0) * 1000 / total
      if (f > 1) f = 1
      d = L * f; if (d > L - 0.3) d = L - 0.3  # keep the bead’s dash on the path
      num("off", L * (1 - f))                  # lit dash covers 0 … L·f
      num("pos", -d)                           # bead: a 0.1-long dash starting at L·f
      ang = -120 + 240 * f                     # glow: degrees clockwise from 12 o’clock
      # the glow rides the bead as two halves (left of 12 o’clock, right of it): a rotation glides the
      # shortest way, so one circle would cut through the bottom gap on a reset from 0:00 to the full ring
      num("angA", ang < 0 ? ang : 0); num("angB", ang > 0 ? ang : 0)
      wA = 0.5 - ang / 4; if (wA < 0) wA = 0; if (wA > 1) wA = 1
      num("wA", wA); num("wB", 1 - wA)
      x = 100 + 80 * sin(ang * 3.14159265 / 180)
      gc = spectrum((x - 24) / 152)            # glow colour = the arc colour under the bead

      # the last minute heats the bloom towards hot pink
      h = 0
      if (st == "running" && shown <= 60) h = (60 - shown) / 60

      # state:       bloom centre / mid colour and opacity, radius   glow r, opacity   halo width, opacity   lit, bead   value colour, opacity   play/pause glyph colour, opacity, shape
      if (st == "rest")     { bC = "#BF5AF2"; bA = 0.12; mC = "#5E5CE6"; bM = 0.04; bR = 82; gR = 28; gA = 0;    hW = 18; hO = 0;    lit = 0;    bead = 0;    vC = "#FFFFFF"; vO = 0;    cC = "#FFFFFF"; cO = 0;    play = 1 }
      if (st == "ready")    { bC = "#BF5AF2"; bA = 0.20; mC = "#5E5CE6"; bM = 0.07; bR = 86; gR = 28; gA = 0.55; hW = 18; hO = 0.45; lit = 1;    bead = 1;    vC = "#FFFFFF"; vO = 1;    cC = "#FFFFFF"; cO = 0.6;  play = 1 }
      if (st == "running")  { bC = mix("#BF5AF2", "#FF375F", h); bA = 0.20 + 0.22 * h; mC = mix("#5E5CE6", "#BF5AF2", h); bM = 0.07 + 0.05 * h; bR = 86 + 8 * h
                              gR = 28; gA = 0.55 + 0.25 * h; hW = 18; hO = 0.45; lit = 1; bead = 1; vC = "#FFFFFF"; vO = 1; cC = "#FFFFFF"; cO = 0.6; play = 0 }
      if (st == "paused")   { bC = "#BF5AF2"; bA = 0.10; mC = "#5E5CE6"; bM = 0.03; bR = 82; gR = 28; gA = 0.22; hW = 18; hO = 0.15; lit = 0.4;  bead = 0.55; vC = "#FFFFFF"; vO = 0.5;  cC = "#FFFFFF"; cO = 0.85; play = 1 }
      if (st == "finished") { bC = "#FF375F"; bA = 0.57; mC = "#BF5AF2"; bM = 0.16; bR = 98; gR = 32; gA = 0.95; hW = 22; hO = 0.60; lit = 1;    bead = 1;    vC = "#FF6B88"; vO = 1;    cC = "#FF7A96"; cO = 0.95; play = 1; gc = "#FF375F" }
      # track: a faint spectrum on the rest face, white while live, hot pink when the time is up
      if (st == "rest")     { split("#FF375F #BF5AF2 #5E5CE6 #64D2FF", tc, " "); split("0.30 0.30 0.30 0.30", to, " ") }
      if (st == "ready" || st == "running") { split("#FFFFFF #FFFFFF #FFFFFF #FFFFFF", tc, " "); split("0.18 0.18 0.18 0.18", to, " ") }
      if (st == "paused")   { split("#FFFFFF #FFFFFF #FFFFFF #FFFFFF", tc, " "); split("0.14 0.14 0.14 0.14", to, " ") }
      if (st == "finished") { split("#FF375F #FF375F #FF375F #FF375F", tc, " "); split("0.30 0.24 0.20 0.20", to, " ") }
      for (i = 1; i <= 4; i++) { kv("tc" i, tc[i]); kv("to" i, to[i]) }

      kv("gc", gc); kv("bC", bC); num("bA", bA); kv("mC", mC); num("bM", bM); num("bR", bR)
      kv("gR", gR); num("gA", gA); num("gM", 0.4 * gA); kv("hW", hW); num("hO", hO)
      num("lit", lit); num("litGlowO", 0.2 * lit); num("coreO", 0.45 * lit); num("bead", bead)
      kv("vC", vC); num("vO", vO); kv("cC", cC); num("cO", cO)
      num("tEO", st == "finished" ? 0 : 0.9)

      # play ▶ / pause ❚❚ as two four-point shapes, so one glides into the other
      if (play) kv("ctl", "M" pt(92, 128) "L" pt(102, 133.5) "L" pt(102, 144.5) "L" pt(92, 150) "ZM" pt(102, 133.5) "L" pt(112, 139) "L" pt(112, 139) "L" pt(102, 144.5) "Z")
      else      kv("ctl", "M" pt(89, 128) "L" pt(96, 128) "L" pt(96, 150) "L" pt(89, 150) "ZM" pt(104, 128) "L" pt(111, 128) "L" pt(111, 150) "L" pt(104, 150) "Z")

      # the big stopwatch is the rest face; when the timer wakes up it sinks to the bottom and fades out
      if (st == "rest") { k = 1;    cy = 106; wo = 0.75; ho = 1 }
      else              { k = 0.27; cy = 172; wo = 0;    ho = 0 }
      num("wcy", cy); num("wr", 30 * k); num("wsw", 5 * k)
      num("sy1", cy - 30 * k); num("sy2", cy - 37.5 * k)
      num("capX", 100 - 9 * k); num("capY", cy - 45 * k); num("capW", 18 * k); num("capH", 7.5 * k); num("capR", 3.75 * k)
      num("hy2", cy - 18 * k); num("hub", 4.5 * k)
      num("px1", 100 + 24.04 * k); num("py1", cy - 24.04 * k); num("px2", 100 + 28.28 * k); num("py2", cy - 28.28 * k)
      num("wo", wo); num("ho", ho)
    }')} )
  local value=$v[txt] vsize=60
  [[ $state == rest ]] && value="—"
  (( ${#value} >= 5 )) && vsize=52              # "25:00" clears the lit arc at 52
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
<line id=\"tickE\" x1=\"46.31\" y1=\"131\" x2=\"41.98\" y2=\"133.5\" stroke=\"#FF375F\" stroke-opacity=\"$v[tEO]\" stroke-width=\"3\" stroke-linecap=\"round\"/>\
<line id=\"tickF\" x1=\"153.69\" y1=\"131\" x2=\"158.02\" y2=\"133.5\" stroke=\"#64D2FF\" stroke-opacity=\"0.9\" stroke-width=\"3\" stroke-linecap=\"round\"/>\
<path id=\"litGlow\" $arc stroke=\"url(#spec)\" stroke-opacity=\"$v[litGlowO]\" stroke-width=\"22\" stroke-linecap=\"round\" stroke-dasharray=\"335.1 400\" stroke-dashoffset=\"$v[off]\"/>\
<path id=\"lit\" $arc stroke=\"url(#spec)\" stroke-opacity=\"$v[lit]\" stroke-width=\"9\" stroke-linecap=\"round\" stroke-dasharray=\"335.1 400\" stroke-dashoffset=\"$v[off]\"/>\
<path id=\"core\" $arc stroke=\"#FFFFFF\" stroke-opacity=\"$v[coreO]\" stroke-width=\"2.5\" stroke-linecap=\"round\" stroke-dasharray=\"335.1 400\" stroke-dashoffset=\"$v[off]\"/>\
<circle id=\"glowA\" cx=\"100\" cy=\"26\" r=\"$v[gR]\" fill=\"url(#glowG)\" fill-opacity=\"$v[wA]\" transform=\"rotate($v[angA] 100 100)\"/>\
<circle id=\"glowB\" cx=\"100\" cy=\"26\" r=\"$v[gR]\" fill=\"url(#glowG)\" fill-opacity=\"$v[wB]\" transform=\"rotate($v[angB] 100 100)\"/>\
<path id=\"halo\" $arc stroke=\"url(#spec)\" stroke-opacity=\"$v[hO]\" stroke-width=\"$v[hW]\" stroke-linecap=\"round\" stroke-dasharray=\"0.1 400\" stroke-dashoffset=\"$v[pos]\"/>\
<path id=\"bead\" $arc stroke=\"#FFFFFF\" stroke-opacity=\"$v[bead]\" stroke-width=\"12\" stroke-linecap=\"round\" stroke-dasharray=\"0.1 400\" stroke-dashoffset=\"$v[pos]\"/>\
<text id=\"value\" x=\"100\" y=\"97\" font-size=\"$vsize\" font-weight=\"600\" text-anchor=\"middle\" dominant-baseline=\"middle\" fill=\"$v[vC]\" fill-opacity=\"$v[vO]\">$value</text>\
<path id=\"ctl\" d=\"$v[ctl]\" fill=\"$v[cC]\" fill-opacity=\"$v[cO]\"/>\
<circle id=\"watch\" cx=\"100\" cy=\"$v[wcy]\" r=\"$v[wr]\" fill=\"none\" stroke=\"url(#watchG)\" stroke-opacity=\"$v[wo]\" stroke-width=\"$v[wsw]\"/>\
<line id=\"stem\" x1=\"100\" y1=\"$v[sy1]\" x2=\"100\" y2=\"$v[sy2]\" stroke=\"url(#watchG)\" stroke-opacity=\"$v[wo]\" stroke-width=\"$v[wsw]\" stroke-linecap=\"round\"/>\
<rect id=\"crown\" x=\"$v[capX]\" y=\"$v[capY]\" width=\"$v[capW]\" height=\"$v[capH]\" rx=\"$v[capR]\" fill=\"url(#watchG)\" fill-opacity=\"$v[wo]\"/>\
<line id=\"pusher\" x1=\"$v[px1]\" y1=\"$v[py1]\" x2=\"$v[px2]\" y2=\"$v[py2]\" stroke=\"url(#watchG)\" stroke-opacity=\"$v[wo]\" stroke-width=\"$v[wsw]\" stroke-linecap=\"round\"/>\
<line id=\"hand\" x1=\"100\" y1=\"$v[wcy]\" x2=\"100\" y2=\"$v[hy2]\" stroke=\"#FFFFFF\" stroke-opacity=\"$v[wo]\" stroke-width=\"$v[wsw]\" stroke-linecap=\"round\" transform=\"rotate(50 100 $v[wcy])\"/>\
<circle id=\"hub\" cx=\"100\" cy=\"$v[wcy]\" r=\"$v[hub]\" fill=\"#64D2FF\" fill-opacity=\"$v[ho]\"/>\
</svg>"
}

# ---- state and posting: identical in startup.zsh, tap.zsh and hold.zsh ----
cell="{{CELL_ID}}"
api="http://127.0.0.1:9848/api"
dir="${DESMAPTIC_STORAGE:-$HOME/Library/Application Support/Desmaptic/ScriptStorage}/gallery/$cell"
state_file="$dir/state"

# REPLY = now, epoch milliseconds (zsh/datetime, no process)
now_ms() { REPLY=$(( epochtime[1] * 1000 + epochtime[2] / 1000000 )) }

# The state file is one line: "<ready|running|paused|finished> <length, min> <remaining, ms> <due, epoch ms>".
# Parsed field by field (never sourced); anything unreadable is a fresh 25-minute timer.
read_state() {
  local line="" ; local -a f
  [[ -r $state_file ]] && IFS= read -r line < $state_file
  state_line=$line
  f=( ${=line} )
  st=ready len=25 rem=0 due=0
  [[ $f[1] == (ready|running|paused|finished) ]] && st=$f[1]
  [[ $f[2] == (5|15|25|50) ]] && len=$f[2]
  [[ $f[3] == <-> && ${#f[3]} -le 15 ]] && rem=$f[3]
  [[ $f[4] == <-> && ${#f[4]} -le 15 ]] && due=$f[4]
  [[ $st == running ]] && (( due == 0 )) && st=ready
  [[ $st == paused ]] && (( rem == 0 || rem > len * 60000 )) && st=ready
  [[ $st == ready ]] && rem=$(( len * 60000 ))
  return 0
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
  [[ $post_code == 200 ]] || print -u2 -- "timer: update-button answered ${post_code:-nothing}: ${${answer%$'\n'*}[1,300]}"
  return 0
}

# ---- the loop ----
# 0 when the button is on the phone's screen, or when nobody can tell (an older app).
on_screen() {
  local answer
  answer=$(curl -q -s -m 5 "$api/view" -H @/dev/fd/3 3<<< "Authorization: Bearer $DESMAPTIC_TOKEN") || return 0
  [[ $answer == *'"visibleCellIds"'* ]] || return 0
  [[ ${(L)answer} == *${(L)cell}* ]]
}

# The time ran out $1 ms ago: remember it, and ring unless that happened while the agent was away.
# Returns 1 only when the state cannot be written (the loop then slows down instead of spinning).
finish() {
  local line=""
  [[ -r $state_file ]] && IFS= read -r line < $state_file
  [[ $line == $state_line ]] || return 0                  # a tap got there first
  write_state "finished $len 0 0" || { print -u2 -- "timer: cannot write $state_file"; return 1 }
  (( $1 > 60000 )) && return 0
  local code
  code=$(curl -q -s -m 5 -o /dev/null -w '%{http_code}' "$api/notify" -H @/dev/fd/3 \
    -H "Content-Type: application/json" --data-binary @- \
    3<<< "Authorization: Bearer $DESMAPTIC_TOKEN" \
    <<< "{\"title\":\"⏱ $len:00\",\"body\":\"✓\",\"targets\":[\"phone\",\"mac\"],\"cellId\":\"$cell\"}")
  [[ $code == 200 ]] || print -u2 -- "timer: notify answered ${code:-nothing}"
  afplay /System/Library/Sounds/Glass.aiff &
  sound_pid=$!
}

last_key=""      # what the phone shows: "<state> <length> <seconds or ms>"
seen=1           # the button was on screen at the last post
look_at=0        # while hidden: when to ask /api/view again
retry_at=0       # after a failed post: when to try again
while true; do
  read_state
  now_ms; now=$REPLY
  if [[ $st == running ]]; then
    left=$(( due - now ))
    if (( left <= 0 )); then
      finish $(( -left )) || zselect -t 500
      continue
    fi
    face=$left
    key="running $len $(( (left + 999) / 1000 ))"
  else
    face=$rem
    key="$st $len $rem"
  fi

  # Hidden: no frames, only a look at the phone every 3 s (every second while the countdown runs,
  # so a page opened mid-run does not show a stale time for long).
  gap=3000
  [[ $st == running ]] && gap=1000
  if (( ! seen && now >= look_at )); then
    if on_screen; then seen=1; else look_at=$(( now + gap - 50 )); fi
  fi
  if (( seen && now >= retry_at )) && [[ $key != $last_key ]]; then
    frame=$(timer_frame $st $len $face)
    line=""
    [[ -r $state_file ]] && IFS= read -r line < $state_file
    if [[ $line == $state_line ]]; then                   # no tap changed the state while the frame was drawn
      duration=0.6 easing=easeInOut
      [[ -z $last_key ]] && duration=1.2                  # the stopwatch sinks out of the saved face
      [[ $st == running && $last_key == running\ * ]] && { duration=1.1; easing=linear }
      post "$frame" $duration $easing
      if [[ $post_code == 200 ]]; then
        last_key=$key
        seen=$post_seen
        (( seen )) || look_at=$(( now + gap - 50 ))
      else
        retry_at=$(( now + 10000 ))
      fi
    fi
    continue
  fi

  # Running: wake when the second on the face changes. Otherwise look at the state four times a second.
  nap=250
  if [[ $st == running ]]; then
    now_ms
    left=$(( due - REPLY ))
    nap=$(( left - ((left + 999) / 1000 - 1) * 1000 + 5 ))
    (( nap > 1005 )) && nap=1005
    (( nap < 10 )) && nap=10
  fi
  zselect -t $(( (nap + 9) / 10 ))
done
