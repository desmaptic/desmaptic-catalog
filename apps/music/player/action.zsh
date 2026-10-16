# Music › every button of the page that plays or sets something: playback, Shuffle, Repeat, Favorite, Dislike & Skip,
# the volume, Favorite Songs, a playlist of the user's and the AirPlay speaker, through Music's own AppleScript — it
# works with Music in the background and whatever its keyboard shortcuts are, and it never launches Music. The first
# tap brings up the macOS question whether the agent may control Music.
# Every button's command is one line that names its action, then this file (app.json):
#   "action=next\n@file:player/action.zsh"
# Play Playlist and AirPlay Speaker start with the user's setting, the line they edit:
#   "playlist=\"\"   # ← …\naction=playlist\n@file:player/action.zsh"   — a playlist's name, as Music lists it
#   "speaker=\"\"   # ← …\naction=airplay\n@file:player/action.zsh"     — an AirPlay device's name, as Music shows it
# While the setting is empty, the tap refuses and says what to write. AirPlay Speaker's long press is
# "action=computer": the music goes back to this Mac.
# After a change it leaves the time in $DESMAPTIC_STORAGE/gallery/music/poke: the live Shuffle, Repeat and Favorite
# buttons (toggle/live.zsh) then read Music at once instead of within 5 s — Next changes the song, and with it the star.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
setopt extended_glob
[[ $action == (previous|playpause|next|shuffle|repeat|favorite|dislike|volume-down|volume-up|favorite-songs|playlist|airplay|computer) ]] \
  || { print -u2 -- "Music: unknown action \"$action\""; exit 1 }
