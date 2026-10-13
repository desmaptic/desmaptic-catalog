# Garland: nothing to edit here. The modes, the timer and the colours are the first lines of the button's startup script.
emulate -R zsh
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT
zmodload zsh/datetime || { print -u2 -- "garland: zsh module datetime is missing"; exit 1 }
zmodload -F zsh/files b:zf_mkdir b:zf_mv b:zf_rm || { print -u2 -- "garland: zsh module files is missing"; exit 1 }

cell="{{CELL_ID}}"
dir="${DESMAPTIC_STORAGE:-$HOME/Library/Application Support/Desmaptic/ScriptStorage}/gallery/$cell"
on_file="$dir/on"

pid=""
{ IFS= read -r pid < $dir/loop } 2>/dev/null
[[ $pid == <-> ]] && kill -0 $pid 2>/dev/null ||
  { print -u2 -- "garland: the button's startup script is not running"; exit 1 }

line=""
{ IFS= read -r line < $on_file } 2>/dev/null
if [[ $line == <-> ]] && (( ${#line} <= 12 && line <= EPOCHSECONDS + 5 && line > EPOCHSECONDS - 7 * 86400 )); then
  zf_rm -f -- $on_file 2>/dev/null || { print -u2 -- "garland: could not put it out: $dir is not writable"; exit 1 }
  exit 0
fi

zf_mkdir -p -- $dir 2>/dev/null
{ print -r -- $EPOCHSECONDS > "$on_file.$$" } 2>/dev/null &&
  zf_mv -f -- "$on_file.$$" $on_file 2>/dev/null ||
  { zf_rm -f -- "$on_file.$$" 2>/dev/null; print -u2 -- "garland: could not light it: $dir is not writable"; exit 1 }
exit 0
