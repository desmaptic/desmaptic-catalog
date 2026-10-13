# Music › Shuffle, Repeat and Favorite, the live state: the button turns Music's red while the mode is on — Repeat
# with a 1 while it repeats one song, Favorite with a filled star while the song playing is a favorite — and keeps its
# own grey while it is off, and while Music is closed or the agent may not control it yet, when nobody can tell.
# Music is read every 5 s while the button is on screen, every second for a moment after any tap of the page's Music
# buttons (player/action.zsh leaves the time in $DESMAPTIC_STORAGE/gallery/music/poke), and not at all while the button
# is not on screen. One question reads all three and leaves them in $DESMAPTIC_STORAGE/gallery/music/modes, so with the
# three buttons on screen only one of them asks.
# The question is a read-only Apple event sent to the running Music by its process id: it cannot launch Music and
# never brings up the Automation question (the first tap of a Music button does that).
# The three buttons' startup script is one line that names the mode, then this file (app.json):
#   "mode=shuffle\n@file:toggle/live.zsh"   — shuffle, repeat or favorite.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
[[ $mode == (shuffle|repeat|favorite) ]] || { print -u2 -- "Music: unknown mode \"$mode\""; exit 1 }
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT HUP
zmodload zsh/datetime zsh/zselect || { print -u2 -- "Music $mode: zsh modules datetime/zselect are missing"; exit 1 }
zmodload -F zsh/files b:zf_mkdir b:zf_mv || { print -u2 -- "Music $mode: zsh module files is missing"; exit 1 }

api="http://127.0.0.1:9848/api"
cell="{{CELL_ID}}"
shared=""
[[ -n $DESMAPTIC_STORAGE ]] && shared="$DESMAPTIC_STORAGE/gallery/music"
# $shared/poke:  "<epoch s>" of the last tap that changed something (player/action.zsh)
# $shared/modes: "<epoch s> <shuffle 1|0> <repeat off|all|one> <favorite 1|0>", the last answer
period=5                                        # seconds between questions while the button is on screen
red="#FA2D48"                                   # Music's own "on"

# Prints "<shuffle 1|0> <repeat off|all|one> <favorite 1|0>", or !<Apple event error>: -600 Music is not running,
# -1744 the agent has not been asked about controlling it yet, -1743 it was told no, -1712 Music did not answer within
# 2 s. Nothing playing is not an error: no song, no star.
read -r -d '' JXA <<'JS'
ObjC.import("AppKit");
function run() {
  const fcc = s => ((s.charCodeAt(0) << 24) | (s.charCodeAt(1) << 16) | (s.charCodeAt(2) << 8) | s.charCodeAt(3)) >>> 0;
  const apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier("com.apple.Music");
  let pid = 0;
  for (let i = 0; i < apps.count && !pid; i++) {
    const app = apps.objectAtIndex(i);
    if (app.finishedLaunching) pid = app.processIdentifier;
  }
  if (!pid) return "!-600";
  const D = $.NSAppleEventDescriptor;
  function property(code, from) {
    const spec = D.recordDescriptor;
    spec.setDescriptorForKeyword(D.descriptorWithTypeCode(fcc("prop")), fcc("want"));
    spec.setDescriptorForKeyword(from, fcc("from"));
    spec.setDescriptorForKeyword(D.descriptorWithEnumCode(fcc("prop")), fcc("form"));
    spec.setDescriptorForKeyword(D.descriptorWithTypeCode(fcc(code)), fcc("seld"));
    return spec.coerceToDescriptorType(fcc("obj "));
  }
  function get(object) {
    const event = D.appleEventWithEventClassEventIDTargetDescriptorReturnIDTransactionID(
      fcc("core"), fcc("getd"), D.descriptorWithProcessIdentifier(pid), -1, 0);
    event.setParamDescriptorForKeyword(object, fcc("----"));
    // wait for the reply, never interact, never ask for consent (-1744 instead); give up after 2 s.
    // The NSError comes back in $(): reading a Ref() after an error crashes osascript (EXC_BAD_ACCESS, macOS 26).
    const error = $();
    const reply = event.sendEventWithOptionsTimeoutError(0x3 | 0x10 | 0x20000, 2, error);
    if (reply.isNil()) throw (error.isNil() ? -1 : error.code);
    const status = reply.paramDescriptorForKeyword(fcc("errn"));
    if (!status.isNil() && status.int32Value != 0) throw status.int32Value;
    return reply.paramDescriptorForKeyword(fcc("----"));
  }
  const yes = value => !value.isNil() && value.booleanValue;
  try {
    const app = D.nullDescriptor;
    const shuffle = yes(get(property("pShE", app))) ? "1" : "0";
    const code = get(property("pRpt", app)).enumCodeValue >>> 0;
    const repeat = code == fcc("kAll") ? "all" : code == fcc("kRp1") ? "one" : "off";
    let favorite = "0";
    try {
      favorite = yes(get(property("pLov", property("pTrk", app)))) ? "1" : "0";
    } catch (error) {
      if ([-600, -609, -1712, -1743, -1744].includes(error)) throw error;
    }
    return shuffle + " " + repeat + " " + favorite;
  } catch (error) { return "!" + error; }
}
JS