# The name the user set, without the spaces around it.
name=""
case $action in
  playlist) name=${${playlist##[[:space:]]##}%%[[:space:]]##}
            [[ -n $name ]] || { print -u2 -- "Write the playlist’s name in this button’s settings: playlist=\"Focus\""; exit 1 } ;;
  airplay)  name=${${speaker##[[:space:]]##}%%[[:space:]]##}
            [[ -n $name ]] || { print -u2 -- "Write the AirPlay speaker’s name, as Music shows it, in this button’s settings: speaker=\"Living Room\""; exit 1 } ;;
  computer) name=$(/usr/sbin/scutil --get ComputerName 2>/dev/null) ;;   # tells this Mac from other Macs (below)
esac
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
zmodload zsh/datetime
zmodload -F zsh/files b:zf_mkdir b:zf_mv

# By bundle id, not by process name: an iOS simulator runs its own "Music" under this account, and pgrep would
# take it for the Mac's. lsappinfo prints the pid of this account's Music app, nothing when it is not running.
[[ $(lsappinfo info -only pid -app com.apple.Music 2>/dev/null) == *'"pid"='<1->* ]] \
  || { print -u2 -- "Music is not running"; exit 1 }

# Prints nothing, or "!<why not>". Volume: Music's own, 0…100, in steps of 10 from the nearest step. Repeat goes
# Off → All → One → Off, as Music's own button. Favorite Songs is the playlist Music fills with the songs marked with
# its star; its name depends on the language of the Apple Account ("Favourite Songs" in British English), so it is
# found by its English names first and otherwise as the smart playlist whose songs are all favorites (preferring one
# that is a favorite itself, as Music's own is). "favorited" is the star of Music 1.6 (older Music called it "loved");
# "disliked" is what Music 1.6 calls Suggest Less. Names the user set compare as AppleScript compares text: case does
# not matter; a playlist is the user's own first, then one added from Apple Music. The AirPlay speaker becomes the
# only one Music plays to. A speaker's name Music does not know is a refusal that lists the names it does know.
# "computer" is this Mac's own output, a device of kind computer: other Macs of the same Apple Account can be AirPlay
# receivers too, so when Music lists several of that kind, the one named as this Mac (System Settings › General ›
# About) is taken, and without one the hold refuses and lists them rather than send the music to another Mac.
read -r -d '' script <<'OSA'
on run argv
	set act to item 1 of argv
	set wanted to item 2 of argv
	if not (application id "com.apple.Music" is running) then return "!Music is not running"
	tell application id "com.apple.Music"
		with timeout of 10 seconds -- a hung Music: -1712, not the tap's 60 s limit
			if act is "playpause" then
				playpause
			else if act is "next" then
				next track
			else if act is "previous" then
				previous track
			else if act is "shuffle" then
				set shuffle enabled to not shuffle enabled
			else if act is "repeat" then
				set r to song repeat
				if r is off then
					set song repeat to all
				else if r is all then
					set song repeat to one
				else
					set song repeat to off
				end if
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
			else if act is "favorite" then
				if player state is stopped then return "!Nothing is playing in Music"
				try
					set t to current track
					set favorited of t to not (favorited of t)
				on error msg number n
					if n is in {-1743, -1712, -600, -609} then error msg number n
					return "!Music cannot mark what is playing as a favorite: " & msg
				end try
			else if act is "dislike" then
				if player state is stopped then return "!Nothing is playing in Music"
				try
					set disliked of current track to true
				on error msg number n
					if n is in {-1743, -1712, -600, -609} then error msg number n
					return "!Music cannot mark what is playing as disliked: " & msg
				end try
				next track
			else if act is "playlist" then
				set found to (every user playlist whose name is wanted)
				if found is {} then
					try -- one from Apple Music, added to the library
						set found to (every subscription playlist whose name is wanted)
					end try
				end if
				if found is {} then return "!Music has no playlist named “" & wanted & "”"
				set p to item 1 of found
				if (count of tracks of p) is 0 then return "!The playlist “" & (name of p) & "” is empty"
				play p
			else if act is "airplay" then
				set found to (every AirPlay device whose name is wanted)
				if found is {} then
					set others to name of every AirPlay device
					if others is {} then return "!Music sees no AirPlay speaker named “" & wanted & "”"
					set AppleScript's text item delimiters to ", "
					set others to others as text
					set AppleScript's text item delimiters to ""
					return "!Music sees no AirPlay speaker named “" & wanted & "”, only: " & others
				end if
				set d to item 1 of found
				if not (available of d) then return "!“" & (name of d) & "” is not available: is it on and on this network?"
				set current AirPlay devices to {d}
			else if act is "computer" then
				set found to (every AirPlay device whose kind is computer)
				if found is {} then return "!Music lists no output of this Mac"
				if (count of found) > 1 then
					set mine to (every AirPlay device whose kind is computer and name is wanted)
					if mine is {} or wanted is "" then
						set AppleScript's text item delimiters to ", "
						set others to (name of every AirPlay device whose kind is computer) as text
						set AppleScript's text item delimiters to ""
						return "!Music lists several Macs (" & others & ") and none is named as this one: pick this Mac in Music’s AirPlay menu"
					end if
					set found to mine
				end if
				set current AirPlay devices to {item 1 of found}
			else
				set p to missing value
				repeat with n in {"Favorite Songs", "Favourite Songs"}
					set found to (every user playlist whose name is (contents of n) and smart is true)
					if found is not {} then
						set p to item 1 of found
						exit repeat
					end if
				end repeat
				if p is missing value then
					set fallback to missing value
					repeat with c in (every user playlist whose smart is true and special kind is none)
						set c to contents of c
						if (count of tracks of c) > 0 then
							if (count of (every track of c whose favorited is false)) is 0 then
								if favorited of c then
									set p to c
									exit repeat
								end if
								if fallback is missing value then set fallback to c
							end if
						end if
					end repeat
					if p is missing value then set p to fallback
				end if
				if p is missing value then return "!Music has no Favorite Songs playlist yet: mark a song with the star first"
				if (count of tracks of p) is 0 then return "!Favorite Songs is empty: mark a song with the star first"
				play p
			end if
		end timeout
	end tell
	return ""
end run
OSA

# The name is an argument — data, never pasted into the script text, and passed after "--", so a name that starts with
# a dash is not taken for an option of osascript.
if ! answer=$(osascript -e "$script" -- "$action" "$name" 2>&1) || [[ $answer == '!'* ]]; then
  case $answer in
    '!'*)    print -ru2 -- "${answer#!}" ;;   # first: the script's own refusal may quote a name, digits and all
    *-1743*) print -u2 -- "The agent may not control Music: allow it in System Settings → Privacy & Security → Automation" ;;
    *-1712*) print -u2 -- "Music did not answer in time" ;;
    *-600*)  print -u2 -- "Music is not running" ;;
    *)       print -ru2 -- "Music did not take the command: ${answer##*execution error: }" ;;
  esac
  exit 1
fi

# The live buttons read the new state now.
if [[ -n $DESMAPTIC_STORAGE ]]; then
  dir="$DESMAPTIC_STORAGE/gallery/music"
  zf_mkdir -p "$dir" 2>/dev/null
  print -r -- $EPOCHREALTIME > "$dir/poke.$$" 2>/dev/null && zf_mv -f "$dir/poke.$$" "$dir/poke" 2>/dev/null
fi
exit 0
