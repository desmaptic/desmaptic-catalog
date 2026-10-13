#!/bin/zsh
# World Clock: switch to the next city; the widget's own loop shows it within half a second
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# The same order as the table in the startup script.
codes=(LON NYC SFO TYO DXB SIN SYD PAR BER MOW IST HKG)
dir="${DESMAPTIC_STORAGE:-$HOME/Library/Application Support/Desmaptic/ScriptStorage}/gallery/{{CELL_ID}}"
mkdir -p "$dir" || exit 1

current=""
{ read -r current < "$dir/city" } 2>/dev/null
i=${codes[(Ie)$current]}
(( i == 0 )) && i=${codes[(Ie)NYC]}
print -r -- ${codes[i % $#codes + 1]} > "$dir/city.tmp" && mv -f "$dir/city.tmp" "$dir/city"
