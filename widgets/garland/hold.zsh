# Garland: nothing to edit here. The modes, the timer and the colours are the first lines of the button's startup script.
emulate -R zsh
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT
zmodload zsh/datetime || { print -u2 -- "garland: zsh module datetime is missing"; exit 1 }
zmodload -F zsh/files b:zf_mkdir || { print -u2 -- "garland: zsh module files is missing"; exit 1 }

cell="{{CELL_ID}}"
dir="${DESMAPTIC_STORAGE:-$HOME/Library/Application Support/Desmaptic/ScriptStorage}/gallery/$cell"

pid=""
{ IFS= read -r pid < $dir/loop } 2>/dev/null
[[ $pid == <-> ]] && kill -0 $pid 2>/dev/null ||
  { print -u2 -- "garland: the button's startup script is not running"; exit 1 }

zf_mkdir -p -- $dir/next 2>/dev/null
{ : > "$dir/next/$EPOCHREALTIME.$$" } 2>/dev/null || { print -u2 -- "garland: cannot write in $dir"; exit 1 }
exit 0