told=""
tell() {   # writes a problem to the log once, not every 5 s
  [[ $1 == "$told" ]] && return 0
  told=$1
  [[ -n $1 ]] && print -ru2 -- "Music $mode: $1"
  return 0
}

# read_state <seconds an answer the other buttons got may be old> → REPLY = the state this button shows: off (also:
# cannot tell), on, all or one; or keep (a passing problem: the phone keeps what it shows).
read_state() {
  local answer="" at="" s="" r="" f=""
  # By bundle id: an iOS simulator's own "Music" would pass pgrep, and the Apple event would then launch the Mac's.
  if [[ $(lsappinfo info -only pid -app com.apple.Music 2>/dev/null) != *'"pid"='<1->* ]]; then
    REPLY=off; tell ""; return
  fi
  if [[ -n $shared && -r $shared/modes ]]; then
    read -r at s r f < $shared/modes 2>/dev/null
    [[ $at == <->(|.<->) && $s == [01] && $r == (off|all|one) && $f == [01] ]] \
      && (( EPOCHREALTIME - at < $1 && at > poked )) && answer="$s $r $f"
  fi
  if [[ -z $answer ]]; then
    at=$EPOCHREALTIME                           # stamped when asked: a tap during the question makes it stale
    answer=$(osascript -l JavaScript -e "$JXA" 2>&1)
    if [[ -n $shared && $answer == [01]' '(off|all|one)' '[01] ]]; then
      zf_mkdir -p $shared 2>/dev/null
      print -r -- "$at $answer" > $shared/modes.$$ 2>/dev/null && zf_mv -f $shared/modes.$$ $shared/modes 2>/dev/null
    fi
  fi
  case $answer in
    [01]' '(off|all|one)' '[01])
      s=${answer%% *} r=${${answer#* }% *} f=${answer##* }
      case $mode in
        shuffle)  if [[ $s == 1 ]]; then REPLY=on; else REPLY=off; fi ;;
        repeat)   REPLY=$r ;;
        favorite) if [[ $f == 1 ]]; then REPLY=on; else REPLY=off; fi ;;
      esac
      tell "" ;;
    '!-600'|'!-609') REPLY=off ;;
    '!-1744')        REPLY=off; tell "shows nothing until the agent may control Music: tap a Music button once" ;;
    '!-1743')        REPLY=off; tell "The agent may not control Music: allow it in System Settings → Privacy & Security → Automation" ;;
    *)               REPLY=keep; tell "Music did not tell the state: ${answer[1,200]}" ;;
  esac
}

# 0 when the phone shows the button, or when it cannot say (an older app).
visible() {
  local out code body
  out=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/view" \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}') || return 1
  code=${out##*$'\n'} body=${(L)${out%$'\n'*}//[[:space:]]/}
  [[ $code != 200 || $body == *'"view":null'* || $body == *${(L)cell}* ]]
}

# post <state> → 0 when the agent took it. Off is the button's own look; the others name their symbol, so Repeat
# goes back from the 1 to its own arrows.
post() {
  local json out code
  case $mode:$1 in
    shuffle:on)  json="{\"cellId\":\"$cell\",\"color\":\"$red\"}" ;;
    repeat:all)  json="{\"cellId\":\"$cell\",\"icon\":\"repeat\",\"color\":\"$red\"}" ;;
    repeat:one)  json="{\"cellId\":\"$cell\",\"icon\":\"repeat.1\",\"color\":\"$red\"}" ;;
    favorite:on) json="{\"cellId\":\"$cell\",\"icon\":\"star.fill\",\"color\":\"$red\"}" ;;
    *)           json="{\"cellId\":\"$cell\",\"reset\":true}" ;;
  esac
  out=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/update-button" \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}' \
    -H "Content-Type: application/json" -d "$json")
  code=${out##*$'\n'}
  [[ $code == 200 ]] && return 0
  print -ru2 -- "Music $mode: update-button answered ${code:-nothing}: ${${out%$'\n'*}[1,300]}"
  return 1
}

# poked → the time of the last tap, 0 before any.
typeset -F poked=0 next_at=0 quick_until=0
last_poke() {
  local p=""
  [[ -n $shared && -r $shared/poke ]] && read -r p < $shared/poke 2>/dev/null
  [[ $p == <->(|.<->) ]] && REPLY=$p || REPLY=0
}
last_poke; poked=$REPLY
shown=""                                        # the state the phone shows; "" before the first post
while true; do
  last_poke
  if (( REPLY > poked )); then                  # a tap: ask now, then every second for a moment —
    poked=$REPLY                                # Music may take a beat to switch or load the next song
    next_at=0 quick_until=$(( EPOCHREALTIME + 3 ))
  fi
  if (( EPOCHREALTIME >= next_at )); then
    if (( EPOCHREALTIME < quick_until )); then
      (( next_at = EPOCHREALTIME + 1 )); fresh=0.8
    else
      (( next_at = EPOCHREALTIME + period )); fresh=3
    fi
    if visible; then
      read_state $fresh
      if [[ $REPLY != keep && $REPLY != "$shown" ]]; then
        if post $REPLY; then shown=$REPLY; else (( next_at = EPOCHREALTIME + 10 )); fi
      fi
    fi
  fi
  zselect -t 25                                 # a quarter of a second, without starting a process
done
