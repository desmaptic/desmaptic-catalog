#!/bin/zsh
# Xcode › Build Status: how the last build, run, test or clean started from Desmaptic went (2×1 SVG face).
#
# The Build, Run, Test and Clean buttons of the Xcode page start the action with Xcode's own AppleScript and
# note it in $DESMAPTIC_STORAGE/gallery/xcode/last-action (scheme/action.zsh); this loop follows that action through
# the same AppleScript ("last scheme action result" of the project) until it ends. Xcode reports only the
# actions it was asked to start this way: a ⌘B pressed in Xcode never shows here, and the face does not pretend
# it does.
#
# The macOS question whether the agent may control Xcode comes up on the first tap of one of those buttons —
# right after the user asked for something from Xcode. This loop asks Xcode only about an action such a tap
# started, so by then the question has been answered and the loop never raises it itself. Off screen it asks
# only about an action started while it runs (an older one waits until its page is on screen again), for at
# most 30 minutes, and only to catch the moment the action ends.
#
# Every frame has the same 17 elements in the same order: the phone glides between them.
# `zsh startup.zsh --face <p|l> <state> <action> <spin step> [value] [scheme]` prints one frame (rest.svg,
# demo.svg and their landscape twins are made that way).
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
asker=0
trap '(( asker > 0 )) && kill $asker 2>/dev/null; exit 0' TERM INT HUP
zmodload zsh/datetime zsh/zselect || { print -u2 -- "build status: zsh modules datetime/zselect are missing"; exit 1 }
zmodload -F zsh/files b:zf_mkdir b:zf_mv

# MARK: - Face

