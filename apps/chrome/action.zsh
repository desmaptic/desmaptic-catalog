# Chrome › Back, Forward, Reload, New Tab, New Window, Incognito and Copy URL, through Chrome's own AppleScript: it works
# with Chrome in the background and whatever its keyboard shortcuts are, and it never launches Chrome. The first
# tap brings up the macOS question whether the agent may control Google Chrome.
# Every button's command is one line that names its action, then this file (app.json):
#   "action=back\n@file:action.zsh"   — back, forward, reload, new-tab, new-window, incognito, copy-url or copy-markdown.
# Back, Forward, Reload and the two copies act on the current tab of the front Chrome window and leave Chrome where it
# is; the three that open something bring Chrome forward, ready for an address or a search. The clipboard is set by
# osascript itself, so a title in any script survives (pbcopy would read it in the C locale).
[[ $action == (back|forward|reload|new-tab|new-window|incognito|copy-url|copy-markdown) ]] || { print -u2 -- "Chrome: unknown action \"$action\""; exit 1 }
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# pgrep sees every account's processes; -U keeps it to this one, whose Chrome the AppleScript talks to.
pgrep -xqU $UID "Google Chrome" || { print -u2 -- "Chrome is not running"; exit 1 }

# Prints nothing, or "!<why not>". Chrome lists its DevTools windows among its windows too, so the front
# window here is the first one whose tab is not DevTools.
read -r -d '' script <<'OSA'
on run argv
	set act to item 1 of argv
	if not (application id "com.google.Chrome" is running) then return "!Chrome is not running"
	set pageURL to missing value
	set pageTitle to missing value
	with timeout of 10 seconds
		tell application id "com.google.Chrome"
			if act is "new-window" then
				make new window
				activate
				return ""
			else if act is "incognito" then
				make new window with properties {mode:"incognito"}
				activate
				return ""
			end if
			set frontWindow to missing value
			repeat with candidate in windows
				try
					if (URL of active tab of candidate) does not start with "devtools:" then
						set frontWindow to contents of candidate
						exit repeat
					end if
				on error
					-- A copy never falls through to a window behind: it would copy a page the user isn't looking at.
					if act is "copy-url" or act is "copy-markdown" then return "!The front Chrome tab shows no page"
				end try
			end repeat
			if act is "new-tab" then
				if frontWindow is missing value then
					make new window
				else
					make new tab at end of tabs of frontWindow
				end if
				activate
				return ""
			end if
			if frontWindow is missing value then return "!No Chrome window is open"
			if act is "back" then
				go back active tab of frontWindow
			else if act is "forward" then
				go forward active tab of frontWindow
			else if act is "reload" then
				reload active tab of frontWindow
			else
				-- The tab of the window found above, never one behind it: a tab that can't be read is a refusal.
				try
					set pageURL to URL of active tab of frontWindow
				on error
					return "!The front Chrome tab shows no page"
				end try
				try
					set pageTitle to title of active tab of frontWindow
				end try
			end if
		end tell
	end timeout
	if act is not "copy-url" and act is not "copy-markdown" then return ""
	if pageURL is missing value or pageURL is "" then return "!The front Chrome tab shows no page"
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
    *-1743*) print -u2 -- "The agent may not control Chrome: allow it in System Settings → Privacy & Security → Automation" ;;
    *-600*)  print -u2 -- "Chrome is not running" ;;
    *-1712*) print -u2 -- "Chrome did not answer" ;;
    '!'*)    print -ru2 -- "${answer#!}" ;;
    *)       print -ru2 -- "Chrome did not take the command: ${answer##*execution error: }" ;;
  esac
  exit 1
fi
exit 0
