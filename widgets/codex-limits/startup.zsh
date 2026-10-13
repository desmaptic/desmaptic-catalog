# Codex Limits: how much of Codex's usage limits is used, and when each one resets (a 2×2 SVG face). The startup
# script is this file (item.json); the ChatGPT page places the same widget.
#
# The numbers come from Codex itself: the codex tool inside the ChatGPT app (a fixed list of places, the app's bundle
# first, never a PATH lookup) runs as `codex app-server` — JSON-RPC, one JSON message a line, on its stdin and stdout —
# and is asked `account/rateLimits/read`, the call ChatGPT itself makes (app.asar). Codex signs in, refreshes its
# tokens and talks to the network by itself: this script never sees a token, and only reads. It asks nothing else:
# no chats, threads, settings or account details.
#
# The app-server (about 100 MB) runs only while the phone shows the button: started when it comes on screen, stopped
# a minute after it goes off. Checked in ChatGPT 26.915.31945 (codex-cli 0.155.0-alpha.9.2, `codex app-server
# generate-json-schema`): after `initialize` and the `initialized` notification, the answer's `rateLimits` — or
# `rateLimitsByLimitId.codex` when there is one — has `primary` and `secondary` windows, each `usedPercent`,
# `windowDurationMins` and `resetsAt` (Unix seconds); a plan with one limit has `secondary` null (the Go plan: one
# 30-day window). Read again every 5 minutes, when Codex says the limits or the account changed
# (`account/rateLimits/updated`, `account/updated`, `account/login/completed`), just after a window resets, and on a
# tap (the tap leaves gallery/{{CELL_ID}}/refresh). An answer without limits (signed out, offline) stops the
# app-server, and a fresh one asks again in a minute, or in 5 without recent numbers. A frame goes out only when the
# face changes — the time left counts down by the minute below 10 hours, by the hour above.
#
# Every frame has the same 14 elements in the same order: the phone glides between them.
# `zsh startup.zsh --face <rest|off|wait|one|two> [used1 left1 win1 [used2 left2 win2]]` prints one frame (rest.svg
# and demo.svg are made that way).
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
srv=0
trap '(( srv > 0 )) && kill $srv 2>/dev/null; exit 0' TERM INT HUP
trap ':' PIPE                                   # a write to an app-server that just quit fails instead of ending the loop
                                                # (a handler, not ignore: children still get the default)

# MARK: - Face

