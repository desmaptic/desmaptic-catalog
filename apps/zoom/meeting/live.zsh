# Zoom › Microphone, Video and Share Screen, the live state: Microphone is green while Zoom hears you and red with a line
# through while you are muted; Video is green while your video is on and red with a line through while it is off; Share
# Screen is green while you share. Outside a meeting, while Zoom is closed and whenever nobody can tell, each keeps its
# own grey look.
# The state comes from Zoom's Meeting menu, read through the Accessibility API ($zoom_ax state, meeting/ax.zsh): no Apple
# event, so no Automation question, and never Zoom launched. It is read only while the button is on the phone's screen:
# every $period seconds in a meeting, every $idle_period seconds while Zoom runs without one, and only a process check
# while Zoom is closed; every half second for a moment after a tap of any of the page's meeting buttons (press.zsh leaves
# the time in $DESMAPTIC_STORAGE/gallery/zoom/poke). One read serves the three buttons: it is left, with the time it was
# asked, in $DESMAPTIC_STORAGE/gallery/zoom/state, and a button that finds a fresh one does not ask again.
# Every button's startup script is one line that names what it shows, then ax.zsh, then this file (app.json):
#   "mode=mic\n@file:meeting/ax.zsh\n@file:meeting/live.zsh"   — mic, camera or share.
emulate -R zsh
[[ $mode == (mic|camera|share) ]] || { print -u2 -- "Zoom: unknown mode \"$mode\""; exit 1 }
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
zmodload zsh/datetime zsh/zselect || { print -u2 -- "Zoom $mode: zsh modules datetime/zselect are missing"; exit 1 }
zmodload -F zsh/files b:zf_mkdir b:zf_mv || { print -u2 -- "Zoom $mode: zsh module files is missing"; exit 1 }

# How often Zoom is read, and how. Measured 2026-09-27 against Zoom 7.0.5 in a meeting: a read is about 21 Accessibility
# calls and 3 ms; "once" starts osascript for each read (about 60 ms and 40 ms of CPU, 35 MB while it runs), "serve"
# keeps one osascript that answers each read (about 3 ms and 2 ms of CPU, 35–45 MB for as long as the button reads, a
# fresh one after 600 reads). Changing these two lines is all it takes to switch.
period=1                                        # seconds between reads in a meeting while the button is on screen
reader=once                                     # once | serve

idle_period=5                                   # seconds between looks while Zoom is closed or has no meeting
look_period=2                                   # seconds between asking the phone whether the button is on screen
green="#34C759" red="#FF3B30"
api="http://127.0.0.1:9848/api"
cell="{{CELL_ID}}"
shared=""
[[ -n $DESMAPTIC_STORAGE ]] && shared="$DESMAPTIC_STORAGE/gallery/zoom"
# $shared/poke:  "<epoch s>" of the last tap of a meeting button (press.zsh)
# $shared/state: "<epoch s> <answer>", the last answer of $zoom_ax state, stamped when it was asked

served=0                                        # the long-lived reader's process ("serve"), 0 when none
stop_reader() { (( served > 0 )) && kill $served 2>/dev/null; served=0; return 0 }
trap 'stop_reader; exit 0' TERM INT HUP
trap '' PIPE                                    # a reader that just ended must not take this loop with it

told=""
tell() {   # writes a problem to the log once, not every second
  [[ $1 == "$told" ]] && return 0
  told=$1
  [[ -n $1 ]] && print -ru2 -- "Zoom $mode: $1"
  return 0
}

# ask → REPLY = one answer of $zoom_ax state.
typeset -F asked_at=0
ask() {
  local line
  asked_at=$EPOCHREALTIME
  if [[ $reader == serve ]]; then
    if (( served == 0 )) || ! kill -0 $served 2>/dev/null; then
      coproc osascript -l JavaScript -e "$zoom_ax" serve
      served=$!
    fi
    if print -p state 2>/dev/null && IFS= read -r -t 3 -p line; then
      REPLY=$line
    else
      stop_reader; REPLY='!busy'
    fi
    return 0
  fi
  REPLY=$(osascript -l JavaScript -e "$zoom_ax" state 2>&1)
}

