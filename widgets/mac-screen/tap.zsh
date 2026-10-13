#!/bin/zsh
# Mac Screen tap: lock the Mac's screen; when it is already locked, nothing happens and nothing is reported
# The lock asks macOS's login session for it (SACLockScreenImmediate, what the menu's Lock Screen does), not a
# keystroke, so it needs no Accessibility. SCREEN_DRY=1 reads the registry from the file $SCREEN_IOREG and prints
# "lock" instead of locking.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT
zmodload -F zsh/files b:zf_mkdir || { print -u2 -- "mac-screen: zsh module files is missing"; exit 1 }

dry=${SCREEN_DRY:-0}
[[ $dry == 1 ]] || dry=0

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

dir="${DESMAPTIC_STORAGE:-$HOME/Library/Application Support/Desmaptic/ScriptStorage}/gallery/{{CELL_ID}}"

# A note for the widget's loop: look at the screen now, not in up to 15 s.
poke() { zf_mkdir -p "$dir" 2>/dev/null; : > "$dir/poke" 2>/dev/null }

console_state
if [[ $REPLY == locked* ]]; then
  poke
  exit 0
fi
if (( dry )); then
  print -r -- "lock"
  poke
  exit 0
fi
# A macOS that no longer has the call fails on bindFunction, before anything runs.
err=$(osascript -l JavaScript -e '
  ObjC.import("Foundation")
  if (!$.NSBundle.bundleWithPath("/System/Library/PrivateFrameworks/login.framework").load) throw new Error("login.framework did not load")
  ObjC.bindFunction("SACLockScreenImmediate", ["int", []])
  $.SACLockScreenImmediate()
  ""' 2>&1 < /dev/null > /dev/null)
rc=$?
poke
if (( rc != 0 )); then
  print -u2 -- "mac-screen: macOS did not lock the screen (exit $rc): ${err[1,200]}"
  exit 1
fi
exit 0
