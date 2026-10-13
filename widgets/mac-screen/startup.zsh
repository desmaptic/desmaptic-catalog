#!/bin/zsh
# Mac Screen: whether the Mac's screen is unlocked or locked, and since when, in the Mac's language
lang=""        # the words: en de es fr ru; empty — the Mac's first language (System Settings › General › Language), English for any other
#
# The state comes from the console session list macOS keeps in the I/O registry (ioreg -n Root -d1, IOConsoleUsers):
# this user's session carries "CGSSessionScreenIsLocked"=Yes and the moment it locked ("CGSSessionScreenLockedTime")
# while the screen is locked, and neither when it is not; a session that is not on the console (another user switched
# in) is locked too. No permission is needed to read it. Looked at every 5 s while the button is on screen, every 15 s
# while it is not, and at once when the tap leaves a note.
# Tool modes, no network: --face <rest|demo> <out.svg> writes the Gallery faces (rest.svg, demo.svg); any other
# argument prints the usage. SCREEN_DRY=1 runs the loop but reads the registry from the file $SCREEN_IOREG (read again
# at every look) and prints what the face says ("face: <word>|<since>") instead of posting.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT HUP
zmodload zsh/datetime zsh/zselect || { print -u2 -- "mac-screen: zsh modules datetime/zselect are missing"; exit 1 }
zmodload -F zsh/files b:zf_mkdir b:zf_mv b:zf_rm || { print -u2 -- "mac-screen: zsh module files is missing"; exit 1 }

dry=${SCREEN_DRY:-0}
[[ $dry == 1 ]] || dry=0

