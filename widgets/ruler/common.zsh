# Ruler: what the tap, the long press and the live loop share. Functions only — every script of the button starts
# with this file (item.json): "@file:common.zsh\n@file:tap.zsh", "…hold.zsh", "…startup.zsh".
#
# A measurement is two files in the button's own folder; they are how the taps talk to the loop (startup.zsh):
#   anchor  "<x> <y> <epoch s>"                   the first tap: where the pointer was. There = measuring.
#   result  "<across> <up and down> <epoch s>"    the second tap: the size it copied, shown on the button a while.
# The taps write a file whole (put_file) and in an order that never leaves the loop with neither: the second tap
# writes the result before it removes the anchor, the first writes the anchor before it removes an old result.
#
# Positions are the Mac's global screen coordinates in points (NSEvent.mouseLocation: one space for all displays,
# its origin at the bottom left of the main one). Reading them needs no permission and asks no app anything.
# Only differences are used.

# Sets the paths, the timings and ruler_js; every script calls it first.
ruler_setup() {
  cell="{{CELL_ID}}"
  dir="${DESMAPTIC_STORAGE:-$HOME/Library/Application Support/Desmaptic/ScriptStorage}/gallery/$cell"
  anchor_file="$dir/anchor"
  result_file="$dir/result"
  anchor_life=600          # a first tap left without a second for 10 minutes is dropped
  result_life=15           # how long the copied size stays on the button
  zmodload zsh/datetime || { print -u2 -- "ruler: zsh module datetime is missing"; return 1 }
  zmodload -F zsh/files b:zf_mkdir b:zf_mv b:zf_rm || { print -u2 -- "ruler: zsh module files is missing"; return 1 }

  # JS shared by the second tap and the pointer reader: the button shows while measuring exactly what the
  # clipboard gets, rounded by one function. size(p, ax, ay) = "<across> <up and down>" from the start point to
  # the position p, whole points; distance(ax, ay) = the same to the pointer now.
  ruler_js='ObjC.import("AppKit");
function here() {
  const p = $.NSEvent.mouseLocation;
  return p.x.toFixed(2) + " " + p.y.toFixed(2);
}
function size(p, ax, ay) {
  return Math.round(Math.abs(p.x - ax)) + " " + Math.round(Math.abs(p.y - ay));
}
function distance(ax, ay) {
  return size($.NSEvent.mouseLocation, ax, ay);
}
function start(argv) {
  const x = Number(argv[0]), y = Number(argv[1]);
  if (argv.length !== 2 || !isFinite(x) || !isFinite(y)) throw new Error("no start point");
  return [x, y];
}'
  return 0
}

# REPLY = "<x> <y>" of the first tap when there is one younger than anchor_life. A stale or unreadable anchor
# is removed. Returns 1 without one.
read_anchor() {
  local line="" ; local -a f
  REPLY=""
  { IFS= read -r line < $anchor_file } 2>/dev/null || return 1
  f=( ${=line} )
  if (( $#f == 3 )) && [[ $f[1] == (|-)<->.<-> && $f[2] == (|-)<->.<-> && $f[3] == <-> ]] &&
     (( ${#f[1]} <= 12 && ${#f[2]} <= 12 && ${#f[3]} <= 12 && EPOCHSECONDS >= f[3] && EPOCHSECONDS - f[3] < anchor_life )); then
    REPLY="$f[1] $f[2]"
    return 0
  fi
  zf_rm -f -- $anchor_file
  return 1
}

# REPLY = "<across> <up and down>" the second tap copied, while it is younger than result_life. An older or
# unreadable result is removed. Returns 1 without one.
read_result() {
  local line="" ; local -a f
  REPLY=""
  { IFS= read -r line < $result_file } 2>/dev/null || return 1
  f=( ${=line} )
  if (( $#f == 3 )) && [[ $f[1] == <-> && $f[2] == <-> && $f[3] == <-> ]] &&
     (( ${#f[1]} <= 7 && ${#f[2]} <= 7 && ${#f[3]} <= 12 && EPOCHSECONDS >= f[3] && EPOCHSECONDS - f[3] < result_life )); then
    REPLY="$f[1] $f[2]"
    return 0
  fi
  zf_rm -f -- $result_file
  return 1
}

# put_file <path> <line>: replaces the file in one step, so a reader never sees half a line.
put_file() {
  zf_mkdir -p -- $dir 2>/dev/null
  print -r -- "$2" > "$1.$$" && zf_mv -f -- "$1.$$" "$1"
}
