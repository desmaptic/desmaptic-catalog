# Claude › Quick Entry: presses Claude's menu bar icon through System Events, which is what a click on it does — Claude
# (2.7032.0, and 2.9939.2 through its native overlay's toggle) answers a click on that icon by opening Quick Entry over
# the app in front, or closing it if it is open (its main process: the tray's "click" handler; signed out, it shows the
# main window instead). Quick Entry's own keyboard shortcut is one each user sets or turns off (double-tap Option by
# default), so no keystroke can be relied on; the icon is there unless the user turned off "Menu bar" in Claude's
# settings. The press reaches Claude through the icon's accessibility action, which Electron 44 routes to the same click
# (VoiceOver uses it), so it works with Claude in the background and whatever app is in front. It needs Accessibility,
# and the first tap brings up the macOS question about controlling System Events. It never launches Claude. The
# button's command is this file (app.json).
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# By bundle id, not pgrep by name: an iOS simulator runs its apps under this account too, and Claude for iPhone in one
# would be a "Claude" process as well. lsappinfo asks this login session only — the one whose Claude System Events
# sees — and prints "pid"=<n> for a running app, nothing for one that is not.
[[ $(lsappinfo info -only pid -app com.anthropic.claudefordesktop 2>/dev/null) == *'"pid"='<->* ]] ||
  { print -u2 -- "Claude is not running"; exit 1 }

# Prints nothing, or "!<why not>". Claude has one menu bar icon (menu bar 2 is an app's status items); should a later
# version show more than one, the script refuses rather than guess which.
read -r -d '' script <<'OSA'
on run argv
	tell application "System Events"
		set found to (application processes whose bundle identifier is "com.anthropic.claudefordesktop")
		if found is {} then return "!Claude is not running"
		tell item 1 of found
			if not (exists menu bar 2) then return "!Claude's icon is not in the menu bar: turn on Menu bar in Claude's settings and allow Claude in System Settings › Menu Bar"
			set icons to menu bar items of menu bar 2
			if (count of icons) is 0 then return "!Claude's icon is not in the menu bar: turn on Menu bar in Claude's settings and allow Claude in System Settings › Menu Bar"
			if (count of icons) is not 1 then return "!Claude shows more than one menu bar icon; this button does not know which one to press"
			click item 1 of icons
		end tell
	end tell
	return ""
end run
OSA

# env -i: System Events, when this starts it, gets the account's own environment, not the agent's token.
if ! answer=$(env -i /usr/bin/osascript -e "$script" 2>&1) || [[ $answer == '!'* ]]; then
  case $answer in
    *-1743*) print -u2 -- "The agent may not control System Events: allow it in System Settings → Privacy & Security → Automation" ;;
    *-1719*|*-25211*) print -u2 -- "The agent needs Accessibility: System Settings → Privacy & Security → Accessibility" ;;
    '!'*)    print -ru2 -- "${answer#!}" ;;
    *)       print -ru2 -- "Claude's menu bar icon did not respond: ${answer##*execution error: }" ;;
  esac
  exit 1
fi
exit 0