answer_shape='(closed|idle|(on|off|none|unknown) (on|off|none|unknown) (on|off|none|unknown))'
remember() {   # remember <epoch s> <answer>: leaves it for the other buttons
  [[ -n $shared ]] || return 0
  zf_mkdir -p $shared 2>/dev/null
  print -r -- "$1 $2" > $shared/state.$$ 2>/dev/null && zf_mv -f $shared/state.$$ $shared/state 2>/dev/null
}
# read_state <seconds an answer another button got may be old> → REPLY = an answer of $zoom_ax state.
# A button about to ask leaves "<epoch s> ?" first; one that finds it waits up to a second for that answer instead of
# asking too.
asked=0                                        # 1 when this button asked Zoom last time, 0 when it used another's answer
read_state() {
  local at="" answer="" tries=0
  asked=0
  while [[ -n $shared && -r $shared/state ]]; do
    at="" answer=""
    read -r at answer < $shared/state 2>/dev/null
    [[ $at == <->(|.<->) ]] || { answer=""; break }
    if [[ $answer == '?' ]] && (( EPOCHREALTIME - at < 2 && at > poked && tries < 10 )); then
      (( tries++ )); zselect -t 10; continue
    fi
    [[ $answer == ${~answer_shape} ]] && (( EPOCHREALTIME - at < $1 && at > poked )) || answer=""
    break
  done
  if [[ -z $answer ]]; then
    at=$EPOCHREALTIME                           # stamped when asked: a tap during the question makes it stale
    remember $at '?'                            # at once: the others must see it before they look
    asked=1
    pgrep -xqU $UID zoom.us                     # the cheap check first: no Zoom, nothing to ask
    case $? in
      0) ;;
      1) remember $at closed; REPLY=closed; return ;;
      *) remember $at '!'; REPLY='!pgrep'; return ;;   # stopped with the loop (the agent ends the group): no answer
    esac
    ask; answer=$REPLY
    if [[ $answer == ${~answer_shape} ]]; then remember $at "$answer"; else remember $at '!'; fi
  fi
  REPLY=$answer
}

# 0 when the phone shows the button, or when it cannot say (an older app).
visible() {
  local out code body
  out=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/view" \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}') || return 1
  code=${out##*$'\n'} body=${(L)${out%$'\n'*}//[[:space:]]/}
  [[ $code != 200 || $body == *'"view":null'* || $body == *${(L)cell}* ]]
}

# post on|off|none → 0 when the agent took it. None is the button's own grey look.
post() {
  local json out code
  case $mode:$1 in
    mic:on)     json="{\"cellId\":\"$cell\",\"icon\":\"mic.fill\",\"color\":\"$green\"}" ;;
    mic:off)    json="{\"cellId\":\"$cell\",\"icon\":\"mic.slash.fill\",\"color\":\"$red\"}" ;;
    camera:on)  json="{\"cellId\":\"$cell\",\"icon\":\"video.fill\",\"color\":\"$green\"}" ;;
    camera:off) json="{\"cellId\":\"$cell\",\"icon\":\"video.slash.fill\",\"color\":\"$red\"}" ;;
    share:on)   json="{\"cellId\":\"$cell\",\"color\":\"$green\"}" ;;
    *)          json="{\"cellId\":\"$cell\",\"reset\":true}" ;;
  esac
  out=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/update-button" \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}' \
    -H "Content-Type: application/json" -d "$json")
  code=${out##*$'\n'}
  [[ $code == 200 ]] && return 0
  print -ru2 -- "Zoom $mode: update-button answered ${code:-nothing}: ${${out%$'\n'*}[1,300]}"
  return 1
}

