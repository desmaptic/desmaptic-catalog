# Fireworks, the tap: a salvo of rockets over the display the pointer is on. The button's live loop (its startup
# script) and the overlay it keeps draw it; the tap only leaves an empty file in $dir/shows, named by the time of the
# tap and the kind of show, and returns at once. A failure is exit 1 with one line on stderr: the phone shakes the button.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT
zmodload zsh/datetime || { print -u2 -- "fireworks: zsh module datetime is missing"; exit 1 }
zmodload -F zsh/files b:zf_mkdir || { print -u2 -- "fireworks: zsh module files is missing"; exit 1 }

cell="{{CELL_ID}}"
dir="${DESMAPTIC_STORAGE:-$HOME/Library/Application Support/Desmaptic/ScriptStorage}/gallery/$cell"

# Nothing would draw the show without the loop: say so instead of leaving a note nobody reads.
pid=""
{ IFS= read -r pid < $dir/loop } 2>/dev/null
[[ $pid == <-> ]] && kill -0 $pid 2>/dev/null ||
  { print -u2 -- "fireworks: the button's startup script is not running"; exit 1 }

zf_mkdir -p -- $dir/shows 2>/dev/null
{ : > "$dir/shows/$EPOCHREALTIME.$$.salvo" } 2>/dev/null || { print -u2 -- "fireworks: cannot write in $dir"; exit 1 }
exit 0
