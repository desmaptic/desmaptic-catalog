# Reactions, the tap: sends a burst of the emoji on the button up the Mac's screen. The button's live loop (its startup
# script) and the overlay it keeps draw it; the tap only leaves an empty file in $dir/taps, named by the time of the
# tap, and returns at once. A failure is exit 1 with one line on stderr: the phone shakes the button.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT
zmodload zsh/datetime || { print -u2 -- "reactions: zsh module datetime is missing"; exit 1 }
zmodload -F zsh/files b:zf_mkdir || { print -u2 -- "reactions: zsh module files is missing"; exit 1 }

cell="{{CELL_ID}}"
dir="${DESMAPTIC_STORAGE:-$HOME/Library/Application Support/Desmaptic/ScriptStorage}/gallery/$cell"

# Nothing would draw the burst without the loop: say so instead of leaving a note nobody reads.
pid=""
{ IFS= read -r pid < $dir/loop } 2>/dev/null
[[ $pid == <-> ]] && kill -0 $pid 2>/dev/null ||
  { print -u2 -- "reactions: the button's startup script is not running"; exit 1 }

zf_mkdir -p -- $dir/taps 2>/dev/null
{ : > "$dir/taps/$EPOCHREALTIME.$$" } 2>/dev/null || { print -u2 -- "reactions: cannot write in $dir"; exit 1 }
exit 0
