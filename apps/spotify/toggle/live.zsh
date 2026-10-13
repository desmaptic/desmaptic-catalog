# Spotify › Shuffle and Repeat, the live state: the button turns Spotify green while the mode is on and keeps its own
# grey while it is off — and while Spotify is closed or the agent may not control it yet, when nobody can tell.
# The modes are read every 5 s while the button is on screen, at once after a tap (player/action.zsh leaves a file
# in the button's storage), and not at all while the button is not on screen. One question reads both modes and
# leaves them in $DESMAPTIC_STORAGE/gallery/spotify/modes, so with both buttons on screen only one of them asks.
# The question is a read-only Apple event sent to the running Spotify by its process id: it cannot launch Spotify
# and never brings up the Automation question (the first tap of a Spotify button does that).
# Both buttons' startup script is one line that names the mode, then this file (app.json):
#   "mode=shuffle\n@file:toggle/live.zsh"   — shuffle or repeat.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
[[ $mode == (shuffle|repeat) ]] || { print -u2 -- "Spotify: unknown mode \"$mode\""; exit 1 }
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT HUP
zmodload zsh/datetime zsh/zselect || { print -u2 -- "Spotify $mode: zsh modules datetime/zselect are missing"; exit 1 }
zmodload -F zsh/files b:zf_mkdir b:zf_mv b:zf_rm || { print -u2 -- "Spotify $mode: zsh module files is missing"; exit 1 }

api="http://127.0.0.1:9848/api"
cell="{{CELL_ID}}"
dir="" shared=""
if [[ -n $DESMAPTIC_STORAGE ]]; then
  dir="$DESMAPTIC_STORAGE/gallery/$cell"          # "changed": a tap switched the mode
  shared="$DESMAPTIC_STORAGE/gallery/spotify"     # "modes": "<epoch s> <shuffle 1|0> <repeat 1|0>", the last answer
fi
period=5                                        # seconds between questions while the button is on screen
fresh=3                                         # an answer the other button got this recently is used as it is
green="#1ED760"                                 # Spotify's own "on"

# Prints "<shuffling> <repeating>" as 1 or 0, or !<Apple event error>: -600 Spotify is not running, -1744 the agent
# has not been asked about controlling it yet, -1743 it was told no, -1712 Spotify did not answer within 2 s.
read -r -d '' JXA <<'JS'
ObjC.import("AppKit");
function run() {
  const fcc = s => ((s.charCodeAt(0) << 24) | (s.charCodeAt(1) << 16) | (s.charCodeAt(2) << 8) | s.charCodeAt(3)) >>> 0;
  const apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier("com.spotify.client");
  let pid = 0;
  for (let i = 0; i < apps.count && !pid; i++) {
    const app = apps.objectAtIndex(i);
    if (app.finishedLaunching) pid = app.processIdentifier;
  }
  if (!pid) return "!-600";
  const D = $.NSAppleEventDescriptor;
  function get(code) {
    const spec = D.recordDescriptor;
    spec.setDescriptorForKeyword(D.descriptorWithTypeCode(fcc("prop")), fcc("want"));
    spec.setDescriptorForKeyword(D.nullDescriptor, fcc("from"));
    spec.setDescriptorForKeyword(D.descriptorWithEnumCode(fcc("prop")), fcc("form"));
    spec.setDescriptorForKeyword(D.descriptorWithTypeCode(fcc(code)), fcc("seld"));
    const event = D.appleEventWithEventClassEventIDTargetDescriptorReturnIDTransactionID(
      fcc("core"), fcc("getd"), D.descriptorWithProcessIdentifier(pid), -1, 0);
    event.setParamDescriptorForKeyword(spec.coerceToDescriptorType(fcc("obj ")), fcc("----"));
    // wait for the reply, never interact, never ask for consent (-1744 instead); give up after 2 s.
    // The NSError comes back in $(): reading a Ref() after an error crashes osascript (EXC_BAD_ACCESS, macOS 26).
    const error = $();
    const reply = event.sendEventWithOptionsTimeoutError(0x3 | 0x10 | 0x20000, 2, error);
    if (reply.isNil()) throw (error.isNil() ? -1 : error.code);
    const status = reply.paramDescriptorForKeyword(fcc("errn"));
    if (!status.isNil() && status.int32Value != 0) throw status.int32Value;
    const value = reply.paramDescriptorForKeyword(fcc("----"));
    return !value.isNil() && value.booleanValue ? "1" : "0";
  }
  try { return get("pShu") + " " + get("pRep"); } catch (code) { return "!" + code; }
}
JS