# build_frame <p|l> <rest|run|ok|fail|cancel|error> <build|run|test|clean> <spin step> [value] [scheme]
# p = the 2×1 face (400×200), l = its 1×2 landscape twin (200×400). The dial — a ring around the action's
# glyph — sits in the middle at rest and moves aside for the value (time so far, time taken, or the number of
# errors) and the scheme. While the action runs a third of the ring turns a third of a turn a frame; when it
# ends the ring closes in the result's colour and a badge says how it went: ✓, ✕, ■ (stopped), ! (did not start).
build_frame() {
  emulate -L zsh
  export LC_ALL=C
  local layout=${1:-p} state=${2:-rest} act=${3:-build} k=${4:-0} value=${5:-—} scheme=${6:-—}
  [[ $layout == (p|l) ]] || layout=p
  [[ $state == (rest|run|ok|fail|cancel|error) ]] || state=rest
  [[ $act == (build|run|test|clean) ]] || act=build
  [[ $k == <-> ]] || k=0
  # Text for XML: no control characters, the scheme cut to what fits (counted in characters, not bytes),
  # then &, < and > escaped.
  local nv ns v
  () {
    local LC_ALL=en_US.UTF-8
    scheme=${scheme//[[:cntrl:]]/}
    (( ${#scheme} > 11 )) && scheme="${scheme[1,10]}…"
    nv=${#value} ns=${#scheme}
  }
  for v in value scheme; do
    : ${(P)v::=${${${(P)v}//&/&amp;}//</&lt;}}
    : ${(P)v::=${(P)v//>/&gt;}}
  done
  BS_VAL=$value BS_SCH=$scheme awk -v ly=$layout -v st=$state -v act=$act -v k=$k -v nv=$nv -v ns=$ns '
    function f(x) { return sprintf("%.2f", x) }
    BEGIN {
      val = ENVIRON["BS_VAL"]; sch = ENVIRON["BS_SCH"]
      C = 427.26                                # 2π · 68: the ring
      live = (st != "rest")
      d = (st == "run") ? 128.18 : C            # a third of the ring turns while the action runs, then it closes
      a = -90 + 120 * k                         # a third of a turn a frame, from 12 o’clock
      ah = a + 108                              # the bright head at the end of the turning third (fades where it is)
      if (ly == "p") { tx = live ? 0 : 100; ty = 0 } else { tx = 0; ty = live ? 22 : 100 }

      # rest: bloom colours and strength, ring gradient and opacities, glyph gradient; the states below change some
      bC = "#BF5AF2"; mC = "#5E5CE6"; bA = 0.16; bM = 0.05; bR = 84; r1 = "#BF5AF2"; r2 = "#64D2FF"; aO = 0.75; hO = 0.16; tO = 0.10
      hd = 0; bd = "#64D2FF"; bO = 0; bRr = 0; gO = 0.95; g1 = "#BF5AF2"; g2 = "#64D2FF"; vO = 0; sO = 0; vC = "#FFFFFF"
      if (st == "run")    { bC = "#5E5CE6"; mC = "#BF5AF2"; bA = 0.20; bM = 0.06; bR = 86; aO = 1; hO = 0.22; tO = 0.14; hd = 1; vO = 1; sO = 0.6 }
      if (st == "ok")     { bC = "#64D2FF"; bA = 0.16; r1 = "#64D2FF"; r2 = "#5E5CE6"; aO = 0.95; hO = 0.20; tO = 0.14; bO = 1; bRr = 24; vO = 1; sO = 0.6 }
      if (st == "fail")   { bC = "#FF375F"; mC = "#BF5AF2"; bA = 0.30; bM = 0.08; bR = 92; r1 = "#FF375F"; r2 = "#E0479E"; aO = 1; hO = 0.28; tO = 0.14; bd = "#FF375F"; bO = 1; bRr = 24; vO = 1; sO = 0.6; vC = "#FF7A96" }
      if (st == "cancel") { bC = "#8E8E93"; bA = 0.10; bM = 0.03; r1 = "#8E8E93"; r2 = "#8E8E93"; aO = 0.55; hO = 0.06; tO = 0.14; bd = "#8E8E93"; bO = 1; bRr = 24; gO = 0.55; g1 = "#8E8E93"; g2 = "#AEAEB2"; vO = 0.8; sO = 0.5 }
      if (st == "error")  { bC = "#FF375F"; mC = "#BF5AF2"; bA = 0.22; bM = 0.06; bR = 88; r1 = "#FF375F"; r2 = "#BF5AF2"; aO = 0.8; hO = 0.2; tO = 0.14; bd = "#FF375F"; bO = 1; bRr = 24; vO = 0.8; sO = 0.6 }
      o["build"] = 0; o["run"] = 0; o["test"] = 0; o["clean"] = 0; o[act] = gO
      m["ok"] = 0; m["fail"] = 0; m["cancel"] = 0; m["error"] = 0; if (st in m) m[st] = 1

      if (ly == "p") { vx = 214; vy = 84; sx = 216; sy = 146; anchor = "start"; W = 176 }
      else           { vx = 100; vy = 268; sx = 100; sy = 322; anchor = "middle"; W = 184 }
      vs = int(W / (0.6 * (nv < 1 ? 1 : nv))); if (vs > 60) vs = 60; if (vs < 30) vs = 30
      ss = int(W / (0.62 * (ns < 1 ? 1 : ns))); if (ss > 30) ss = 30; if (ss < 26) ss = 26

      printf "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 %d %d\"><defs>", (ly == "p") ? 400 : 200, (ly == "p") ? 200 : 400
      printf "<linearGradient id=\"ringG\" gradientUnits=\"userSpaceOnUse\" x1=\"32\" y1=\"0\" x2=\"168\" y2=\"0\"><stop offset=\"0\" stop-color=\"%s\"/><stop offset=\"1\" stop-color=\"%s\"/></linearGradient>", r1, r2
      printf "<linearGradient id=\"glyphG\" gradientUnits=\"userSpaceOnUse\" x1=\"64\" y1=\"0\" x2=\"136\" y2=\"0\"><stop offset=\"0\" stop-color=\"%s\"/><stop offset=\"1\" stop-color=\"%s\"/></linearGradient>", g1, g2
      printf "<radialGradient id=\"bloomG\"><stop offset=\"0\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"0.55\" stop-color=\"%s\" stop-opacity=\"%s\"/><stop offset=\"1\" stop-color=\"%s\" stop-opacity=\"0\"/></radialGradient>", bC, f(bA), mC, f(bM), mC
      printf "<radialGradient id=\"glowG\"><stop offset=\"0\" stop-color=\"#64D2FF\" stop-opacity=\"%s\"/><stop offset=\"0.4\" stop-color=\"#64D2FF\" stop-opacity=\"%s\"/><stop offset=\"1\" stop-color=\"#64D2FF\" stop-opacity=\"0\"/></radialGradient></defs>", f(0.6 * hd), f(0.24 * hd)
      printf "<g id=\"dial\" transform=\"translate(%d %d)\">", tx, ty
      printf "<circle id=\"bloom\" cx=\"100\" cy=\"100\" r=\"%d\" fill=\"url(#bloomG)\"/>", bR
      printf "<circle id=\"track\" cx=\"100\" cy=\"100\" r=\"68\" fill=\"none\" stroke=\"#FFFFFF\" stroke-opacity=\"%s\" stroke-width=\"8\"/>", f(tO)
      printf "<circle id=\"halo\" cx=\"100\" cy=\"100\" r=\"68\" fill=\"none\" stroke=\"url(#ringG)\" stroke-opacity=\"%s\" stroke-width=\"22\" stroke-linecap=\"round\" stroke-dasharray=\"%s %s\" transform=\"rotate(%s 100 100)\"/>", f(hO), f(d), f(C), f(a)
      printf "<circle id=\"arc\" cx=\"100\" cy=\"100\" r=\"68\" fill=\"none\" stroke=\"url(#ringG)\" stroke-opacity=\"%s\" stroke-width=\"9\" stroke-linecap=\"round\" stroke-dasharray=\"%s %s\" transform=\"rotate(%s 100 100)\"/>", f(aO), f(d), f(C), f(a)
      printf "<circle id=\"glow\" cx=\"168\" cy=\"100\" r=\"24\" fill=\"url(#glowG)\" transform=\"rotate(%s 100 100)\"/>", f(ah)
      printf "<circle id=\"head\" cx=\"168\" cy=\"100\" r=\"6.5\" fill=\"#FFFFFF\" fill-opacity=\"%s\" transform=\"rotate(%s 100 100)\"/>", f(hd), f(ah)
      glyph = "fill=\"none\" stroke=\"url(#glyphG)\" stroke-width=\"7\" stroke-linecap=\"round\" stroke-linejoin=\"round\""
      printf "<path id=\"hammer\" d=\"M 123 67 L 123 93 L 83 93 L 83 85 C 71 85 57 89 47 97 C 53 79 67 67 83 67 Z M 101 93 L 101 143\" %s stroke-opacity=\"%s\" transform=\"rotate(40 100 100)\"/>", glyph, f(o["build"])
      printf "<path id=\"play\" d=\"M 86 68 L 128 100 L 86 132 Z\" %s stroke-opacity=\"%s\"/>", glyph, f(o["run"])
      printf "<path id=\"diamond\" d=\"M 100 64 L 136 100 L 100 136 L 64 100 Z\" %s stroke-opacity=\"%s\"/>", glyph, f(o["test"])
      printf "<path id=\"sparkle\" d=\"M 100 62 Q 104 96 138 100 Q 104 104 100 138 Q 96 104 62 100 Q 96 96 100 62 Z\" %s stroke-opacity=\"%s\"/>", glyph, f(o["clean"])
      printf "<circle id=\"badge\" cx=\"148\" cy=\"148\" r=\"%d\" fill=\"%s\" fill-opacity=\"%s\"/>", bRr, bd, f(bO)
      printf "<path id=\"check\" d=\"M 137 148 L 145 156 L 159 140\" fill=\"none\" stroke=\"#1C1C1E\" stroke-opacity=\"%s\" stroke-width=\"5\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>", f(m["ok"])
      printf "<path id=\"cross\" d=\"M 140 140 L 156 156 M 156 140 L 140 156\" fill=\"none\" stroke=\"#FFFFFF\" stroke-opacity=\"%s\" stroke-width=\"5\" stroke-linecap=\"round\"/>", f(m["fail"])
      printf "<rect id=\"square\" x=\"141\" y=\"141\" width=\"14\" height=\"14\" rx=\"2\" fill=\"#1C1C1E\" fill-opacity=\"%s\"/>", f(m["cancel"])
      printf "<path id=\"bang\" d=\"M 148 136 L 148 150 M 148 158 L 148 158.5\" fill=\"none\" stroke=\"#FFFFFF\" stroke-opacity=\"%s\" stroke-width=\"5\" stroke-linecap=\"round\"/>", f(m["error"])
      printf "</g>"
      printf "<text id=\"value\" x=\"%d\" y=\"%d\" font-size=\"%d\" font-weight=\"600\" text-anchor=\"%s\" dominant-baseline=\"middle\" fill=\"%s\" fill-opacity=\"%s\">%s</text>", vx, vy, vs, anchor, vC, f(vO), val
      printf "<text id=\"scheme\" x=\"%d\" y=\"%d\" font-size=\"%d\" font-weight=\"600\" text-anchor=\"%s\" dominant-baseline=\"middle\" fill=\"#FFFFFF\" fill-opacity=\"%s\">%s</text>", sx, sy, ss, anchor, f(sO), sch
      printf "</svg>\n"
    }'
}

if [[ $1 == --face ]]; then
  shift
  build_frame "$@"
  exit 0
fi

# MARK: - Xcode

# Asks Xcode how the action of the project named $1 is going, and keeps asking every step — ¼ s ($3 = 0) or
# 1 s ($3 = 1) — for up to $2 steps, until it ends: one process covers 5 s instead of a process a question.
# Prints "<answer>\t<number>\t<steps waited>"; the answer is run | ok (number: warnings) | fail (errors plus
# failed tests) | cancel | error (Xcode could not start it) | gone (Xcode quit, the project was closed).
read -r -d '' ASK <<'OSA'
on run argv
	set wsName to item 1 of argv
	set steps to (item 2 of argv) as integer
	set slow to (item 3 of argv) is "1"
	repeat with i from 0 to steps
		set answer to my lookAt(wsName)
		if answer does not start with "run" or i = steps then return answer & tab & i
		if slow then
			delay 1
		else
			delay 0.25
		end if
	end repeat
end run

on lookAt(wsName)
	if not (application id "com.apple.dt.Xcode" is running) then return "gone" & tab & 0
	tell application id "com.apple.dt.Xcode"
		if not (exists workspace document wsName) then return "gone" & tab & 0
		set r to last scheme action result of workspace document wsName
		if r is missing value then return "gone" & tab & 0
		set s to status of r
		if s is succeeded then return "ok" & tab & (count build warnings of r)
		if s is failed then return "fail" & tab & ((count build errors of r) + (count test failures of r))
		if s is cancelled then return "cancel" & tab & 0
		if s is error occurred then return "error" & tab & 0
		return "run" & tab & 0
	end tell
end lookAt
OSA

# MARK: - Loop

api="http://127.0.0.1:9848/api"
cell="{{CELL_ID}}"
marker="$DESMAPTIC_STORAGE/gallery/xcode/last-action"   # action=, started=, scheme=, workspace= lines
dir="$DESMAPTIC_STORAGE/gallery/$cell"                  # seen: the last result, so a restart need not ask again
zf_mkdir -p "$dir" 2>/dev/null
began=$EPOCHREALTIME

nap() { zselect -t $1; return 0 }                     # hundredths of a second, without starting a process

# The action on record → m_action m_start m_scheme m_ws; 1 when there is none.
read_marker() {
  local line
  m_action="" m_start="" m_scheme="" m_ws=""
  [[ -r $marker ]] || return 1
  while IFS= read -r line; do
    case $line in
      action=*) m_action=${line#*=} ;;
      started=*) m_start=${line#*=} ;;
      scheme=*) m_scheme=${line#*=} ;;
      workspace=*) m_ws=${line#*=} ;;
    esac
  done < "$marker"
  [[ $m_action == (build|run|test|clean) && $m_start == <->.<-> && -n $m_ws ]]
}

# REPLY = seconds as the face writes them: 12 s, 1:05, 12 min, 3 h.
span() {
  local -i s=$(( $1 + 0.5 ))
  (( s < 1 )) && s=1
  if (( s < 60 )); then REPLY="$s s"
  elif (( s < 600 )); then REPLY="$(( s / 60 )):${(l:2::0:)$(( s % 60 ))}"
  elif (( s < 3600 )); then REPLY="$(( s / 60 )) min"
  else REPLY="$(( s / 3600 )) h"; fi
}

hidden=1   # until the phone says otherwise: an action older than this loop is asked about only on screen
post() {   # $1 portrait frame, $2 landscape frame, $3 glide seconds → 0 when the agent took it
  local p=$1 l=$2 out code body
  p=${p//\\/\\\\}; p=${p//\"/\\\"}; p=${p//$'\n'/}
  l=${l//\\/\\\\}; l=${l//\"/\\\"}; l=${l//$'\n'/}
  out=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/update-button" \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}' -H "Content-Type: application/json" \
    -d "{\"cellId\":\"$cell\",\"svg\":{\"source\":\"$p\",\"landscapeSource\":\"$l\",\"duration\":$3}}")
  code=${out##*$'\n'} body=${out%$'\n'*}
  if [[ $code != 200 ]]; then
    print -ru2 -- "build status: update-button answered ${code:-nothing}: ${body[1,300]}"
    return 1
  fi
  [[ ${body//[[:space:]]/} == *'"visible":false'* ]] && hidden=1 || hidden=0
  return 0
}

on_screen() {   # the phone shows this button (or is too old to say)
  local body
  body=$(curl -q -s -m 5 "$api/view" --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}') || return 1
  body=${(L)body//[[:space:]]/}
  [[ $body == *'"view":null'* || $body == *${(L)cell}* ]]
}

# What the face shows: state (rest, run, ok, fail, cancel, error; gone draws as rest), count (errors), ended
# (epoch) and exact (1 when the end was seen as it happened, so the time taken is true, else it shows "—").
state=rest count=0 ended=0 exact=0 tracked="" k=0 drawn="" said="" looked=0 asked_at=0 run_at=0
saved=""
[[ -r $dir/seen ]] && IFS= read -r saved < "$dir/seen"

save() {
  print -r -- "$tracked $state $count $ended $exact" > "$dir/seen.tmp" 2>/dev/null && zf_mv -f "$dir/seen.tmp" "$dir/seen" 2>/dev/null
}

stop_asking() { (( asker )) && { kill $asker 2>/dev/null; wait $asker 2>/dev/null }; asker=0 }

# May Xcode be asked now? Only about an action a button started, only while Xcode runs; off screen only about
# one started while this loop runs (see the top), and for at most 30 minutes.
may_ask() {
  (( ! hidden || (m_start > began && EPOCHREALTIME - m_start < 1800) )) || return 1
  if ! pgrep -xqU $UID Xcode; then   # pgrep sees every account's processes: -U keeps to this one's Xcode
    state=gone; save; return 1
  fi
}

# Takes the asker's answer.
take() {
  local word n waited
  IFS=$'\t' read -r word n waited <<< "$1"
  [[ $n == <-> ]] || n=0
  [[ $waited == <-> ]] || waited=0
  case $word in
    run)
      run_at=$EPOCHREALTIME
      return ;;
    ok|fail|cancel|error)
      state=$word count=$n ended=$EPOCHREALTIME exact=0
      if (( waited > 0 || EPOCHREALTIME - run_at < 3 )); then
        exact=1                               # seen running a moment ago: the end is now
      elif (( asked_at - m_start < 2 )); then
        exact=1 ended=$asked_at               # over before the first look, a second after the tap
      fi ;;
    gone)
      state=gone ;;
    *)
      # An AppleScript error: -1743 is "not allowed" (Privacy & Security → Automation), -1712 Xcode too busy
      # to answer in time (asked again); anything else, and the face goes back to rest until the next action.
      if [[ $1 != $said ]]; then
        said=$1
        if [[ $1 == *-1743* ]]; then
          print -ru2 -- "build status: the agent may not control Xcode — allow it in System Settings → Privacy & Security → Automation"
        else
          print -ru2 -- "build status: Xcode did not answer: ${1[1,200]}"
        fi
      fi
      [[ $1 == *-1712* ]] && return
      state=gone ;;
  esac
  save
}

fresh=0 posted_at=0
while true; do
  if read_marker; then
    if [[ $m_start != $tracked ]]; then
      # a new action, or the first look after a start: follow it, unless its result is already known
      stop_asking
      tracked=$m_start state=run count=0 ended=0 exact=0 run_at=0 fresh=1
      if [[ ${saved%% *} == $m_start ]]; then
        was=( ${=saved} )
        state=${was[2]:-run} count=${was[3]:-0} ended=${was[4]:-0} exact=${was[5]:-0}
      fi
    fi
  else
    stop_asking
    tracked="" state=rest m_action="" m_scheme=""
  fi

  if [[ $state == run ]]; then
    if (( hidden && EPOCHSECONDS - looked >= 3 )); then   # off screen: is the page back?
      looked=$EPOCHSECONDS
      on_screen && hidden=0 drawn=""
    fi
    if (( ! asker )) && may_ask; then
      (( slow = hidden || EPOCHREALTIME - m_start > 600 ))
      coproc { osascript -e "$ASK" "$m_ws" $(( slow ? 5 : 20 )) $slow 2>&1 }
      asker=$! asked_at=$EPOCHREALTIME
    fi
    if (( asker )); then
      # Waits for the answer: a moment for a new action (one that is over at once is then drawn over, not
      # first as running), then 2 s at a time — between them the face shows the time so far.
      t0=$EPOCHREALTIME
      if IFS= read -r -t $(( fresh ? 0.3 : 2 )) -p answer; then
        take "$answer"
        wait $asker 2>/dev/null; asker=0
      elif ! kill -0 $asker 2>/dev/null; then
        wait $asker 2>/dev/null; asker=0      # ended without a word: asked again next round
        (( EPOCHREALTIME - t0 < 1 )) && nap 100
      fi
    elif [[ $state == run ]]; then
      nap 200                                 # off screen and not to be asked now: look for the page again
    fi
  else
    nap 50                                    # the record is a file the buttons write: a look is almost free
  fi
  fresh=0

  # Draws when the face changes. The turning ring only while someone sees it, and a turn every 2 s at most.
  shown=$state
  [[ $shown == gone ]] && shown=rest
  value="—"
  case $shown in
    run) span $(( EPOCHREALTIME - m_start )); value=$REPLY ;;
    fail) if (( count > 0 )); then value=$count; elif (( exact )); then span $(( ended - m_start )); value=$REPLY; fi ;;
    ok|cancel) (( exact )) && { span $(( ended - m_start )); value=$REPLY } ;;
  esac
  # A frame of a running action after another one turns the ring on by a step; the end keeps the last step,
  # so the ring closes where it stands instead of turning.
  step=$k glide=1.2
  if [[ $shown == run && ${drawn%% *} == run ]]; then
    (( hidden || EPOCHREALTIME - posted_at < 1.8 )) && continue
    (( step = (k + 1) % 3 )); glide=1
  fi
  next="$shown ${m_action:-build} $step $value|${m_scheme:-—}"
  [[ $next == $drawn ]] && continue
  if post "$(build_frame p $shown ${m_action:-build} $step "$value" "${m_scheme:-—}")" \
          "$(build_frame l $shown ${m_action:-build} $step "$value" "${m_scheme:-—}")" $glide; then
    drawn=$next posted_at=$EPOCHREALTIME k=$step
  else
    nap 1000
  fi
done