# screen_frame <rest|locked|unlocked> <word> <word size> <since line> <since size>
# rest: the saved face, a big padlock and no words. locked / unlocked: the padlock shrinks to the top, closed or
# with its shackle up, and the word and the time stand under it in the state's colour: calm cyan when locked,
# pink when anyone at the Mac could use it. A text with nothing to say keeps a character, hidden.
screen_frame() {
  emulate -L zsh
  local st=${1:-rest} word=${2:-} wsize=${3:-30} when=${4:-} tsize=${5:-26}
  [[ $st == (rest|locked|unlocked) ]] || st=rest
  [[ $wsize == <-> && $wsize -ge 10 && $wsize -le 60 ]] || wsize=30
  [[ $tsize == <-> && $tsize -ge 10 && $tsize -le 40 ]] || tsize=26
  local c bloom shackle tx=100 ty=40 k=0.5 fill=0 wo=1 to=0.72
  case $st in
    (locked)   c="#64D2FF" bloom=0.16 fill=0.30 shackle="M -18 -6 V -24 A 18 18 0 0 1 18 -24 V -6" ;;
    (unlocked) c="#FF375F" bloom=0.18 shackle="M -18 -18 V -34 A 18 18 0 0 1 18 -34 V -6" ;;
    (*)        c="#5E5CE6" bloom=0.14 shackle="M -18 -6 V -24 A 18 18 0 0 1 18 -24 V -6" ty=92 k=1.3 wo=0 to=0 ;;
  esac
  [[ -n $word ]] || { word="-" wo=0 }
  [[ -n $when ]] || { when="-" to=0 }
  word=${word//&/&amp;}; word=${word//</&lt;}; word=${word//>/&gt;}
  when=${when//&/&amp;}; when=${when//</&lt;}; when=${when//>/&gt;}
  local at="transform=\"translate($tx $ty) scale($k)\""

  printf '%s\n' "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 200 200\">\
<defs>\
<radialGradient id=\"bloomG\"><stop offset=\"0\" stop-color=\"$c\" stop-opacity=\"$bloom\"/><stop offset=\"1\" stop-color=\"$c\" stop-opacity=\"0\"/></radialGradient>\
</defs>\
<circle id=\"bloom\" cx=\"100\" cy=\"100\" r=\"92\" fill=\"url(#bloomG)\"/>\
<path id=\"shackle\" d=\"$shackle\" fill=\"none\" stroke=\"$c\" stroke-width=\"5\" stroke-linecap=\"round\" $at/>\
<rect id=\"body\" x=\"-30\" y=\"-6\" width=\"60\" height=\"46\" rx=\"10\" fill=\"$c\" fill-opacity=\"$fill\" stroke=\"$c\" stroke-width=\"5\" $at/>\
<text id=\"word\" x=\"100\" y=\"106\" font-size=\"$wsize\" font-weight=\"700\" text-anchor=\"middle\" dominant-baseline=\"middle\" fill=\"$c\" fill-opacity=\"$wo\">$word</text>\
<text id=\"since\" x=\"100\" y=\"148\" font-size=\"$tsize\" font-weight=\"500\" text-anchor=\"middle\" dominant-baseline=\"middle\" fill=\"#FFFFFF\" fill-opacity=\"$to\">$when</text>\
</svg>"
}

# The face's words in one language: sets w_unlocked, s_unlocked, w_locked, s_locked (the word and its size, so
# the longest still fits the button), w_since, w_days (Monday first), w_date (a strftime date) and the since line's
# size today, within the week and before it (s_today, s_day, s_date). Spanish agrees with "la pantalla", French
# with "l'écran".
words() {
  case $1 in
    (ru) w_unlocked="Открыт"       s_unlocked=34 w_locked="Заблокирован" s_locked=24 w_since="с"
         w_days=( пн вт ср чт пт сб вс ) w_date="%d.%m" s_day=26 s_date=26 ;;
    (de) w_unlocked="Entsperrt"    s_unlocked=31 w_locked="Gesperrt"     s_locked=34 w_since="seit"
         w_days=( Mo Di Mi Do Fr Sa So ) w_date="%d.%m." s_day=26 s_date=22 ;;
    (es) w_unlocked="Desbloqueada" s_unlocked=25 w_locked="Bloqueada"    s_locked=31 w_since="desde"
         w_days=( lun mar mié jue vie sáb dom ) w_date="%d/%m" s_day=21 s_date=20 ;;
    (fr) w_unlocked="Déverrouillé" s_unlocked=25 w_locked="Verrouillé"   s_locked=29 w_since="depuis"
         w_days=( lun. mar. mer. jeu. ven. sam. dim. ) w_date="%d/%m" s_day=20 s_date=19 ;;
    (*)  w_unlocked="Unlocked"     s_unlocked=34 w_locked="Locked"       s_locked=38 w_since="since"
         w_days=( Mon Tue Wed Thu Fri Sat Sun ) w_date="%b %f" s_day=22 s_date=19 ;;
  esac
  s_today=26
}

# since_line <epoch> <now>: REPLY = the since line, REPLY_size = its size. Today: "since 14:02"; within the last
# six days: "since Fri 14:02" (never today's weekday); before that: "since Oct 3 14:02".
since_line() {
  local hm day today
  strftime -s hm "%H:%M" $1
  strftime -s day "%Y%m%d" $1
  strftime -s today "%Y%m%d" $2
  if [[ $day == $today ]]; then
    REPLY="$w_since $hm" REPLY_size=$s_today
  elif (( $2 - $1 < 6 * 86400 )); then
    strftime -s day "%u" $1
    REPLY="$w_since $w_days[day] $hm" REPLY_size=$s_day
  else
    strftime -s day $w_date $1
    REPLY="$w_since $day $hm" REPLY_size=$s_date
  fi
}

usage() { print -u2 -- "usage: startup.zsh [--face <rest|demo> <out.svg>]"; exit 2 }
if (( $# )); then
  case $1 in
    (--face)
      (( $# == 3 )) && [[ $2 == (rest|demo) ]] || usage
      # The sample is one for all languages, so it says only the time.
      if [[ $2 == rest ]]; then REPLY=$(screen_frame rest)
      else REPLY=$(screen_frame locked 14:02 40); fi
      { print -rn -- $REPLY > $3 } 2>/dev/null || { print -u2 -- "mac-screen: cannot write $3"; exit 1 }
      exit 0 ;;
    (*) usage ;;
  esac
fi
if (( dry == 0 )) && [[ -z ${DESMAPTIC_TOKEN:-} ]]; then
  print -u2 -- "mac-screen: not started by Desmaptic Agent (no DESMAPTIC_TOKEN): try SCREEN_DRY=1"
  exit 1
fi

# The language: the setting above, else the first of the Mac's languages ("ru-RU" → ru).
if [[ -z $lang ]]; then
  langs=$(defaults read -g AppleLanguages 2>/dev/null)
  lang=${${(f)langs}[2]:-}
  lang=${${lang//[[:space:]\"(),]/}[1,2]}
fi
[[ $lang == (en|de|es|fr|ru) ]] || lang=en
words $lang

# ---- console_state: identical in startup.zsh and tap.zsh ----
# REPLY = "locked <locked at, epoch s; 0 when macOS does not say>", "unlocked", or "" when the registry has no
# session of this user. The list is one line of dictionaries, {…},{…}; this user's is the one with its uid.
console_state() {
  emulate -L zsh
  local out dict t
  REPLY=""
  if (( dry )); then out=$(cat -- ${SCREEN_IOREG:-/dev/null} 2>/dev/null)
  else out=$(ioreg -n Root -d1 2>/dev/null); fi
  [[ $out == *'"IOConsoleUsers" = ('* ]] || return 0
  out=${out#*\"IOConsoleUsers\" = \(}
  out=${out%%$'\n'*}
  out=${out//\},\{/$'\n'}
  for dict in "${(@f)out}"; do
    [[ $dict == *'"kCGSSessionUserIDKey"='$UID([^0-9]*|) ]] || continue
    if [[ $dict == *'"CGSSessionScreenIsLocked"=Yes'* || $dict == *'"kCGSSessionOnConsoleKey"=No'* ]]; then
      t=${dict#*\"CGSSessionScreenLockedTime\"=}
      t=${t%%[^0-9]*}
      [[ $t == <-> && ${#t} -le 12 ]] || t=0
      REPLY="locked $t"
    else
      REPLY="unlocked"
    fi
    return 0
  done
  return 0
}

cell="{{CELL_ID}}"
api="http://127.0.0.1:9848/api"
dir="${DESMAPTIC_STORAGE:-$HOME/Library/Application Support/Desmaptic/ScriptStorage}/gallery/$cell"
state_file="$dir/state"   # "<locked|unlocked> <since, epoch s; 0 unknown> <last seen, epoch s>": a restart keeps "since"
poke_file="$dir/poke"     # the tap's note: look at the screen now

# Replaces a file in one step, so a reader never sees half a line: put_file <path> <line>
put_file() {
  zf_mkdir -p "$dir" 2>/dev/null
  print -r -- "$2" > "$1.$$" && zf_mv -f "$1.$$" "$1"
}

# post <frame> <duration>: sets post_code and post_seen (0 when the button is not on screen).
# The token goes in through a descriptor, not the command line, where any user of the Mac could read it.
post() {
  local json=$1 answer
  if (( dry )); then post_code=200 post_seen=1; return 0; fi
  json=${json//\\/\\\\}; json=${json//\"/\\\"}; json=${json//$'\n'/}
  answer=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/update-button" -H @/dev/fd/3 \
    -H "Content-Type: application/json" --data-binary @- \
    3<<< "Authorization: Bearer $DESMAPTIC_TOKEN" \
    <<< "{\"cellId\":\"$cell\",\"svg\":{\"source\":\"$json\",\"duration\":$2,\"easing\":\"easeInOut\"}}")
  post_code=${answer##*$'\n'}
  post_seen=1
  [[ $answer == *'"visible":false'* ]] && post_seen=0
  [[ $post_code == 200 ]] || print -u2 -- "mac-screen: update-button answered ${post_code:-nothing}: ${${answer%$'\n'*}[1,300]}"
  return 0
}

# 0 when the button is on the phone's screen, or when nobody can tell (an older app).
on_screen() {
  local answer
  (( dry )) && return 0
  answer=$(curl -q -s -m 5 "$api/view" -H @/dev/fd/3 3<<< "Authorization: Bearer $DESMAPTIC_TOKEN") || return 0
  [[ $answer == *'"visibleCellIds"'* ]] || return 0
  [[ ${(L)answer} == *${(L)cell}* ]]
}

remember() { put_file $state_file "$st $since $EPOCHSECONDS" || print -u2 -- "mac-screen: cannot write $state_file" }
trap '[[ -n $st ]] && remember; exit 0' TERM INT HUP

st=""            # what the screen is: locked, unlocked; empty until the first look
since=0          # since when, epoch s; 0: not known (unlocked before the loop started)
missing=0        # the registry had no session of this user at the last look (said once)
look_at=0        # when to look at the screen next
quick_until=0    # after a tap: look every second until then
saved_at=0       # when the state file was last written
last_key=""      # what the phone shows: "<state> <since line>"
seen=1           # the button was on screen at the last post
view_at=0        # while hidden: when to ask /api/view again
retry_at=0       # after a failed post: when to try again
while true; do
  now=$EPOCHSECONDS
  if [[ -e $poke_file ]]; then
    zf_rm -f $poke_file 2>/dev/null
    look_at=0 quick_until=$(( now + 4 ))
  fi

  if (( now >= look_at )); then
    console_state
    if [[ -z $REPLY ]]; then
      (( missing )) || print -u2 -- "mac-screen: no console session of user $UID in the I/O registry"
      missing=1
    else
      missing=0
      new=${REPLY%% *} at=${REPLY#* }
      [[ $new == unlocked ]] && at=0
      if [[ $new != $st ]]; then
        if [[ -z $st ]]; then
          # The first look: locked has its moment from macOS; unlocked keeps the saved one when the
          # loop was away at most 2.5 minutes in the same state — longer, and the screen may have locked meanwhile.
          since=0
          if [[ $new == unlocked && -r $state_file ]]; then
            f=( ${=$(< $state_file)} )
            [[ $f[1] == unlocked && $f[2] == <-> && $f[3] == <-> ]] &&
              (( f[3] <= now && now - f[3] <= 150 && f[2] <= f[3] )) && since=$f[2]
          fi
        else
          since=$now
        fi
        (( at > 0 && at <= now )) && since=$at
        st=$new
        remember; saved_at=$now
      elif [[ $st == locked ]] && (( at > 0 && at <= now && at != since )); then
        since=$at     # macOS knew the moment better than the loop's first look
      fi
      (( now - saved_at >= 60 )) && { remember; saved_at=$now }
    fi
    if (( now < quick_until )); then look_at=$(( now + 1 ))
    elif (( seen )); then look_at=$(( now + 5 ))
    else look_at=$(( now + 15 )); fi
  fi

  if [[ -n $st ]]; then
    when="" tsize=26
    (( since > 0 )) && { since_line $since $now; when=$REPLY tsize=$REPLY_size }
    key="$st $when"
    # Hidden: no frames, only a look at the phone every 3 s.
    if (( ! seen && now >= view_at )); then
      if on_screen; then seen=1; else view_at=$(( now + 3 )); fi
    fi
    if (( seen && now >= retry_at )) && [[ $key != "$last_key" ]]; then
      if [[ $st == locked ]]; then word=$w_locked size=$s_locked; else word=$w_unlocked size=$s_unlocked; fi
      duration=0.8
      [[ -z $last_key ]] && duration=1.2       # the first frame: out of the saved face
      post "$(screen_frame $st $word $size "$when" $tsize)" $duration
      if [[ $post_code == 200 ]]; then
        (( dry )) && print -r -- "face: $word|$when"
        last_key=$key
        seen=$post_seen
        (( seen )) || view_at=$(( now + 3 ))
      else
        retry_at=$(( now + 10 ))
      fi
    fi
  fi

  zselect -t 50    # half a second, without starting a process
done