# limits_frame <state> [used1 left1 win1 [used2 left2 win2]]: the 2×2 face (200×200). A dial on top — the outer ring the
# first window's use, the inner ring the second's, a >_ prompt in the middle — and under it a column for each window,
# under its own side of the dial: its length in its ring's colour ("5h", "7d", "30d": which limit this is), the percent
# used, and "↻" with the time until it resets. No words: the script does not know the phone's language. A ring turns
# amber from 80 % and pink from 90 %.
# rest: the dial alone, large (the face before the script runs); off: no codex, signed out or no answer ("—", grey);
# wait: Codex was asked and has not answered yet ("…"); one: a plan with one limit; two: with two.
limits_frame() {
  emulate -L zsh
  export LC_ALL=C
  local state=${1:-rest} u1=${2:-0} t1=${3:-0} m1=${4:-0} u2=${5:-0} t2=${6:-0} m2=${7:-0}
  [[ $state == (rest|off|wait|one|two) ]] || state=rest
  [[ $u1 == <-> ]] || u1=0
  [[ $u2 == <-> ]] || u2=0
  (( u1 > 100 )) && u1=100
  (( u2 > 100 )) && u2=100
  # the times come from left_text: digits, d, h, m and spaces, or "—" when Codex gave none
  [[ $t1 == "—" || ( -n $t1 && $t1 != *[^0-9dhm\ ]* ) ]] || t1=0
  [[ $t2 == "—" || ( -n $t2 && $t2 != *[^0-9dhm\ ]* ) ]] || t2=0
  [[ $m1 == <->[mhd] ]] || m1=0                 # a window's length from win_text: 5h, 7d, 30d; 0 = not known
  [[ $m2 == <->[mhd] ]] || m2=0
  awk -v st=$state -v u1=$u1 -v u2=$u2 -v t1="$t1" -v t2="$t2" -v m1=$m1 -v m2=$m2 '
    function f(x) { return sprintf("%.2f", x) }
    function clamp(x) { return x < 0 ? 0 : (x > 1 ? 1 : x) }
    function em(s,   i, c, w) {                 # the width of a text in ems: the system font, digits monospaced
      w = 0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "%" || c == "m") w += 0.90; else if (c == " ") w += 0.27; else if (c ~ /[\300-\377]/) w += 1; else if (c !~ /[\200-\277]/) w += 0.62
      }
      return w
    }
    function fit(s, size, width) { return (em(s) * size > width) ? width / em(s) : size }
    function text(id, x, y, size, weight, fill, op, val) {
      printf "<text id=\"%s\" x=\"%s\" y=\"%s\" font-size=\"%s\" font-weight=\"%d\" text-anchor=\"middle\" dominant-baseline=\"middle\" fill=\"%s\" fill-opacity=\"%s\">%s</text>", id, f(x), f(y), f(size), weight, fill, f(op), val
    }
    BEGIN {
      two = (st == "two"); one = (st == "one"); live = one || two
      C1 = 439.82; C2 = 301.59                  # 2π·70 and 2π·48: the rings, in the dial own 200×200 units
      a1 = live ? clamp(u1 / 100) * C1 : 0
      a2 = two ? clamp(u2 / 100) * C2 : 0
      # how full a window is: 0 calm, 1 from 80 % (amber), 2 from 90 % (pink)
      H1 = !live ? 0 : (u1 >= 90) ? 2 : (u1 >= 80) ? 1 : 0
      H2 = !two ? 0 : (u2 >= 90) ? 2 : (u2 >= 80) ? 1 : 0
      H = (H1 > H2) ? H1 : H2

      # rings: gradient ends, arc and halo opacity; tracks; tag colours; glyph gradient, opacity and scale; bloom
      split("#64D2FF #FFD60A #FF8FA8", s0, " "); split("#BF5AF2 #FF9F0A #FF375F", s1, " ")
      r10 = s0[H1 + 1]; r11 = s1[H1 + 1]; r20 = (H2 ? s0[H2 + 1] : "#8CFFD4"); r21 = (H2 ? s1[H2 + 1] : "#19C37D")
      split("#A8B0FF #FFC24D #FF7A96", kc, " ")
      k1 = kc[H1 + 1]; k2 = H2 ? kc[H2 + 1] : "#7EEBC0"
      o1 = live ? 1 : 0; h1 = live ? 0.22 + 0.06 * H1 : 0
      o2 = two ? 1 : 0;  h2 = two ? 0.20 + 0.06 * H2 : 0
      k1O = 0.12; k2O = (two || st == "rest") ? 0.12 : 0
      g0 = "#64D2FF"; g1 = "#BF5AF2"; gO = 0.95; gS = two || st == "rest" ? 1 : 1.3
      split("#5E5CE6 #FF9F0A #FF375F", bc, " "); split("0.14 0.18 0.26", ba, " ")
      bC = bc[H + 1]; bA = ba[H + 1]; bM = bA * 0.35
      if (st == "wait") { gO = 0.6; bA = 0.08; bM = 0.03 }
      if (st == "off")  { g0 = "#8E8E93"; g1 = "#AEAEB2"; gO = 0.5; bC = "#636366"; bA = 0; bM = 0; k1O = 0.10 }
      # the dial: large in the middle at rest, small on top otherwise
      if (st == "rest") { ds = 0.9; dy = 100 } else { ds = 0.56; dy = 58 }
      dx = 100 - 100 * ds; dy = dy - 100 * ds

      printf "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 200 200\"><defs>"
      printf "<linearGradient id=\"ring1G\" gradientUnits=\"userSpaceOnUse\" x1=\"30\" y1=\"30\" x2=\"170\" y2=\"170\"><stop offset=\"0\" stop-color=\"%s\"/><stop offset=\"1\" stop-color=\"%s\"/></linearGradient>", r10, r11
      printf "<linearGradient id=\"ring2G\" gradientUnits=\"userSpaceOnUse\" x1=\"52\" y1=\"52\" x2=\"148\" y2=\"148\"><stop offset=\"0\" stop-color=\"%s\"/><stop offset=\"1\" stop-color=\"%s\"/></linearGradient>", r20, r21
      printf "<linearGradient id=\"glyphG\" gradientUnits=\"userSpaceOnUse\" x1=\"78\" y1=\"0\" x2=\"122\" y2=\"0\"><stop offset=\"0\" stop-color=\"%s\"/><stop offset=\"1\" stop-color=\"%s\"/></linearGradient>", g0, g1
      printf "<radialGradient id=\"bloomG\"><stop offset=\"0\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"0.55\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"1\" stop-color=\"%s\" stop-opacity=\"0\"/></radialGradient></defs>", bC, f(bA), bC, f(bM), bC
      printf "<g id=\"dial\" transform=\"translate(%s %s) scale(%s)\">", f(dx), f(dy), f(ds)
      printf "<circle id=\"bloom\" cx=\"100\" cy=\"100\" r=\"90\" fill=\"url(#bloomG)\"/>"
      printf "<circle id=\"track1\" cx=\"100\" cy=\"100\" r=\"70\" fill=\"none\" stroke=\"#FFFFFF\" stroke-opacity=\"%s\" stroke-width=\"11\"/>", f(k1O)
      printf "<circle id=\"halo1\" cx=\"100\" cy=\"100\" r=\"70\" fill=\"none\" stroke=\"url(#ring1G)\" stroke-opacity=\"%s\" stroke-width=\"22\" stroke-linecap=\"round\" stroke-dasharray=\"%s %s\" transform=\"rotate(-90 100 100)\"/>", f(h1), f(a1), f(C1)
      printf "<circle id=\"arc1\" cx=\"100\" cy=\"100\" r=\"70\" fill=\"none\" stroke=\"url(#ring1G)\" stroke-opacity=\"%s\" stroke-width=\"11\" stroke-linecap=\"round\" stroke-dasharray=\"%s %s\" transform=\"rotate(-90 100 100)\"/>", f(o1), f(a1), f(C1)
      printf "<circle id=\"track2\" cx=\"100\" cy=\"100\" r=\"48\" fill=\"none\" stroke=\"#FFFFFF\" stroke-opacity=\"%s\" stroke-width=\"9\"/>", f(k2O)
      printf "<circle id=\"halo2\" cx=\"100\" cy=\"100\" r=\"48\" fill=\"none\" stroke=\"url(#ring2G)\" stroke-opacity=\"%s\" stroke-width=\"18\" stroke-linecap=\"round\" stroke-dasharray=\"%s %s\" transform=\"rotate(-90 100 100)\"/>", f(h2), f(a2), f(C2)
      printf "<circle id=\"arc2\" cx=\"100\" cy=\"100\" r=\"48\" fill=\"none\" stroke=\"url(#ring2G)\" stroke-opacity=\"%s\" stroke-width=\"9\" stroke-linecap=\"round\" stroke-dasharray=\"%s %s\" transform=\"rotate(-90 100 100)\"/>", f(o2), f(a2), f(C2)
      printf "<path id=\"prompt\" d=\"M 81 86 L 95 100 L 81 114 M 102 114 L 119 114\" fill=\"none\" stroke=\"url(#glyphG)\" stroke-opacity=\"%s\" stroke-width=\"7\" stroke-linecap=\"round\" stroke-linejoin=\"round\" transform=\"translate(100 100) scale(%s) translate(-100 -100)\"/>", f(gO), f(gS)
      printf "</g>"

      # the texts, in this order in every frame: tag1 used1 left1 tag2 used2 left2. Hidden ones keep a "0" (an empty
      # <text> would change the structure). A tag names its window by its length, in the colour of its ring.
      v1 = u1 "%"; v2 = u2 "%"; w1 = (t1 == "—") ? t1 : "↻" t1; w2 = (t2 == "—") ? t2 : "↻" t2; g1 = m1; g2 = m2
      p1O = 0; l1O = 0; p2O = 0; l2O = 0; q1O = 0; q2O = 0
      p1C = "#FFFFFF"; p2C = "#FFFFFF"
      if (!live) { v1 = "0"; w1 = "0"; v2 = "0"; w2 = "0"; g1 = "0"; g2 = "0" }
      if (one) { v2 = "0"; w2 = "0"; g2 = "0" }
      if (st == "off")  { v1 = "—"; p1O = 0.55; p1C = "#AEAEB2" }
      if (st == "wait") { v1 = "…"; p1O = 0.55 }
      if (live) { p1O = 1; l1O = 0.72; q1O = (g1 == "0") ? 0 : 0.95; if (H1) p1C = k1 }
      if (two)  { p2O = 1; l2O = 0.72; q2O = (g2 == "0") ? 0 : 0.95; if (H2) p2C = k2 }
      if (two) {                                # a column under each side of the dial
        text("tag1", 52, 124, 20, 700, k1, q1O, g1)
        text("used1", 52, 152, fit(v1, 30, 80), 700, p1C, p1O, v1)
        text("left1", 52, 180, fit(w1, 18, 72), 600, "#FFFFFF", l1O, w1)
        text("tag2", 148, 124, 20, 700, k2, q2O, g2)
        text("used2", 148, 152, fit(v2, 30, 80), 700, p2C, p2O, v2)
        text("left2", 148, 180, fit(w2, 18, 72), 600, "#FFFFFF", l2O, w2)
      } else {                                  # one column in the middle; "—" or "…" alone
        y = one ? 154 : (st == "wait") ? 140 : 150    # "…" sits on the baseline: raised to the middle
        text("tag1", 100, 122, 22, 700, k1, q1O, g1)
        text("used1", 100, y, fit(v1, 42, 180), 700, p1C, p1O, v1)
        text("left1", 100, 183, fit(w1, 20, 160), 600, "#FFFFFF", l1O, w1)
        text("tag2", 148, 124, 20, 700, k2, 0, g2)
        text("used2", 148, 152, 30, 700, p2C, 0, v2)
        text("left2", 148, 180, 18, 600, "#FFFFFF", 0, w2)
      }
      printf "</svg>\n"
    }'
}

