#!/bin/zsh
# Keep Awake: shows until when the agent keeps the Mac awake for this button, on a neon gauge that empties toward that time
# (the tap asks the agent; the agent holds the Mac awake by itself, with or without the phone and this loop)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT HUP
zmodload zsh/datetime zsh/zselect || { print -u2 -- "keep-awake: zsh modules datetime/zselect are missing"; exit 1 }
zmodload -F zsh/files b:zf_mkdir b:zf_mv b:zf_rm || { print -u2 -- "keep-awake: zsh module files is missing"; exit 1 }

# ---- awake_frame: identical in startup.zsh and tap.zsh ----
# awake_frame <rest|off|on> <minutes left> <minutes asked> <deadline HH:MM>
# rest: the saved face, a big open eye. off: the eye closes and dims, the gauge is empty.
# on: the eye opens and sinks under the deadline; the gauge holds the share of the asked time still left,
# and over the last half hour the glow warms to pink.
awake_frame() {
  emulate -L zsh
  export LC_ALL=C
  local state=${1:-rest} left=${2:-0} asked=${3:-1} value=${4:-00:00}
  [[ $state == (rest|off|on) ]] || state=rest
  [[ $left == <-> && ${#left} -le 9 ]] || left=0
  [[ $asked == <1-> && ${#asked} -le 9 ]] || asked=1
  [[ $value == [0-9][0-9]:[0-9][0-9] ]] || value=00:00

  # Every number and colour comes from awk as "key value" pairs
  # (zsh float arithmetic would print 0.17999999999999999).
  local -A v
  v=( ${=$(awk -v st=$state -v m=$left -v a=$asked '
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
    function clamp(x) { return x < 0 ? 0 : (x > 1 ? 1 : x) }
    function kv(k, x) { printf "%s %s\n", k, x }
    function num(k, x) { printf "%s %.2f\n", k, x }
    BEGIN {
      L = 335.10                               # arc length: r 80 · 240° = 80 · 4π/3
      on = (st == "on") ? 1 : 0
      f = on ? clamp(m / a) : 0                # the share of the asked time still left; off and rest park everything at the start
      H = on ? clamp((30 - m) / 30) : 0        # the last half hour: the glow warms to hot pink
      d = L * f; if (d > L - 0.3) d = L - 0.3  # keep the bead’s dash on the path
      num("off", L * (1 - f))                  # lit dash covers 0 … L·f
      num("pos", -d)                           # bead: a 0.1-long dash starting at L·f
      ang = -120 + 240 * f                     # glow: degrees clockwise from 12 o’clock
      # the glow rides the bead as two halves (left of 12 o’clock, right of it): a rotation glides the
      # shortest way, so one circle would cut through the bottom gap when the gauge empties from full
      num("angA", ang < 0 ? ang : 0); num("angB", ang > 0 ? ang : 0)
      wA = clamp(0.5 - ang / 4); num("wA", wA); num("wB", 1 - wA)
      x = 100 + 80 * sin(ang * 3.14159265 / 180)
      gc = mix(spectrum((x - 24) / 152), "#FF375F", H)

      if (on) {
        bC = mix("#BF5AF2", "#FF375F", H); bA = lerp(0.20, 0.57, H); mC = mix("#5E5CE6", "#BF5AF2", H); bM = lerp(0.07, 0.16, H); bR = lerp(86, 98, H)
        gR = lerp(28, 32, H); gA = lerp(0.55, 0.95, H); hW = lerp(18, 22, H); hO = lerp(0.45, 0.60, H)
        g1 = mix("#64D2FF", "#FF8FA8", H); g2 = mix("#BF5AF2", "#FF375F", H); led = mix("#64D2FF", "#FF375F", H)
        split("0.20 0.20 0.24 0.30", hot, " ")
        for (i = 1; i <= 4; i++) { kv("tc" i, mix("#FFFFFF", "#FF375F", H)); num("to" i, lerp(0.18, hot[i], H)) }
      } else if (st == "off") {                # everything unlit: a dim closed eye over an empty white track
        bC = "#BF5AF2"; bA = 0.07; mC = "#5E5CE6"; bM = 0.02; bR = 80; gR = 28; gA = 0; hW = 18; hO = 0
        g1 = "#BF5AF2"; g2 = "#64D2FF"; led = "#64D2FF"
        for (i = 1; i <= 4; i++) { kv("tc" i, "#FFFFFF"); num("to" i, 0.14) }
      } else {                                 # rest: the family’s saved face, a faint spectrum track
        bC = "#BF5AF2"; bA = 0.12; mC = "#5E5CE6"; bM = 0.04; bR = 82; gR = 28; gA = 0; hW = 18; hO = 0
        g1 = "#BF5AF2"; g2 = "#64D2FF"; led = "#64D2FF"
        split("#64D2FF #5E5CE6 #BF5AF2 #FF375F", tc, " ")
        for (i = 1; i <= 4; i++) { kv("tc" i, tc[i]); num("to" i, 0.30) }
      }
      kv("gc", gc); kv("bC", bC); num("bA", bA); kv("mC", mC); num("bM", bM); num("bR", bR)
      num("gR", gR); num("gA", gA); num("gM", 0.4 * gA); num("hW", hW); num("hO", hO)
      num("lit", on); num("litGlowO", on * 0.2); num("coreO", on * 0.45)
      kv("g1", g1); kv("g2", g2); kv("led", led)
      # end ticks step aside when the bead sits on them; dim when off
      num("tLO", on ? 0.9 * clamp((f - 0.03) / 0.05) : (st == "off" ? 0.4 : 0.9))
      num("tRO", on ? 0.9 * clamp((0.97 - f) / 0.05) : (st == "off" ? 0.4 : 0.9))

      # the eye: big and open on the rest face, big, closed and dim when off; when switched on it opens,
      # sinks under the deadline and stays there as a small mark (drawn under the text, so the time fades in over it)
      if (on)              { cx = 100; cy = 142; k = 0.46; w = 3.2; o = 1; eo = 0.9;  po = 1; lo = 0 }
      else if (st == "off") { cx = 100; cy = 94;  k = 1;    w = 5;   o = 0; eo = 0.38; po = 0; lo = 0.38 }
      else                 { cx = 100; cy = 100; k = 1;    w = 5;   o = 1; eo = 0.75; po = 1; lo = 0 }
      yU = cy + k * (-28 * o + 12 * (1 - o))   # lid control points: open, the lids arch apart; closed, both sag into one curve
      yL = cy + k * ( 28 * o + 12 * (1 - o))
      kv("lid", sprintf("M_%.2f_%.2f_C_%.2f_%.2f_%.2f_%.2f_%.2f_%.2f_C_%.2f_%.2f_%.2f_%.2f_%.2f_%.2f_Z", \
        cx - 38 * k, cy, cx - 22 * k, yU, cx + 22 * k, yU, cx + 38 * k, cy, cx + 22 * k, yL, cx - 22 * k, yL, cx - 38 * k, cy))
      # lashes hang from the closed lid; open, they are folded into it and invisible
      s = 1 - o
      kv("lash", sprintf("M_%.2f_%.2f_L_%.2f_%.2f_M_%.2f_%.2f_L_%.2f_%.2f_M_%.2f_%.2f_L_%.2f_%.2f", \
        cx - 21.6 * k, cy + 6.75 * k, cx - (21.6 + 5 * s) * k, cy + (6.75 + 9 * s) * k, \
        cx, cy + 9 * k, cx, cy + (9 + 10 * s) * k, \
        cx + 21.6 * k, cy + 6.75 * k, cx + (21.6 + 5 * s) * k, cy + (6.75 + 9 * s) * k))
      # iris and pupil are clipped by the lids, so closing the eye covers them like a real lid
      num("ecx", cx); num("ecy", cy); num("ir", 14 * k); num("pr", 6 * k); num("ew", w)
      num("eo", eo); num("io", eo * o); num("po", po); num("lo", lo)
      num("gx1", cx - 40 * k); num("gx2", cx + 40 * k)
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
<linearGradient id=\"eyeG\" gradientUnits=\"userSpaceOnUse\" x1=\"$v[gx1]\" y1=\"0\" x2=\"$v[gx2]\" y2=\"0\"><stop offset=\"0\" stop-color=\"$v[g1]\"/><stop offset=\"1\" stop-color=\"$v[g2]\"/></linearGradient>\
<clipPath id=\"eyeC\"><path d=\"${v[lid]//_/ }\"/></clipPath>\
<radialGradient id=\"bloomG\"><stop offset=\"0\" stop-color=\"$v[bC]\" stop-opacity=\"$v[bA]\"/><stop offset=\"0.55\" stop-color=\"$v[mC]\" stop-opacity=\"$v[bM]\"/><stop offset=\"1\" stop-color=\"$v[mC]\" stop-opacity=\"0\"/></radialGradient>\
<radialGradient id=\"glowG\"><stop offset=\"0\" stop-color=\"$v[gc]\" stop-opacity=\"$v[gA]\"/><stop offset=\"0.4\" stop-color=\"$v[gc]\" stop-opacity=\"$v[gM]\"/><stop offset=\"1\" stop-color=\"$v[gc]\" stop-opacity=\"0\"/></radialGradient>\
</defs>\
<circle id=\"bloom\" cx=\"100\" cy=\"100\" r=\"$v[bR]\" fill=\"url(#bloomG)\"/>\
<path id=\"track\" $arc stroke=\"url(#trackG)\" stroke-width=\"6\" stroke-linecap=\"round\"/>\
<path id=\"ticks\" d=\"M 100 38 L 100 33\" fill=\"none\" stroke=\"#FFFFFF\" stroke-opacity=\"0.3\" stroke-width=\"2.5\" stroke-linecap=\"round\"/>\
<line id=\"tickL\" x1=\"46.31\" y1=\"131\" x2=\"41.98\" y2=\"133.5\" stroke=\"#64D2FF\" stroke-opacity=\"$v[tLO]\" stroke-width=\"3\" stroke-linecap=\"round\"/>\
<line id=\"tickR\" x1=\"153.69\" y1=\"131\" x2=\"158.02\" y2=\"133.5\" stroke=\"#FF375F\" stroke-opacity=\"$v[tRO]\" stroke-width=\"3\" stroke-linecap=\"round\"/>\
<path id=\"litGlow\" $arc stroke=\"url(#spec)\" stroke-opacity=\"$v[litGlowO]\" stroke-width=\"22\" stroke-linecap=\"round\" stroke-dasharray=\"335.1 400\" stroke-dashoffset=\"$v[off]\"/>\
<path id=\"lit\" $arc stroke=\"url(#spec)\" stroke-opacity=\"$v[lit]\" stroke-width=\"9\" stroke-linecap=\"round\" stroke-dasharray=\"335.1 400\" stroke-dashoffset=\"$v[off]\"/>\
<path id=\"core\" $arc stroke=\"#FFFFFF\" stroke-opacity=\"$v[coreO]\" stroke-width=\"2.5\" stroke-linecap=\"round\" stroke-dasharray=\"335.1 400\" stroke-dashoffset=\"$v[off]\"/>\
<circle id=\"glowA\" cx=\"100\" cy=\"26\" r=\"$v[gR]\" fill=\"url(#glowG)\" fill-opacity=\"$v[wA]\" transform=\"rotate($v[angA] 100 100)\"/>\
<circle id=\"glowB\" cx=\"100\" cy=\"26\" r=\"$v[gR]\" fill=\"url(#glowG)\" fill-opacity=\"$v[wB]\" transform=\"rotate($v[angB] 100 100)\"/>\
<path id=\"halo\" $arc stroke=\"url(#spec)\" stroke-opacity=\"$v[hO]\" stroke-width=\"$v[hW]\" stroke-linecap=\"round\" stroke-dasharray=\"0.1 400\" stroke-dashoffset=\"$v[pos]\"/>\
<path id=\"bead\" $arc stroke=\"#FFFFFF\" stroke-opacity=\"$v[lit]\" stroke-width=\"12\" stroke-linecap=\"round\" stroke-dasharray=\"0.1 400\" stroke-dashoffset=\"$v[pos]\"/>\
<path id=\"lash\" d=\"${v[lash]//_/ }\" fill=\"none\" stroke=\"url(#eyeG)\" stroke-opacity=\"$v[lo]\" stroke-width=\"$v[ew]\" stroke-linecap=\"round\"/>\
<path id=\"lid\" d=\"${v[lid]//_/ }\" fill=\"none\" stroke=\"url(#eyeG)\" stroke-opacity=\"$v[eo]\" stroke-width=\"$v[ew]\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>\
<circle id=\"iris\" cx=\"$v[ecx]\" cy=\"$v[ecy]\" r=\"$v[ir]\" fill=\"none\" stroke=\"url(#eyeG)\" stroke-opacity=\"$v[io]\" stroke-width=\"$v[ew]\" clip-path=\"url(#eyeC)\"/>\
<circle id=\"pupil\" cx=\"$v[ecx]\" cy=\"$v[ecy]\" r=\"$v[pr]\" fill=\"$v[led]\" fill-opacity=\"$v[po]\" clip-path=\"url(#eyeC)\"/>\
<text id=\"value\" x=\"100\" y=\"97\" font-size=\"48\" font-weight=\"600\" text-anchor=\"middle\" dominant-baseline=\"middle\" fill=\"#FFFFFF\" fill-opacity=\"$v[lit]\">$value</text>\
</svg>"
}

# ---- the agent and posting: identical in startup.zsh and tap.zsh ----
cell="{{CELL_ID}}"
api="http://127.0.0.1:9848/api"
dir="${DESMAPTIC_STORAGE:-$HOME/Library/Application Support/Desmaptic/ScriptStorage}/gallery/$cell"
asked_file="$dir/asked"   # "<deadline> <minutes asked>" (epoch s): what the full gauge stands for
poke_file="$dir/poke"     # left by a tap: the loop asks the agent again at once

# Replaces a file in one step, so a reader never sees half a line: put_file <path> <line>
put_file() {
  zf_mkdir -p "$dir" 2>/dev/null
  print -r -- "$2" > "$1.$$" && zf_mv -f "$1.$$" "$1"
}

# awake [<json>]: GET /api/keep-awake, or POST the json there; sets awake_code and awake_body, fails unless 200.
# The token goes in through a descriptor, not the command line, where any user of the Mac could read it.
awake() {
  local answer
  if (( $# )); then
    answer=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/keep-awake" -H @/dev/fd/3 \
      -H "Content-Type: application/json" --data-binary @- \
      3<<< "Authorization: Bearer $DESMAPTIC_TOKEN" <<< "$1")
  else
    answer=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/keep-awake" -H @/dev/fd/3 \
      3<<< "Authorization: Bearer $DESMAPTIC_TOKEN")
  fi
  awake_code=${answer##*$'\n'}
  awake_body=${answer%$'\n'*}
  [[ $awake_code == 200 ]]
}

# REPLY = this button's deadline (epoch s) in the agent's last answer, empty when it asks for nothing.
# Another button may keep the Mac awake as well: the face shows only this button's own request.
own_deadline() {
  emulate -L zsh
  setopt extended_glob
  local -a match mbegin mend
  REPLY=""
  [[ ${(U)awake_body} == (#b)*'"CELLID":"'${(U)cell}'","UNTIL":"'[^\"]#'","UNTILEPOCH":'([0-9]##)[,\}]* ]] && REPLY=$match[1]
  (( ${#REPLY} <= 12 )) || REPLY=""
}

# REPLY = the minutes asked for this deadline, from asked_file. A deadline the file does not know
# (the file is gone, or something else asked for this button) counts from now, and is written down.
asked_for() {
  local line="" ; local -a f
  [[ -r $asked_file ]] && IFS= read -r line < $asked_file
  f=( ${=line} )
  if [[ $f[1] == $1 && $f[2] == <1-> && ${#f[2]} -le 6 ]]; then REPLY=$f[2]; return 0; fi
  REPLY=$(( ($1 - EPOCHSECONDS + 59) / 60 ))
  (( REPLY > 0 )) || REPLY=1
  put_file $asked_file "$1 $REPLY" || print -u2 -- "keep-awake: cannot write $asked_file"
  return 0
}

# post <frame> <duration>: sets post_code and post_seen (0 when the button is not on screen).
post() {
  local json=$1 answer
  json=${json//\\/\\\\}; json=${json//\"/\\\"}; json=${json//$'\n'/}
  answer=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/update-button" -H @/dev/fd/3 \
    -H "Content-Type: application/json" --data-binary @- \
    3<<< "Authorization: Bearer $DESMAPTIC_TOKEN" \
    <<< "{\"cellId\":\"$cell\",\"svg\":{\"source\":\"$json\",\"duration\":$2,\"easing\":\"easeInOut\"}}")
  post_code=${answer##*$'\n'}
  post_seen=1
  [[ $answer == *'"visible":false'* ]] && post_seen=0
  [[ $post_code == 200 ]] || print -u2 -- "keep-awake: update-button answered ${post_code:-nothing}: ${${answer%$'\n'*}[1,300]}"
  return 0
}

# ---- the loop ----
# --face rest|demo prints the saved face or the Gallery's sample (the Mac at 10:48, asked for 3 hours at 10:30).
if (( $# )); then
  case "$1 $2" in
    "--face rest") awake_frame rest 0 1; exit 0 ;;
    "--face demo") awake_frame on 162 180 13:30; exit 0 ;;
  esac
  print -u2 -- "usage: startup.zsh [--face rest|demo]"
  exit 2
fi

# 0 when the button is on the phone's screen, or when nobody can tell (an older app).
on_screen() {
  local answer
  answer=$(curl -q -s -m 5 "$api/view" -H @/dev/fd/3 3<<< "Authorization: Bearer $DESMAPTIC_TOKEN") || return 0
  [[ $answer == *'"visibleCellIds"'* ]] || return 0
  [[ ${(L)answer} == *${(L)cell}* ]]
}

# The face follows the agent: every 30 s, and at once after a tap (the poke file); between the asks the gauge
# moves on by the clock. Stopping this loop (the phone went away) changes nothing on the Mac.
deadline=""      # this button's deadline at the last answer, epoch s
ask_at=0         # when to ask the agent again
failed=0         # the last ask failed (said once on stderr)
last_key=""      # what the phone shows: "off" or "on <deadline> <minutes left>"
seen=1           # the button was on screen at the last post
look_at=0        # while hidden: when to ask /api/view again
retry_at=0       # after a failed post: when to try again
while true; do
  now=$EPOCHSECONDS
  if [[ -e $poke_file ]] || (( now >= ask_at )); then
    zf_rm -f $poke_file 2>/dev/null
    if awake; then
      own_deadline
      deadline=$REPLY failed=0 ask_at=$(( now + 30 ))
    else
      (( failed )) || print -u2 -- "keep-awake: the agent answered ${awake_code:-nothing}: ${awake_body[1,300]}"
      failed=1 ask_at=$(( now + 10 ))
    fi
  fi

  if [[ -n $deadline ]] && (( deadline > now )); then
    left=$(( (deadline - now + 59) / 60 ))
    key="on $deadline $left"
  else
    key=off
  fi

  # Hidden: no frames, only a look at the phone every 3 s.
  if (( ! seen && now >= look_at )); then
    if on_screen; then seen=1; else look_at=$(( now + 3 )); fi
  fi
  if (( seen && now >= retry_at )) && [[ $key != "$last_key" ]]; then
    if [[ $key == on* ]]; then
      asked_for $deadline
      frame=$(awake_frame on $left $REPLY $(strftime %H:%M $deadline))
    else
      frame=$(awake_frame off 0 1)
    fi
    duration=1.0
    [[ ${last_key%% *} != ${key%% *} ]] && duration=0.8     # switched on or off: the eye opens or closes
    [[ -z $last_key ]] && duration=1.2                       # the first frame: out of the saved face
    post "$frame" $duration
    if [[ $post_code == 200 ]]; then
      last_key=$key
      seen=$post_seen
      (( seen )) || look_at=$(( now + 3 ))
    else
      retry_at=$(( now + 10 ))
    fi
    continue
  fi

  zselect -t 50    # look for a tap twice a second, without starting a process
done
