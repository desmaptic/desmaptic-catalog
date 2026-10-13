# Snow, the tap: lets it snow on the Mac's screen, or stops the snow. The button's live loop (its startup
# script) does the drawing; the tap only leaves it a note: $dir/until holds the second the snow ends by itself,
# snow_minutes from now, and no file means no snow. The file is replaced in one step, so the loop never reads half
# a line. Returns at once. A failure is exit 1 with one line on stderr: the phone shakes the button.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT
snow_minutes=10                                 # the snow stops by itself after this long
zmodload zsh/datetime || { print -u2 -- "snow: zsh module datetime is missing"; exit 1 }
zmodload -F zsh/files b:zf_mkdir b:zf_mv b:zf_rm || { print -u2 -- "snow: zsh module files is missing"; exit 1 }

cell="{{CELL_ID}}"
dir="${DESMAPTIC_STORAGE:-$HOME/Library/Application Support/Desmaptic/ScriptStorage}/gallery/$cell"
until_file="$dir/until"

# Snowing now: the file holds a second still ahead (the rule the loop follows) — then this tap stops it.
line=""
{ IFS= read -r line < $until_file } 2>/dev/null
if [[ $line == <-> ]] && (( ${#line} <= 12 && line > EPOCHSECONDS && line <= EPOCHSECONDS + 86400 )); then
  zf_rm -f -- $until_file 2>/dev/null || { print -u2 -- "snow: could not stop it: $dir is not writable"; exit 1 }
  exit 0
fi

zf_mkdir -p -- $dir 2>/dev/null
{ print -r -- $(( EPOCHSECONDS + snow_minutes * 60 )) > "$until_file.$$" } 2>/dev/null &&
  zf_mv -f -- "$until_file.$$" $until_file 2>/dev/null ||
  { zf_rm -f -- "$until_file.$$" 2>/dev/null; print -u2 -- "snow: could not start it: $dir is not writable"; exit 1 }
exit 0
