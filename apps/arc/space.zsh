# Arc › Go to Space: switches the front Arc window to the Space named on the button's first line, through Arc's own
# AppleScript ("focus" on a space). It works with Arc in the background, leaves Arc where it is and never launches it;
# the first tap brings up the macOS question whether the agent may control Arc.
# The button's command is the line that sets the name, then this file (app.json):
#   "space=\"\"   # ← …\n@file:space.zsh"
# Until the name is set, the button refuses and says where to set it. The name is the Space's title as the sidebar
# shows it: the first Space with exactly that title wins, then the first whose title differs only in case.
setopt extended_glob
space=${${space##[[:space:]]##}%%[[:space:]]##}
[[ -n $space ]] || { print -u2 -- "Go to Space: type the Space’s name in this button’s settings, space=\"…\""; exit 1 }
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# pgrep sees every account's processes; -U keeps it to this one, whose Arc the AppleScript talks to.
pgrep -xqU $UID Arc || { print -u2 -- "Arc is not running"; exit 1 }

# Prints nothing, or "!<why not>". The name is an argument — data, never pasted into the script text, and passed after
# "--", so a name that starts with a dash is not taken for an option of osascript. The window is the first that lists
# Spaces: only a window that provably has none (Arc counts 0) is skipped, while a count that fails is a refusal — the
# button never switches a window behind the one the user looks at. Its Spaces are read one by one and named again by
# their place in the same request as "focus": Arc 1.166 returns references it cannot resolve again
# (apps/arc/action.zsh), so none is kept. Names that can't be read make the refusal say so, not blame the name typed.
read -r -d '' script <<'OSA'
on run argv
	set wanted to item 1 of argv
	if not (application id "company.thebrowser.Browser" is running) then return "!Arc is not running"
	with timeout of 10 seconds
		tell application id "company.thebrowser.Browser"
			set windowCount to 0
			repeat with candidate in windows
				set windowCount to windowCount + 1
				try
					set spaceCount to count of spaces of candidate
				on error
					return "!Arc did not list the Spaces of its window " & windowCount
				end try
				if spaceCount > 0 then
					set titles to {}
					set unread to 0
					repeat with i from 1 to spaceCount
						set spaceTitle to missing value
						try
							set spaceTitle to title of space i of candidate
						end try
						if spaceTitle is missing value then
							set unread to unread + 1
							set spaceTitle to ""
						end if
						set end of titles to spaceTitle
					end repeat
					if unread is spaceCount then return "!Arc did not give the names of its Spaces"
					set chosen to 0
					considering case
						repeat with i from 1 to spaceCount
							if item i of titles is wanted then
								set chosen to i
								exit repeat
							end if
						end repeat
					end considering
					if chosen is 0 then
						ignoring case
							repeat with i from 1 to spaceCount
								if item i of titles is wanted then
									set chosen to i
									exit repeat
								end if
							end repeat
						end ignoring
					end if
					if chosen is 0 then
						if unread > 0 then return "!Arc has no Space named “" & wanted & "” among the names it gave"
						return "!Arc has no Space named “" & wanted & "”"
					end if
					focus space chosen of candidate
					return ""
				end if
			end repeat
		end tell
	end timeout
	if windowCount > 0 then return "!No Arc window shows Spaces"
	return "!No Arc window is open"
end run
OSA

if ! answer=$(osascript -e "$script" -- "$space" 2>&1) || [[ $answer == '!'* ]]; then
  case $answer in
    '!'*)    print -ru2 -- "${answer#!}" ;;   # first: the script's own refusal may quote the name, digits and all
    *-1743*) print -u2 -- "The agent may not control Arc: allow it in System Settings → Privacy & Security → Automation" ;;
    *-600*)  print -u2 -- "Arc is not running" ;;
    *-1712*) print -u2 -- "Arc did not answer" ;;
    *)       print -ru2 -- "Arc did not take the command: ${answer##*execution error: }" ;;
  esac
  exit 1
fi
exit 0
