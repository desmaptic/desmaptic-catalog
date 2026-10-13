#!/bin/zsh
# Long Jobs, the long press: stops the top job the face shows that can be stopped, and only that one. The live loop
# leaves it in $dir/stop: "pid <pid> <process name>" — a program of the job list, interrupted (Ctrl-C) only while that
# pid still runs the same program; "tm" — the Time Machine backup (tmutil stopbackup), only while one runs. A job that
# has ended since is not replaced by another: the press refuses and the face is looked at again. Builds in Xcode
# itself and AI sessions are not stopped from here. Either way it leaves $dir/poke, so the face shows the change at once.
emulate -R zsh
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 1' TERM INT
cell="{{CELL_ID}}"
dir="${DESMAPTIC_STORAGE:-$HOME/Library/Application Support/Desmaptic/ScriptStorage}/gallery/$cell"

if [[ ! -r $dir/stop ]]; then
  print -u2 -- "long-jobs: nothing to stop: the face shows no program of the job list and no backup"
  exit 1
fi
entry=${"$(<$dir/stop)"%%$'\n'*}   # the first line only
w=( ${=entry} )
stopped=0
case $w[1] in
  pid)
    if [[ $w[2] == <-> ]] && (( $#w >= 3 )); then
      name=$(ps -co comm= -p $w[2] 2>/dev/null)
      name=${${name##[[:space:]]#}%%[[:space:]]#}
      [[ $name == ${(j: :)w[3,-1]} ]] && kill -INT $w[2] 2>/dev/null && stopped=1
    fi
    ;;
  tm)
    [[ $(tmutil status 2>/dev/null) == *'Running = 1;'* ]] && tmutil stopbackup >/dev/null 2>&1 && stopped=1
    ;;
esac
: > "$dir/poke"
(( stopped )) && exit 0
print -u2 -- "long-jobs: nothing stopped: the job on the face has ended"
exit 1
