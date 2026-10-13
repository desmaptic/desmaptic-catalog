# Microsoft Teams › Mic and Camera, the live state: green while the mic (camera) is on, red and crossed out while it is
# off, the button's own grey while Teams is closed, not in a meeting or cannot be read — and, for the camera, grey and
# crossed out when Teams greys the control out (no camera, or not allowed). Each button's startup script is one line
# that names it, then teams.zsh and this file (app.json):
#   "kind=mic\n@file:meeting/teams.zsh\n@file:meeting/live.zsh"   — mic or camera.
#
# Teams is read (teams.zsh) only while the button is on screen, and by one reader for both buttons: the loop that holds
# the lock in $DESMAPTIC_STORAGE/gallery/teams/ reads and writes what it saw to the state file there, and every loop
# shows that file. A button that leaves the screen lets go, and a loop still on screen takes over. While Teams is not
# running nothing is read — lsappinfo says so, every few seconds. A tap on Mic or Camera writes what Teams shows after
# the press (press.zsh), so the button changes at once, not at the next read.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
[[ $kind == (mic|camera) ]] || { print -u2 -- "Teams: unknown kind \"$kind\""; exit 1 }
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
zmodload zsh/datetime zsh/zselect zsh/system \
  || { print -u2 -- "Teams $kind: zsh modules datetime/zselect/system are missing"; exit 1 }
zmodload -F zsh/files b:zf_mkdir b:zf_mv b:zf_rm || { print -u2 -- "Teams $kind: zsh module files is missing"; exit 1 }

# Every interval, in one place.
period=1        # seconds between reads while a meeting is on (a read of the two labels it already found)
idle=5          # seconds between looks for a meeting while Teams runs without one (a look walks Teams' windows),
                # and between asks whether Teams runs at all
mode=loop       # loop: one reader process lives while the button is on screen and Teams runs (lifetime below);
                # once: a new osascript for every read
lifetime=1800   # seconds a long-lived reader lives before a fresh one takes over (the one before only grows)
look=3          # seconds between asks whether the phone shows the button, while it does not
look_shown=10   # … and while it does (the answer only decides when reading stops)

api="http://127.0.0.1:9848/api"
cell="{{CELL_ID}}"
shared=""
[[ -n $DESMAPTIC_STORAGE ]] && shared="$DESMAPTIC_STORAGE/gallery/teams"   # "state", "reader.lock"
stale=$(( (2 * idle + period + 3) * 1000 ))     # a state line older than this (ms) says nothing any more
green="#34C759" red="#FF3B30" grey="#8E8E93"

teams_program; program=$REPLY

told=""
tell() {   # writes a problem to the log once, not every read
  [[ $1 == "$told" ]] && return 0
  told=$1
  [[ -n $1 ]] && print -ru2 -- "Teams $kind: $1"
  return 0
}

# 0 when the phone shows the button, or when it cannot say (an older app).
visible() {
  local out code body
  out=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/view" \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}') || return 1
  code=${out##*$'\n'} body=${(L)${out%$'\n'*}//[[:space:]]/}
  [[ $code != 200 || $body == *'"view":null'* || $body == *${(L)cell}* ]]
}

# post <look> → 0 when the agent took it. "rest" is the button's own look.
post() {
  local json out code
  case $1 in
    rest)      json="{\"cellId\":\"$cell\",\"reset\":true}" ;;
    mic:on)    json="{\"cellId\":\"$cell\",\"icon\":\"mic.fill\",\"color\":\"$green\"}" ;;
    mic:off)   json="{\"cellId\":\"$cell\",\"icon\":\"mic.slash.fill\",\"color\":\"$red\"}" ;;
    camera:on) json="{\"cellId\":\"$cell\",\"icon\":\"video.fill\",\"color\":\"$green\"}" ;;
    camera:off) json="{\"cellId\":\"$cell\",\"icon\":\"video.slash.fill\",\"color\":\"$red\"}" ;;
    camera:none) json="{\"cellId\":\"$cell\",\"icon\":\"video.slash\",\"color\":\"$grey\"}" ;;
    *) return 1 ;;
  esac
  out=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/update-button" \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}' \
    -H "Content-Type: application/json" -d "$json")
  code=${out##*$'\n'}
  [[ $code == 200 ]] && return 0
  print -ru2 -- "Teams $kind: update-button answered ${code:-nothing}: ${${out%$'\n'*}[1,300]}"
  return 1
}

# The look for a state line: rest, mic:on, mic:off, camera:on, camera:off, camera:none — or keep (a passing problem:
# the phone keeps what it shows).
look_of() {
  local -a f=( ${(s: :)1} )
  local asked=$f[1] teams=$f[2] mic=$f[3] camera=$f[4] now_ms
  (( now_ms = EPOCHREALTIME * 1000 ))
  if [[ $asked != <-> ]] || (( now_ms - asked > stale )); then REPLY=rest; return; fi
  case $teams in
    meeting) ;;
    wait|busy) REPLY=keep; return ;;
    noax)
      tell "The agent needs Accessibility: System Settings → Privacy & Security → Accessibility"
      REPLY=rest; return ;;
    *) tell ""; REPLY=rest; return ;;
  esac
  local s=$mic
  [[ $kind == camera ]] && s=$camera
  case $kind:$s in
    mic:on|mic:off|camera:on|camera:off|camera:none) REPLY=$kind:$s; tell "" ;;
    mic:locked) REPLY=mic:off; tell "" ;;         # greyed out: Teams will not let the mic on now
    *:-) REPLY=rest; tell "" ;;                   # this meeting shows no such control (a call without a camera)
    *) REPLY=rest; tell "Teams shows a $kind control this button does not know" ;;
  esac
}

# MARK: - The reader (only in the loop that holds the lock)