if [[ $1 == --face ]]; then
  shift
  limits_frame "$@"
  exit 0
fi

# MARK: - Codex

zmodload zsh/datetime zsh/zselect || { print -u2 -- "Codex limits: zsh modules datetime/zselect are missing"; exit 1 }
zmodload -F zsh/files b:zf_mkdir
[[ -n $DESMAPTIC_STORAGE ]] || { print -u2 -- "Codex limits: DESMAPTIC_STORAGE is not set"; exit 1 }

# REPLY = the codex tool: the one inside the ChatGPT app first (it is the one the app keeps up to date and signed in),
# then the Codex app's, in Applications and then in the home folder's Applications. 1 when there is none.
find_codex() {
  emulate -L zsh
  local c
  [[ $HOME == /?* ]] || return 1
  for c in /Applications/ChatGPT.app/Contents/Resources/codex \
           /Applications/Codex.app/Contents/Resources/codex \
           $HOME/Applications/ChatGPT.app/Contents/Resources/codex \
           $HOME/Applications/Codex.app/Contents/Resources/codex; do
    [[ -f $c && -x $c ]] && { REPLY=$c; return 0 }
  done
  return 1
}

# One answer of the app-server (a line of JSON on stdin) → one line: "limits <used1> <resets1> <mins1> <used2> <resets2>
# <mins2>" (a "-" for what the plan does not have; resets in Unix seconds, mins = the window's length in minutes), "none" when the answer has no window at all, "error" for an
# error or anything this cannot read. A small JSON reader: every value lands in V under its path ("result.rateLimits.
# primary.usedPercent"), then the codex bucket is picked — rateLimitsByLimitId.codex, else rateLimits, as ChatGPT does.
# A plan with a spend limit instead of windows (individualLimit: remainingPercent, resetsAt) shows that as its window.
read -r -d '' SUMMARY <<'AWK'
function put(v,   i, p) {
  p = ""
  for (i = 1; i <= d; i++) p = p (i > 1 ? "." : "") (t[i] == "o" ? k[i] : n[i])
  V[p] = v
}
function whole(p) {                               # a whole number at path p, or ""
  if (!(p in V) || V[p] !~ /^-?[0-9]+(\.[0-9]+)?$/) return ""
  return int(V[p])
}
function pct(x) { return x < 0 ? 0 : (x > 100 ? 100 : x) }
{
  s = $0; d = 0
  while (s != "") {
    c = substr(s, 1, 1)
    if (c == " " || c == "\t" || c == "\r") { s = substr(s, 2); continue }
    if (c == "{" || c == "[") { d++; t[d] = (c == "{") ? "o" : "a"; n[d] = 0; k[d] = ""; w[d] = (c == "{"); s = substr(s, 2); continue }
    if (c == "}" || c == "]") { d--; s = substr(s, 2); continue }
    if (c == ",") { if (t[d] == "o") w[d] = 1; else n[d]++; s = substr(s, 2); continue }
    if (c == ":") { w[d] = 0; s = substr(s, 2); continue }
    if (c == "\"") {
      if (!match(s, /^"([^"\\]|\\.)*"/)) { bad = 1; exit }
      v = substr(s, 2, RLENGTH - 2); s = substr(s, RLENGTH + 1)
      if (t[d] == "o" && w[d]) k[d] = v; else put(v)
      continue
    }
    if (match(s, /^-?[0-9][-+0-9.eE]*/) || match(s, /^(true|false|null)/)) { put(substr(s, 1, RLENGTH)); s = substr(s, RLENGTH + 1); continue }
    bad = 1; exit
  }
}
END {
  if (bad || ("error.code" in V) || ("error.message" in V)) { print "error"; exit }
  b = "result.rateLimits"
  for (p in V) if (index(p, "result.rateLimitsByLimitId.codex.") == 1) { b = "result.rateLimitsByLimitId.codex"; break }
  u1 = whole(b ".primary.usedPercent"); r1 = whole(b ".primary.resetsAt"); m1 = whole(b ".primary.windowDurationMins")
  u2 = whole(b ".secondary.usedPercent"); r2 = whole(b ".secondary.resetsAt"); m2 = whole(b ".secondary.windowDurationMins")
  if (u1 == "" && u2 != "") { u1 = u2; r1 = r2; m1 = m2; u2 = ""; r2 = ""; m2 = "" }
  if (u1 == "" && whole(b ".individualLimit.remainingPercent") != "") {
    u1 = 100 - whole(b ".individualLimit.remainingPercent"); r1 = whole(b ".individualLimit.resetsAt"); m1 = ""
  }
  if (u1 == "") { print "none"; exit }
  printf "limits %d %s %s %s %s %s\n", pct(u1), (r1 > 0 ? r1 : "-"), (m1 > 0 ? m1 : "-"), (u2 == "" ? "-" : pct(u2)), (u2 != "" && r2 > 0 ? r2 : "-"), (u2 != "" && m2 > 0 ? m2 : "-")
}
AWK