told=""
tell() {   # writes a problem to the log once, not every 5 s
  [[ $1 == "$told" ]] && return 0
  told=$1
  [[ -n $1 ]] && print -ru2 -- "Spotify $mode: $1"
  return 0
}

# read_mode [1: ask Spotify even when the other button just did] → REPLY = on, off (also: cannot tell) or keep
# (a passing problem: the phone keeps what it shows).
read_mode() {
  local answer="" at="" s="" r=""
  if ! pgrep -xqU $UID Spotify; then
    REPLY=off; tell ""; return
  fi
  if [[ $1 != 1 && -n $shared && -r $shared/modes ]]; then
    read -r at s r < $shared/modes 2>/dev/null
    [[ $at == <-> && $s == [01] && $r == [01] ]] && (( EPOCHSECONDS - at < fresh )) && answer="$s $r"
  fi
  if [[ -z $answer ]]; then
    answer=$(osascript -l JavaScript -e "$JXA" 2>&1)
    if [[ -n $shared && $answer == [01]' '[01] ]]; then
      zf_mkdir -p $shared 2>/dev/null
      print -r -- "$EPOCHSECONDS $answer" > $shared/modes.$$ 2>/dev/null && zf_mv -f $shared/modes.$$ $shared/modes 2>/dev/null
    fi
  fi
  case $answer in
    [01]' '[01])
      if [[ $mode == shuffle ]]; then s=${answer% *}; else s=${answer#* }; fi
      if [[ $s == 1 ]]; then REPLY=on; else REPLY=off; fi
      tell "" ;;
    '!-600'|'!-609') REPLY=off ;;
    '!-1744')        REPLY=off; tell "shows nothing until the agent may control Spotify: tap a Spotify button once" ;;
    '!-1743')        REPLY=off; tell "The agent may not control Spotify: allow it in System Settings → Privacy & Security → Automation" ;;
    *)               REPLY=keep; tell "Spotify did not tell the mode: ${answer[1,200]}" ;;
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

# post on|off → 0 when the agent took it. Off is the button's own look.
post() {
  local json out code
  if [[ $1 == on ]]; then json="{\"cellId\":\"$cell\",\"color\":\"$green\"}"
  else json="{\"cellId\":\"$cell\",\"reset\":true}"; fi
  out=$(curl -q -s -m 5 -w '\n%{http_code}' "$api/update-button" \
    --variable '%DESMAPTIC_TOKEN=' --expand-header 'Authorization: Bearer {{DESMAPTIC_TOKEN}}' \
    -H "Content-Type: application/json" -d "$json")
  code=${out##*$'\n'}
  [[ $code == 200 ]] && return 0
  print -ru2 -- "Spotify $mode: update-button answered ${code:-nothing}: ${${out%$'\n'*}[1,300]}"
  return 1
}

typeset -F next_at=0 quick_until=0
shown=""                                        # on or off as the phone shows it; "" before the first post
urgent=0                                        # a tap: this button's own question, not the other's answer
while true; do
  if [[ -n $dir && -e $dir/changed ]]; then     # a tap: ask now, then every second for a moment —
    zf_rm -f $dir/changed 2>/dev/null           # Spotify may take a beat to switch
    next_at=0 quick_until=$(( EPOCHREALTIME + 3 )) urgent=1
  fi
  if (( EPOCHREALTIME >= next_at )); then
    (( next_at = EPOCHREALTIME + (EPOCHREALTIME < quick_until ? 1 : period) ))
    (( EPOCHREALTIME < quick_until )) || urgent=0
    if visible; then
      read_mode $urgent
      if [[ $REPLY != keep && $REPLY != "$shown" ]]; then
        if post $REPLY; then shown=$REPLY; else (( next_at = EPOCHREALTIME + 10 )); fi
      fi
    fi
  fi
  zselect -t 25                                 # a quarter of a second, without starting a process
done