holding=0 lockfd=0 reader=0 reader_for="" reader_since=0
typeset -F next_check=0 next_read=0
last_teams="" was_meeting=0 misses=0

take_lock() {
  [[ -n $shared ]] || return 1
  zf_mkdir -p $shared 2>/dev/null
  : >> $shared/reader.lock 2>/dev/null || return 1
  zsystem flock -t 0 -f lockfd $shared/reader.lock 2>/dev/null && holding=1
}
stop_reader() {
  (( reader > 0 )) && kill $reader 2>/dev/null
  reader=0 reader_for=""
}
let_go() {
  stop_reader
  (( holding )) && zsystem flock -u $lockfd 2>/dev/null
  holding=0
}
take_line() {   # a line from the reader → the shared state
  local -a f=( ${(s: :)1} )
  local asked=$f[1] teams=$f[2]
  if [[ $asked != <-> || $teams != (meeting|none|wait|busy|noax|off) || $#f != 5 ]]; then
    tell "the reader said: ${1[1,200]}"
    return
  fi
  # A scan can miss the toolbar once while Teams rebuilds it: after a meeting, "none" counts from the third in a row
  # (the reader looks again after 1 s); the two before it keep what the buttons show.
  if [[ $teams == meeting ]]; then
    was_meeting=1 misses=0
  elif [[ $teams == none ]] && (( was_meeting && misses < 2 )); then
    (( misses++ ))
    last_teams=wait
    teams_keep $shared "$asked wait - -"
    return
  elif [[ $teams == (none|noax|off) ]]; then
    was_meeting=0 misses=0
  fi
  last_teams=$teams
  teams_keep $shared "${1% *}"
}
stamp_off() {
  local -i now_ms
  (( now_ms = EPOCHREALTIME * 1000 ))
  was_meeting=0 misses=0
  last_teams=off
  teams_keep $shared "$now_ms off - -"
}

# Called every tick while this loop holds the lock.
serve() {
  local now=$EPOCHREALTIME pid
  if (( now >= next_check )); then              # is Teams running, and is the reader reading this Teams?
    (( next_check = now + idle ))
    if ! teams_pid; then
      stop_reader
      [[ $last_teams == off ]] || stamp_off
      return
    fi
    pid=$REPLY
    if [[ $mode == loop ]]; then
      if (( reader > 0 )) && [[ $reader_for != $pid ]]; then stop_reader; fi
      if (( reader == 0 )); then
        coproc /usr/bin/osascript -l JavaScript -e "$program" loop $pid $period $idle $lifetime
        reader=$! reader_for=$pid reader_since=$now
      fi
    else
      reader_for=$pid
    fi
  fi
  if [[ $mode == once && -n $reader_for ]] && (( now >= next_read )); then
    take_line "$(/usr/bin/osascript -l JavaScript -e "$program" read $reader_for 2>&1)"
    case $last_teams in
      meeting) (( next_read = EPOCHREALTIME + period )) ;;
      wait|busy) (( next_read = EPOCHREALTIME + 1 )) ;;
      *) (( next_read = EPOCHREALTIME + idle )) ;;
    esac
  fi
}

# A quarter of a second; the holder of a long-lived reader spends it waiting for the reader's next line.
tick() {
  local line t0=$EPOCHREALTIME
  if (( holding && reader > 0 )); then
    if IFS= read -r -t 0.25 -p line 2>/dev/null; then
      take_line "$line"
      return
    fi
    if (( EPOCHREALTIME - t0 < 0.2 )); then     # the reader is gone: its life ended, or no Accessibility
      if ! kill -0 $reader 2>/dev/null; then
        if [[ $last_teams == noax ]]; then (( next_check = EPOCHREALTIME + 6 * idle ))
        elif (( EPOCHREALTIME - reader_since < 10 )); then (( next_check = EPOCHREALTIME + 2 * idle ))   # failing
        else next_check=0                       # it lived its life: a fresh one now
        fi
        reader=0 reader_for=""
      fi
      zselect -t 25
    fi
    return
  fi
  zselect -t 25
}

trap 'let_go; exit 0' TERM INT HUP

typeset -F next_view=0 next_post=0
on_screen=0 shown="" state=""
typeset -F next_alive=0
teams_alive=0
while true; do
  # Teams closed (most of the day): no reason to ask the phone anything — one process check every $idle seconds
  # (lsappinfo, about 3 ms of CPU) instead of a request to the agent every $look; while Teams runs, once a second,
  # not on every quarter-second tick.
  if (( EPOCHREALTIME >= next_alive )); then
    if teams_pid; then teams_alive=1; (( next_alive = EPOCHREALTIME + 1 )); else teams_alive=0; fi
  fi
  if (( ! teams_alive )); then
    (( holding )) && let_go
    if [[ -n $shown && $shown != rest ]]; then post rest && shown=rest; fi
    on_screen=0 next_view=0 next_alive=0
    zselect -t $(( idle * 100 ))
    continue
  fi
  if (( EPOCHREALTIME >= next_view )); then
    if visible; then on_screen=1; else on_screen=0; fi
    (( next_view = EPOCHREALTIME + (on_screen ? look_shown : look) ))
  fi
  if (( ! on_screen )); then                    # not on screen: nothing is read, the lock goes to a loop that is
    (( holding )) && let_go
    zselect -t 25
    continue
  fi
  (( holding )) || take_lock
  (( holding )) && serve
  state=""
  [[ -n $shared && -r $shared/state ]] && read -r state < $shared/state 2>/dev/null
  look_of "$state"
  if [[ $REPLY != keep && $REPLY != "$shown" ]] && (( EPOCHREALTIME >= next_post )); then
    if post $REPLY; then shown=$REPLY; else (( next_post = EPOCHREALTIME + 10 )); fi
  fi
  tick
done
