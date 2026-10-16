# Homebrew updates, the long press: asks the live loop (startup.zsh) to look again now — brew update, then the count —
# instead of at its next time. It only leaves $dir/poke; while an upgrade runs it refuses, and the count comes when
# the upgrade ends.
emulate -R zsh
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
trap 'exit 1' TERM INT
cell="{{CELL_ID}}"
dir="${DESMAPTIC_STORAGE:-$HOME/Library/Application Support/Desmaptic/ScriptStorage}/gallery/$cell"

if [[ -e $dir/running ]]; then
  print -u2 -- "Homebrew updates: brew upgrade is running: the count comes when it ends"
  exit 1
fi
mkdir -p -- "$dir" && : > "$dir/poke" || { print -u2 -- "Homebrew updates: cannot write $dir"; exit 1 }
