#!/bin/zsh
# Mac Town tap: tells the engine (the page's startup script) which tile was tapped; a tap on a building switches to
# its app.
export LC_ALL=C
trap 'exit 0' TERM INT
dir="${DESMAPTIC_STORAGE:-$HOME/Library/Application Support/Desmaptic/ScriptStorage}/gallery/town"
mkdir -p "$dir" && print -r -- "{{CELL_ID}}" >> "$dir/taps"
