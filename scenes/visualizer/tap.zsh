#!/bin/zsh
# Visualizer key, tap: tells the visualizer's loop (the page's startup script) which key was tapped by writing
# "<this button's id> <time>" to $DESMAPTIC_STORAGE/gallery/visualizer/k-tap — a new file moved into place, so the
# loop never reads half a line. The loop decides what the tap means (show the controls, switch, power).
emulate -R zsh
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 0' TERM INT
zmodload zsh/datetime || { print -u2 -- "Visualizer: zsh module datetime is missing"; exit 1 }
zmodload -F zsh/files b:zf_mkdir b:zf_mv || { print -u2 -- "Visualizer: zsh module files is missing"; exit 1 }
[[ -n ${DESMAPTIC_STORAGE:-} ]] || { print -u2 -- "Visualizer: DESMAPTIC_STORAGE is not set"; exit 1 }
dir=$DESMAPTIC_STORAGE/gallery/visualizer
zf_mkdir -p $dir || exit 1
{ print -r -- "{{CELL_ID}} $EPOCHREALTIME" > $dir/k-tap.$$ && zf_mv -f $dir/k-tap.$$ $dir/k-tap } || exit 1
