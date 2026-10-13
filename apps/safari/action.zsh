# Safari › Copy Link and Reading List, through Safari's own AppleScript: they work with Safari in the background and
# never launch it. The first tap brings up the macOS question whether the agent may control Safari.
# Every button's command is one line that names its action, then this file (app.json):
#   "action=copy-link\n@file:action.zsh"   — copy-link, copy-markdown or reading-list.
# All three act on the current tab of the front Safari window. Nothing is typed into Safari and Safari stays where it
# is; the clipboard is set by osascript itself, so a title in any script survives (pbcopy would read it in the C locale).
[[ $action == (copy-link|copy-markdown|reading-list) ]] || { print -u2 -- "Safari: unknown action \"$action\""; exit 1 }
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# pgrep sees every account's processes; -U keeps it to this one, whose Safari the AppleScript talks to.
pgrep -xqU $UID Safari || { print -u2 -- "Safari is not running"; exit 1 }

# Prints nothing, or "!<why not>". Safari lists its Settings window among its windows too, so the front window here is
# the first one that has tabs. Its current tab is the one read: when its address can't be read, the button says so
# rather than falling through to a window behind it and copying a page the user isn't looking at.
read -r -d '' script <<'OSA'
on run argv
	set act to item 1 of argv
	if not (application id "com.apple.Safari" is running) then return "!Safari is not running"
	set pageURL to missing value
	set pageTitle to missing value
	set found to false
	with timeout of 10 seconds
		tell application id "com.apple.Safari"
			repeat with candidate in windows
				set tabCount to 0
				try
					set tabCount to count of tabs of candidate
				end try
				if tabCount > 0 then
					set found to true
					try
						set theTab to current tab of candidate
						set pageURL to URL of theTab
						set pageTitle to name of theTab
					end try
					exit repeat
				end if
			end repeat
		end tell
	end timeout
	if not found then return "!No Safari window is open"
	if pageURL is missing value then return "!The front Safari tab shows no web page"
	if not (pageURL starts with "http://" or pageURL starts with "https://" or pageURL starts with "file://") then return "!The front Safari tab shows no web page"
	if pageTitle is missing value or pageTitle is "" then set pageTitle to pageURL
	if act is "reading-list" then
		if pageURL starts with "file://" then return "!Only a web page can go to the Reading List"
		with timeout of 10 seconds
			tell application id "com.apple.Safari" to add reading list item pageURL with title pageTitle
		end timeout
	else if act is "copy-link" then
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
    *-1743*) print -u2 -- "The agent may not control Safari: allow it in System Settings → Privacy & Security → Automation" ;;
    *-600*)  print -u2 -- "Safari is not running" ;;
    *-1712*) print -u2 -- "Safari did not answer" ;;
    '!'*)    print -ru2 -- "${answer#!}" ;;
    *)       print -ru2 -- "Safari did not take the command: ${answer##*execution error: }" ;;
  esac
  exit 1
fi
exit 0
