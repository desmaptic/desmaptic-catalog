# Spotify › every button of the page but Search: playback, Shuffle, Repeat, volume, seeking and Copy Link, through
# Spotify's own AppleScript — it works with Spotify in the background and whatever its keyboard shortcuts are, and it
# never launches Spotify. The first tap brings up the macOS question whether the agent may control Spotify.
# Every button's command is one line that names its action, then this file (app.json):
#   "action=next\n@file:player/action.zsh"
# Shuffle and Repeat then ask their button's loop (toggle/live.zsh) to show the new state at once.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
[[ $action == (previous|playpause|next|shuffle|repeat|volume-down|volume-up|restart|back|forward|copy-link) ]] \
  || { print -u2 -- "Spotify: unknown action \"$action\""; exit 1 }
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
zmodload -F zsh/files b:zf_mkdir

# pgrep sees every account's processes; -U keeps it to this one, whose Spotify the AppleScript talks to.
pgrep -xqU $UID Spotify || { print -u2 -- "Spotify is not running"; exit 1 }

# Volume: Spotify's own, 0…100, in steps of 10 from the nearest step (47 set with the slider goes to 60 or 40).
# Seeking: 15 s, as Spotify's podcast buttons.
read -r -d '' script <<'OSA'
on run argv
	set act to item 1 of argv
	if not (application id "com.spotify.client" is running) then return "!Spotify is not running"
	tell application id "com.spotify.client"
		with timeout of 10 seconds -- a hung Spotify: -1712, not the tap's 60 s limit
			if act is "playpause" then
				playpause
			else if act is "next" then
				next track
			else if act is "previous" then
				previous track
			else if act is "shuffle" then
				set shuffling to not shuffling
			else if act is "repeat" then
				set repeating to not repeating
			else if act is "volume-up" or act is "volume-down" then
				set v to ((sound volume + 5) div 10) * 10
				if act is "volume-up" then
					set v to v + 10
				else
					set v to v - 10
				end if
				if v > 100 then set v to 100
				if v < 0 then set v to 0
				set sound volume to v
			else
				if player state is stopped then return "!Nothing is playing in Spotify"
				if act is "copy-link" then
					return spotify url of current track
				else if act is "restart" then
					set player position to 0
				else if act is "back" then
					set p to (player position) - 15
					if p < 0 then set p to 0
					set player position to p
				else
					set player position to (player position) + 15
				end if
			end if
		end timeout
	end tell
	return ""
end run
OSA

if ! answer=$(osascript -e "$script" $action 2>&1) || [[ $answer == '!'* ]]; then
  case $answer in
    *-1743*) print -u2 -- "The agent may not control Spotify: allow it in System Settings → Privacy & Security → Automation" ;;
    *-1712*) print -u2 -- "Spotify did not answer in time" ;;
    '!'*)    print -ru2 -- "${answer#!}" ;;
    *)       print -ru2 -- "Spotify did not take the command: ${answer##*execution error: }" ;;
  esac
  exit 1
fi

# Copy Link: Spotify names the item "spotify:track:<id>" (or "spotify:episode:<id>"); the link anyone can open is
# https://open.spotify.com/track/<id>. A local file or an ad has none.
if [[ $action == copy-link ]]; then
  if [[ $answer =~ '^spotify:(track|episode):([A-Za-z0-9]+)$' ]]; then
    answer="https://open.spotify.com/$match[1]/$match[2]"
  elif [[ ! $answer =~ '^https://open\.spotify\.com/(track|episode)/[A-Za-z0-9]+' ]]; then
    print -u2 -- "What Spotify is playing has no link to share (a local file or an ad)"
    exit 1
  fi
  print -rn -- $answer | pbcopy || { print -u2 -- "The link could not be put on the clipboard"; exit 1 }
  exit 0
fi

# Shuffle and Repeat: the button's loop reads the new state now instead of within 4 s.
if [[ $action == (shuffle|repeat) && -n $DESMAPTIC_STORAGE ]]; then
  dir="$DESMAPTIC_STORAGE/gallery/{{CELL_ID}}"
  zf_mkdir -p "$dir" 2>/dev/null
  : > "$dir/changed" 2>/dev/null
fi
exit 0
