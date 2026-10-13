# Discord › Mute and Deafen, the live state: Mute is green while your mic is on and red and crossed out while Discord
# mutes it (also while you are deafened: Discord mutes the mic then); Deafen is green while you hear Discord and red and
# crossed out while you are deafened. Each keeps the button's own grey while Discord is closed, its window is closed or
# nobody can tell. Each button's startup script is one line that names it, then discord.zsh and this file (app.json):
#   "kind=mute\n@file:voice/discord.zsh\n@file:voice/live.zsh"   — mute or deafen.
#
# Discord is read (discord.zsh) only while the button is on screen, and by one reader for both buttons: the loop that
# holds the lock in $DESMAPTIC_STORAGE/gallery/discord/ reads and writes what it saw to the state file there, and every
# loop shows that file. A button that leaves the screen lets go, and a loop still on screen takes over. While Discord is
# not running nothing is read and the phone is not asked — lsappinfo says so, every few seconds. A tap writes what
# Discord shows after the press (press.zsh), so both buttons change at once, not at the next read.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
[[ $kind == (mute|deafen) ]] || { print -u2 -- "Discord: unknown kind \"$kind\""; exit 1 }
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
zmodload zsh/datetime zsh/zselect zsh/system \
  || { print -u2 -- "Discord $kind: zsh modules datetime/zselect/system are missing"; exit 1 }
zmodload -F zsh/files b:zf_mkdir b:zf_mv || { print -u2 -- "Discord $kind: zsh module files is missing"; exit 1 }

# Every interval, in one place.
period=1        # seconds between reads while the switches are found (a read of the two values it already found)
idle=5          # seconds between looks for the switches while Discord shows none (a look walks its windows),
                # and between asks whether Discord runs at all
mode=loop       # loop: one reader process lives while the button is on screen and Discord runs (lifetime below);
                # once: a new osascript for every read
lifetime=1800   # seconds a long-lived reader lives before a fresh one takes over (the one before only grows)
look=3          # seconds between asks whether the phone shows the button, while it does not
look_shown=10   # … and while it does (the answer only decides when reading stops)

api="http://127.0.0.1:9848/api"
cell="{{CELL_ID}}"
shared=""
[[ -n $DESMAPTIC_STORAGE ]] && shared="$DESMAPTIC_STORAGE/gallery/discord"   # "state", "reader.lock"
stale=$(( (2 * idle + period + 3) * 1000 ))     # a state line older than this (ms) says nothing any more
green="#34C759" red="#FF3B30"

discord_program; program=$REPLY

told=""
tell() {   # writes a problem to the log once, not every read
  [[ $1 == "$told" ]] && return 0
  told=$1
  [[ -n $1 ]] && print -ru2 -- "Discord $kind: $1"
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

# post <look> → 0 when the agent took it. "rest" is the button's own look. The phone app runs on iOS 17, which has no
# crossed-out headphones (headphones.slash is iOS 18), so deafened is Discord's other word for it: the sound off.
post() {
  local json out code
  case $1 in
    rest)       json="{\"cellId\":\"$cell\",\"reset\":true}" ;;
    mute:off)   json="{\"cellId\":\"$cell\",\"icon\":\"mic.fill\",\"color\":\"$green\"}" ;;
    mute:on)    json="{\"cellId\":\"$cell\",\"icon\":\"mic.slash.fill\",\"color\":\"$red\"}" ;;
    deafen:off) json="{\"cellId\":\"$cell\",\"icon\":\"headphones\",\"color\":\"$green\"}" ;;
    deafen:on)  json="{\"cellId\":\"$cell\",\"icon\":\"speaker.slash.fill\",\"color\":\"$red\"}" ;;
    *) return 1 ;;
  esac
  out=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/update-button" \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}' \
    -H "Content-Type: application/json" -d "$json")
  code=${out##*$'\n'}
  [[ $code == 200 ]] && return 0
  print -ru2 -- "Discord $kind: update-button answered ${code:-nothing}: ${${out%$'\n'*}[1,300]}"
  return 1
}

# The look for a state line: rest, mute:on, mute:off, deafen:on, deafen:off — or keep (a passing problem: the phone
# keeps what it shows).
look_of() {
  local -a f=( ${(s: :)1} )
  local asked=$f[1] discord=$f[2] mute=$f[3] deafen=$f[4] now_ms
  (( now_ms = EPOCHREALTIME * 1000 ))
  if [[ $asked != <-> ]] || (( now_ms - asked > stale )); then REPLY=rest; return; fi
  case $discord in
    ok) ;;
    wait|busy) REPLY=keep; return ;;
    noax)
      tell "The agent needs Accessibility: System Settings → Privacy & Security → Accessibility"
      REPLY=rest; return ;;
    *) tell ""; REPLY=rest; return ;;
  esac
  local s=$mute
  [[ $kind == deafen ]] && s=$deafen
  case $s in
    on|off) REPLY=$kind:$s; tell "" ;;
    *) REPLY=rest; tell "Discord's $kind switch says something this button does not know" ;;
  esac
}

# MARK: - The reader (only in the loop that holds the lock)

holding=0 lockfd=0 reader=0 reader_for="" reader_since=0
typeset -F next_check=0 next_read=0
last_discord="" was_ok=0 misses=0

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
  local asked=$f[1] discord=$f[2]
  if [[ $asked != <-> || $discord != (ok|none|closed|wait|busy|noax|off) || $#f != 5 ]]; then
    tell "the reader said: ${1[1,200]}"
    return
  fi
  # A walk can miss the panel once while Discord rebuilds it: after "ok", "none" counts from the third in a row (the
  # reader looks again after 1 s); the two before it keep what the buttons show.
  if [[ $discord == ok ]]; then
    was_ok=1 misses=0
  elif [[ $discord == none ]] && (( was_ok && misses < 2 )); then
    (( misses++ ))
    last_discord=wait
    discord_keep $shared "$asked wait - -"
    return
  elif [[ $discord == (none|closed|noax|off) ]]; then
    was_ok=0 misses=0
  fi
  last_discord=$discord
  discord_keep $shared "${1% *}"
}
stamp_off() {
  local -i now_ms
  (( now_ms = EPOCHREALTIME * 1000 ))
  was_ok=0 misses=0
  last_discord=off
  discord_keep $shared "$now_ms off - -"
}

# Called every tick while this loop holds the lock.
serve() {
  local now=$EPOCHREALTIME pid
  if (( now >= next_check )); then              # is Discord running, and is the reader reading this Discord?
    (( next_check = now + idle ))
    if ! discord_pid; then
      stop_reader
      [[ $last_discord == off ]] || stamp_off
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
    case $last_discord in
      ok) (( next_read = EPOCHREALTIME + period )) ;;
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
        if [[ $last_discord == noax ]]; then (( next_check = EPOCHREALTIME + 6 * idle ))
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

typeset -F next_view=0 next_post=0 next_alive=0
on_screen=0 shown="" state=""
while true; do
  # Discord closed: no reason to ask the phone anything — one process check every $idle seconds (lsappinfo, a few ms)
  # instead of a request to the agent every $look. While it runs (for many, all day) the check is once a second, not
  # every quarter-second tick: an lsappinfo costs about 3 ms of CPU with Launch Services' share.
  if (( EPOCHREALTIME >= next_alive )); then
    if ! discord_pid; then
      (( holding )) && let_go
      if [[ -n $shown && $shown != rest ]]; then post rest && shown=rest; fi
      on_screen=0 next_view=0
      zselect -t $(( idle * 100 ))
      continue
    fi
    (( next_alive = EPOCHREALTIME + 1 ))
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
