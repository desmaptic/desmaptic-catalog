# Xcode › Scheme and Run Destination: makes a scheme, or a run destination, the active one of the front Xcode project,
# so the next Build, Run or Test uses it. Xcode's own AppleScript properties (`active scheme`, `active run destination`
# of the workspace document): it works with Xcode in the background, and it never launches Xcode. The first tap brings
# up the macOS question whether the agent may control Xcode.
# The button's first line is the setting the user edits, then this file (app.json):
#   "scheme=\"\"   # ← …\n@file:scheme/active.zsh"        — the scheme's name, as Xcode lists it
#   "destination=\"\"   # ← …\n@file:scheme/active.zsh"   — the run destination's name, as Xcode shows it
# While the setting is empty, the tap refuses and says what to write; a name Xcode does not have is a refusal that
# lists the names it does have. Run destinations often share a name — an iPhone of each installed iOS runtime — so of
# those the one with the newest system is taken, and "iPhone 17 Pro (26.4)" picks the one whose system is 26.4 (or
# 26.4.x). Terms read from the dictionary of Xcode 27.0, the same in Xcode 27.1 beta (2026-10-12): active scheme,
# active run destination, scheme, run destination › device (rdev) › operating system version.
emulate -R zsh
if (( ${+scheme} )); then
  kind=scheme value=$scheme example=MyApp
elif (( ${+destination} )); then
  kind=destination value=$destination example='iPhone 17 Pro'
else
  print -u2 -- "Xcode: the button names no scheme or run destination"; exit 1
fi
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

[[ -n $value ]] || { print -ru2 -- "Write the $kind in the first line of the button’s script: $kind=\"$example\""; exit 1 }
# "iPhone 17 Pro (26.4)": the name, then the system version — tried when no destination has the whole text as its name.
base="" version=""
[[ $kind == destination && $value =~ '^(.+) \(([0-9]+(\.[0-9]+)*)\)$' ]] && base=$match[1] version=$match[2]

# pgrep sees every account's processes; -U keeps it to this one, whose Xcode the AppleScript talks to.
pgrep -xqU $UID Xcode || { print -u2 -- "Xcode is not running"; exit 1 }

# Prints "" once set, "?<the names there are>" for a name Xcode does not have, or "!<why not>". Names compare as
# AppleScript compares text: case does not matter.
read -r -d '' script <<'OSA'
on run argv
	set kind to item 1 of argv
	set wanted to item 2 of argv
	if not (application id "com.apple.dt.Xcode" is running) then return "!Xcode is not running"
	tell application id "com.apple.dt.Xcode"
		set ws to active workspace document
		if ws is missing value then return "!No project is open in Xcode"
		if not (loaded of ws) then return "!The project is still opening in Xcode"
		if kind is "scheme" then
			try
				set found to first scheme of ws whose name is wanted
			on error
				return "?" & my joined(name of schemes of ws)
			end try
			set active scheme of ws to found
		else
			-- Of those named so, the newest system; v > foundVersion compares "27.1" and "26.4" as numbers.
			set wantedBase to item 3 of argv
			set wantedVersion to item 4 of argv
			set found to missing value
			set foundVersion to ""
			set allNames to {}
			repeat with d in (get run destinations of ws)
				set dest to contents of d
				set n to name of dest
				if allNames does not contain n then set end of allNames to n
				set v to ""
				-- The property `device` (rdev) shares its name with the class `device` (devc), and AppleScript compiles the
				-- name to the class: hence the raw code.
				try
					set v to operating system version of («property rdev» of dest)
				end try
				if v is missing value then set v to ""
				set fits to (n is wanted)
				if not fits and wantedVersion is not "" then set fits to (n is wantedBase and (v is wantedVersion or v starts with (wantedVersion & ".")))
				if fits then
					considering numeric strings
						if found is missing value or v > foundVersion then
							set found to dest
							set foundVersion to v
						end if
					end considering
				end if
			end repeat
			if found is missing value then return "?" & my joined(allNames)
			set active run destination of ws to found
		end if
	end tell
	return ""
end run

on joined(names)
	set saved to AppleScript's text item delimiters
	set AppleScript's text item delimiters to ", "
	set s to names as text
	set AppleScript's text item delimiters to saved
	return s
end joined
OSA

if ! answer=$(osascript -e "$script" $kind "$value" "$base" "$version" 2>&1) || [[ $answer == ['!?']* ]]; then
  case $answer in
    *-1743*) print -u2 -- "The agent may not control Xcode: allow it in System Settings → Privacy & Security → Automation" ;;
    '!'*)    print -ru2 -- "${answer#!}" ;;
    '?')     print -ru2 -- "The front Xcode project has no ${kind}s" ;;
    '?'*)    [[ $kind == scheme ]] && there=Schemes || there='Run destinations'
             print -ru2 -- "Xcode has no $kind “$value”. $there: ${${answer#\?}[1,200]}" ;;
    *)       print -ru2 -- "Xcode did not take the $kind: ${${answer##*execution error: }[1,200]}" ;;
  esac
  exit 1
fi
exit 0
