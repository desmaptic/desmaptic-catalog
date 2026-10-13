# Arc › Back, Forward, Refresh and Copy URL, through Arc's own AppleScript: they work with Arc in the background and
# whatever its keyboard shortcuts are, and they never launch Arc. The first tap brings up the macOS question
# whether the agent may control Arc.
# Every button's command is one line that names its action, then this file (app.json):
#   "action=back\n@file:action.zsh"   — back, forward, refresh, copy-url or copy-markdown.
# All five act on the current tab of the front Arc window and leave Arc where it is. Back and Forward also spare the
# bracket keys of ⌘[ and ⌘], which many layouts type only with Option or Shift. The clipboard is set by osascript
# itself, so a title in any script survives (pbcopy would read it in the C locale).
[[ $action == (back|forward|refresh|copy-url|copy-markdown) ]] || { print -u2 -- "Arc: unknown action \"$action\""; exit 1 }
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# pgrep sees every account's processes; -U keeps it to this one, whose Arc the AppleScript talks to.
pgrep -xqU $UID Arc || { print -u2 -- "Arc is not running"; exit 1 }

# Prints nothing, or "!<why not>". The front window is the first browser window: one with tabs, or with a Space —
# a Space with no tabs left still makes its window the one the user looks at. Its current tab is the one used: when
# that tab can't be read, the button says so rather than falling through to a window behind it and acting on a page
# the user isn't looking at.
read -r -d '' script <<'OSA'
on run argv
	set act to item 1 of argv
	if not (application id "company.thebrowser.Browser" is running) then return "!Arc is not running"
	set pageURL to missing value
	set pageTitle to missing value
	set found to false
	with timeout of 10 seconds
		tell application id "company.thebrowser.Browser"
			repeat with candidate in windows
				set isBrowser to false
				try
					set isBrowser to ((count of tabs of candidate) > 0)
				end try
				if not isBrowser then
					try
						set isBrowser to ((active space of candidate) is not missing value)
					end try
				end if
				if isBrowser then
					set found to true
					-- The tab is always named in the same request ("URL of active tab of candidate"), never kept in a
					-- variable: the reference Arc 1.166 returns for "active tab" names its container with an empty class
					-- code, and Arc itself cannot resolve it again — "go back", "URL of" on it failed with
					-- "Can't make «class tAbB» id … of «class     » id …" (seen 2026-09-27).
					try
						set pageURL to URL of active tab of candidate
					on error
						return "!The front Arc window shows no page"
					end try
					if act is "back" then
						go back active tab of candidate
					else if act is "forward" then
						go forward active tab of candidate
					else if act is "refresh" then
						reload active tab of candidate
					else
						try
							set pageTitle to title of active tab of candidate
						end try
					end if
					exit repeat
				end if
			end repeat
		end tell
	end timeout
	if not found then return "!No Arc window is open"
	if act is "back" or act is "forward" or act is "refresh" then return ""
	if pageURL is missing value or pageURL is "" then return "!The front Arc tab shows no page"
	if pageTitle is missing value or pageTitle is "" then set pageTitle to pageURL
	if act is "copy-url" then
		set the clipboard to pageURL
	else
		-- [title](address): brackets in the title are escaped, parentheses and spaces in the address encoded.
		set label to my swap(my swap(my swap(pageTitle, "\\", "\\\\"), "[", "\\["), "]", "\\]")
		set label to my swap(my swap(label, return, " "), linefeed, " ")
		set target to my swap(my swap(my swap(pageURL, " ", "%20"), "(", "%28"), ")", "%29")
		set the clipboard to "[" & label & "](" & target & ")"
	end if
	return ""
end run

on swap(theText, oldPart, newPart)
	set saved to AppleScript's text item delimiters
	set AppleScript's text item delimiters to oldPart
	set pieces to text items of theText
	set AppleScript's text item delimiters to newPart
	set theText to pieces as text
	set AppleScript's text item delimiters to saved
	return theText
end swap
OSA

if ! answer=$(osascript -e "$script" $action 2>&1) || [[ $answer == '!'* ]]; then
  case $answer in
    *-1743*) print -u2 -- "The agent may not control Arc: allow it in System Settings → Privacy & Security → Automation" ;;
    *-600*)  print -u2 -- "Arc is not running" ;;
    *-1712*) print -u2 -- "Arc did not answer" ;;
    '!'*)    print -ru2 -- "${answer#!}" ;;
    *)       print -ru2 -- "Arc did not take the command: ${answer##*execution error: }" ;;
  esac
  exit 1
fi
exit 0