# poked → the time of the last tap, 0 before any.
typeset -F poked=0 next_at=0 quick_until=0 look_at=0 wait=0 slack=0
last_poke() {
  local p=""
  [[ -n $shared && -r $shared/poke ]] && read -r p < $shared/poke 2>/dev/null
  [[ $p == <->(|.<->) ]] && REPLY=$p || REPLY=0
}
last_poke; poked=$REPLY
# The three buttons start together; a random first delay puts them out of step, so that one asks and the others
# find its fresh answer instead of all three asking at the same moment.
(( next_at = EPOCHREALTIME + (RANDOM % 900) / 1000.0 ))
on_screen=0
last=""                                         # the last answer this button used
shown=""                                        # the state the phone shows; "" before the first post
typeset -a fields
while true; do
  last_poke
  if (( REPLY > poked )); then                  # a tap: read now, then every half second for a moment —
    poked=$REPLY                                # Zoom renames its menu item once it has switched
    next_at=0 quick_until=$(( EPOCHREALTIME + 3 ))
  fi
  if (( EPOCHREALTIME >= next_at )); then
    # Zoom closed (most of the day): no reason to ask the phone anything — one process check every $idle_period
    # seconds instead of a request to the agent every $look_period. Only pgrep's 1 means "not running".
    pgrep -xqU $UID zoom.us
    if (( $? == 1 )); then
      stop_reader; on_screen=0 look_at=0
      if [[ -n $shown && $shown != none ]]; then post none && shown=none; fi
      (( next_at = EPOCHREALTIME + idle_period + (RANDOM % 200) / 1000.0 ))
      zselect -t 25
      continue
    fi
    if (( EPOCHREALTIME >= look_at || next_at == 0 )); then
      if visible; then on_screen=1; else on_screen=0; fi
      (( look_at = EPOCHREALTIME + look_period ))
    fi
    if (( ! on_screen )); then                  # not on the phone's screen: Zoom is not read at all
      stop_reader
      (( next_at = look_at ))
    else
      # The button that asked last time keeps asking; the others take a slightly older answer, so one of them asks for
      # all (and, with "serve", only one reader stays).
      (( slack = asked ? 0 : 0.5 ))
      if (( EPOCHREALTIME < quick_until )); then read_state 0.45
      elif [[ $last == (closed|idle) ]]; then read_state $(( idle_period + 2 * slack ))
      else read_state $(( period + slack )); fi
      last=$REPLY
      # A reader this button no longer uses (another one asks for all of them) is not kept.
      (( served > 0 && EPOCHREALTIME - asked_at > 5 )) && stop_reader
      # Anything but an answer (osascript's own error text) is a problem to report, not three words to show.
      [[ $REPLY == ${~answer_shape} || $REPLY == '!'* ]] || REPLY="!${REPLY//$'\n'/ }"
      case $REPLY in
        closed) state=none; stop_reader; wait=$idle_period; tell "" ;;
        idle)   state=none; wait=$idle_period; tell "" ;;
        '!ax')  state=none; wait=$idle_period
                tell "The agent needs Accessibility to read Zoom: System Settings → Privacy & Security → Accessibility" ;;
        '!'*)   state=keep; wait=$period; tell "Zoom did not answer: ${REPLY[1,200]}" ;;
        *)      fields=(${=REPLY}); wait=$period
                case $mode in
                  mic)    state=$fields[1] ;;
                  camera) state=$fields[2] ;;
                  share)  state=$fields[3] ;;
                esac
                if [[ $state == unknown ]]; then
                  state=none; tell "Zoom's Meeting menu names this item in words this button does not know"
                else
                  tell ""
                fi ;;
      esac
      (( EPOCHREALTIME < quick_until && wait > 0.5 )) && wait=0.5
      (( next_at = EPOCHREALTIME + wait + (RANDOM % 200) / 1000.0 ))   # a little jitter keeps the buttons out of step
      [[ $state == off && $mode == share ]] && state=none
      if [[ $state != keep && $state != "$shown" ]]; then
        if post $state; then shown=$state; else (( next_at = EPOCHREALTIME + 10 )); fi
      fi
    fi
  fi
  zselect -t 25                                 # a quarter of a second, without starting a process
done
