#!/bin/zsh
# Aquarium tap: drop food at this tile. The engine (the page's startup script) reads the line, drops food above
# the tile and the fish swim to it; the crab gets what reaches the sand.
export LC_ALL=C
trap 'exit 0' TERM INT
dir="${DESMAPTIC_STORAGE:-$HOME/Library/Application Support/Desmaptic/ScriptStorage}/gallery/aquarium"
mkdir -p "$dir" && print -r -- "{{CELL_ID}}" >> "$dir/taps"