# REPLY = the time until a reset as the face writes it: 45m, 2h 10m (below 10 hours, by the minute, rounded up), 23h,
# 5d 3h (below 10 days), 23d; "—" when Codex gave no time.
left_text() {
  emulate -L zsh
  local s=$1 m
  if [[ $s != <-> ]]; then REPLY="—"; return; fi
  (( s -= EPOCHSECONDS ))
  (( s < 0 )) && s=0
  (( m = (s + 59) / 60 ))
  if (( m < 60 )); then REPLY="${m}m"
  elif (( m < 600 )); then (( m % 60 )) && REPLY="$(( m / 60 ))h $(( m % 60 ))m" || REPLY="$(( m / 60 ))h"
  elif (( s < 86400 )); then REPLY="$(( s < 36000 ? 10 : s / 3600 ))h"
  elif (( s < 864000 )); then (( s % 86400 / 3600 )) && REPLY="$(( s / 86400 ))d $(( s % 86400 / 3600 ))h" || REPLY="$(( s / 86400 ))d"
  else REPLY="$(( s / 86400 ))d"; fi
}

# REPLY = a window's length as its tag on the face: 5h, 7d, 30d (whole days, else whole hours, else minutes); "0"
# when Codex gave none (the tag is hidden).
win_text() {
  local m=$1
  if [[ $m != <-> ]] || (( m <= 0 )); then REPLY=0
  elif (( m % 1440 == 0 )); then REPLY="$(( m / 1440 ))d"
  elif (( m % 60 == 0 )); then REPLY="$(( m / 60 ))h"
  else REPLY="${m}m"; fi
}

# MARK: - The app-server

srv_out=-1 srv_in=-1 ready=0 started=0 pending=0 asked=0 next_id=2
delays=( 10 30 60 120 300 )                     # seconds before another start after 1, 2, 3… failures in a row
fails=0 retry_at=0 said=""

say() { [[ $1 != $said ]] && { said=$1; print -ru2 -- "Codex limits: $1" }; return 0 }

send() { print -r -u $srv_in -- "$1" 2>/dev/null }

stop_server() {
  local i
  (( srv > 0 )) || return 0
  kill $srv 2>/dev/null
  for i in {1..20}; do kill -0 $srv 2>/dev/null || break; zselect -t 10; done
  kill -0 $srv 2>/dev/null && kill -9 $srv 2>/dev/null
  wait $srv 2>/dev/null
  exec {srv_in}>&- {srv_out}<&-
  srv=0 ready=0 pending=0
}

# fail <why>: the app-server is stopped, and started again later — the longer, the more failures in a row.
fail() {
  say "$1"
  erred=1
  stop_server
  (( fails < $#delays )) && (( fails++ ))
  retry_at=$(( EPOCHSECONDS + delays[fails] ))
}

# Starts the app-server with the agent's token and storage path left out of its environment, under both names (the agent
# also sets each under its old name, as an alias): they are not Codex's.
# `initialize` goes out at once; its answer is awaited by the loop.
start_server() {
  if ! find_codex; then
    codex="" state=off
    say "no codex tool in ChatGPT.app or Codex.app"
    retry_at=$(( EPOCHSECONDS + 60 ))
    return 1
  fi
  codex=$REPLY
  coproc env -u DESMAPTIC_TOKEN -u DESMAPTIC_STORAGE -u DESKTAP_TOKEN -u DESKTAP_STORAGE "$codex" app-server 2>/dev/null
  srv=$!
  exec {srv_out}<&p {srv_in}>&p
  ready=0 pending=0 started=$EPOCHSECONDS
  send '{"id":1,"method":"initialize","params":{"clientInfo":{"name":"desmaptic","title":"Desmaptic","version":"1"},"capabilities":null}}' ||
    fail "the app-server did not start"
}

# rest_server <seconds>: after an answer without limits the app-server is stopped, and a new one asks again then. A new
# one reads the sign-in afresh (the user may sign in to ChatGPT meanwhile), and 100 MB do not wait around for nothing.
rest_server() {
  stop_server
  retry_at=$(( EPOCHSECONDS + $1 ))
}

# Asks for the limits, unless a question is already out.
ask() {
  (( ready && ! pending )) || return 0
  pending=$next_id asked=$EPOCHSECONDS
  (( next_id++ ))
  send "{\"id\":$pending,\"method\":\"account/rateLimits/read\",\"params\":{\"excludeResetCreditDetails\":true}}" ||
    fail "the app-server quit"
}

# soon <seconds>: the next question goes out within that many seconds of the last one (never more often).
soon() {
  local at=$(( asked + $1 ))
  (( at < EPOCHSECONDS )) && at=$EPOCHSECONDS
  (( due > at )) && due=$at
  return 0
}

# What Codex said last: state (live, off or ""), when (got), the windows (u1 r1 m1 u2 r2 m2: used, resets, length);
# erred: the last question brought no numbers (an error, no answer, the app-server quit).
state="" got=0 u1=0 r1=- m1=- u2=- r2=- m2=- due=0 erred=0

# handle <line>: one message from the app-server. An answer is {"id":N,"result":…} — or {"error":{…},"id":N}: codex
# writes an error's id last (checked: an unknown method and a bad parameter, before initialize). A request of the
# app-server's own ({"id":N,"method":…}) is not an answer.
handle() {
  local line=$1 id kind method answer
  local -a f
  if [[ $line =~ '^\{"id":([0-9]+),"result":' ]]; then
    id=$match[1] kind=result
  elif [[ $line =~ '^\{"error":.*,"id":([0-9]+)\}$' ]]; then
    id=$match[1] kind=error
  fi
  if [[ -n $kind ]]; then
    if (( id == 1 )); then
      if [[ $kind == error ]]; then fail "the app-server refused to start"; return 0; fi
      send '{"method":"initialized"}'
      ready=1 due=$EPOCHSECONDS
    elif (( id == pending )); then
      pending=0
      answer=error
      [[ $kind == result ]] && answer=$(print -r -- "$line" | awk "$SUMMARY")
      f=( ${=answer} )
      if [[ $f[1] == limits && $#f == 7 ]]; then
        state=live got=$EPOCHSECONDS u1=$f[2] r1=$f[3] m1=$f[4] u2=$f[5] r2=$f[6] m2=$f[7] fails=0 said="" erred=0
        due=$(( EPOCHSECONDS + 300 ))
        # a window that resets before then: asked again just after
        [[ $r1 == <-> ]] && (( r1 > EPOCHSECONDS && r1 + 15 < due )) && due=$(( r1 + 15 ))
        [[ $r2 == <-> ]] && (( r2 > EPOCHSECONDS && r2 + 15 < due )) && due=$(( r2 + 15 ))
      elif [[ $f[1] == none ]]; then
        state=off
        say "Codex has no limits to tell for this account"
        rest_server 300
      else
        # signed out, or Codex could not reach its server: what it said before stays while it is fresh, and it is
        # asked again in a minute then; without it, "—" and every 5 minutes
        say "Codex did not tell the limits (signed out, or offline?)"
        erred=1
        if [[ $state == live ]] && (( EPOCHSECONDS - got < 960 )); then
          rest_server 60
        else
          state=off
          rest_server 300
        fi
      fi
    fi
    return 0
  fi
  [[ $line == *'"method":"'* ]] || return 0
  method=${line#*\"method\":\"}
  method=${method%%\"*}
  case $method in
    account/rateLimits/updated) soon 30 ;;
    account/updated|account/login/completed) soon 5 ;;
  esac
}

# Reads what the app-server wrote; its output ending means it quit.
drain() {
  local line
  while (( srv > 0 )) && zselect -t 0 -r $srv_out; do
    if ! IFS= read -r -u $srv_out line; then
      fail "the app-server quit"
      return
    fi
    handle "$line"
  done
}

# MARK: - Loop

api="http://127.0.0.1:9848/api"
cell="{{CELL_ID}}"
dir="$DESMAPTIC_STORAGE/gallery/$cell"            # refresh: the time of the last tap, which asks for a fresh read
zf_mkdir -p "$dir" 2>/dev/null
linger=60                                       # seconds the app-server outlives the button leaving the screen

on_screen() {   # the phone shows this button (or is too old to say: unknown counts as shown, never rest on a guess)
  local out code body
  out=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/view" --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}') || return 1
  code=${out##*$'\n'}
  [[ $code == 200 ]] || return 0                 # an agent without /api/view (older, on another Mac): shown
  body=${(L)${out%$'\n'*}//[[:space:]]/}
  [[ $body == *'"view":null'* || $body == *${(L)cell}* ]]
}

post() {   # $1 the frame → 0 when the agent took it
  local p=$1 out code
  p=${p//\\/\\\\}; p=${p//\"/\\\"}; p=${p//$'\n'/}
  out=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/update-button" \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}' -H "Content-Type: application/json" \
    -d "{\"cellId\":\"$cell\",\"svg\":{\"source\":\"$p\",\"duration\":0.8}}")
  code=${out##*$'\n'}
  [[ $code == 200 ]] && return 0
  print -ru2 -- "Codex limits: update-button answered ${code:-nothing}: ${${out%$'\n'*}[1,300]}"
  return 1
}

# REPLY = the face as limits_frame arguments. What Codex said is shown for 16 minutes (three missed reads); after that,
# or with no answer, "…" while the app-server is starting or asked and nothing went wrong since the last numbers, "—"
# otherwise (no "…" flash each time a failing read is tried again).
face_now() {
  local a b wa wb
  if [[ $state == live ]] && (( EPOCHSECONDS - got < 960 )); then
    left_text $r1; a=$REPLY
    win_text $m1; wa=$REPLY
    if [[ $u2 == <-> ]]; then
      left_text $r2; b=$REPLY
      win_text $m2; wb=$REPLY
      REPLY="two $u1 ${a// /_} $wa $u2 ${b// /_} $wb"
    else
      REPLY="one $u1 ${a// /_} $wa"
    fi
  elif [[ $state != off ]] && (( srv > 0 && ! erred )); then
    REPLY=wait
  else
    REPLY=off
  fi
}

hidden=1 looked=0 seen=0 shown="" poked=0 post_at=0
[[ -f $dir/refresh ]] && IFS= read -r poked < "$dir/refresh" 2>/dev/null
[[ $poked == <-> ]] || poked=0
while true; do
  now=$EPOCHSECONDS
  if (( now - looked >= (hidden ? 3 : 5) )); then   # is the button on screen? The phone is asked every few seconds.
    looked=$now
    on_screen && hidden=0 || hidden=1
  fi
  (( hidden )) || seen=$now

  poke=""
  [[ -f $dir/refresh ]] && IFS= read -r poke < "$dir/refresh" 2>/dev/null
  if [[ $poke == <-> ]] && (( poke > poked )); then   # a tap: a fresh read now (5 s after the last at the soonest)
    poked=$poke fails=0 retry_at=0
    soon 5
  fi

  if (( hidden )); then
    (( srv > 0 && now - seen >= linger )) && stop_server
  else
    (( srv == 0 && now >= retry_at )) && start_server
    if (( srv > 0 )); then
      if (( ! ready && now - started > 20 )); then fail "the app-server did not answer"
      elif (( pending && now - asked > 20 )); then fail "no answer about the limits"
      elif (( ready && ! pending && now >= due )); then ask; fi
    fi
    face_now
    if [[ $REPLY != "$shown" ]] && (( now >= post_at )); then
      f=( ${=REPLY} )
      if post "$(limits_frame ${f[1]} ${f[2]} "${f[3]//_/ }" ${f[4]} ${f[5]} "${f[6]//_/ }" ${f[7]})"; then
        shown=$REPLY
      else
        post_at=$(( now + 10 ))                 # the agent is busy or restarting: try again in 10 s
      fi
    fi
  fi

  if (( srv > 0 )) && zselect -t 100 -r $srv_out; then
    drain
  elif (( srv == 0 )); then
    zselect -t 100
  fi
done
