# Linear › New Issue (tap) and New Project (hold), Agent Chat, Back (tap) and Forward (hold): an item of Linear's own
# menu, clicked through System Events. New Issue, New Project and Agent Chat have no shortcut of their own in the menu
# (the web client's C is a bare letter, which would type itself into a text field being edited); Back and Forward are
# ⌘[ and ⌘], punctuation keys that German, French, Spanish and other layouts type only with Option or Shift, so the
# keystroke would miss there. The menu works the same on every layout and whatever Linear's shortcuts are.
# Checked in Linear 1.32.4 (app.asar, out/main/index.js: the menu template) and in its running menus, read without a
# click: File › New › Issue… and Project… (the web client enables them once a workspace is open), History › Back and
# Forward. File › New › Agent chat… is in the same template (agentChat), read only there: the web client enables it,
# or hides it where the workspace has no agent chat — then the item is not in the menu and the button says so.
# Linear's menus are in English whatever the Mac's language (it ships no translations of its own), so the item is
# found by its English name. "Issue…", "Project…" and "Agent chat…" end with U+2026, built with character id so it can
# be seen here.
# The script refuses while Linear is not in front: the items act on Linear's focused window, and do nothing without one.
# It needs Accessibility, and the first tap brings up the macOS question about controlling System Events. It never
# launches Linear.
# Every button's command is one line that names its action, then this file (app.json):
#   "action=new-issue\n@file:menu/click.zsh"   — new-issue, new-project, new-agent-chat, back or forward.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
[[ $action == (new-issue|new-project|new-agent-chat|back|forward) ]] || { print -u2 -- "Linear: unknown action \"$action\""; exit 1 }
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# By bundle id through lsappinfo, not pgrep by name: "Linear" is a plain word another program's process may carry.
# lsappinfo asks this login session's Launch Services and prints nothing for an app that is not running.
[[ $(lsappinfo info -only pid -app com.linear 2>/dev/null) == *'"pid"='<->* ]] || { print -u2 -- "Linear is not running"; exit 1 }

# Prints nothing, or "!<why not>".
read -r -d '' script <<'OSA'
on run argv
	set act to item 1 of argv
	set ellipsis to character id 8230
	if act is "new-issue" then
		set menuPath to {"File", "New", "Issue" & ellipsis}
	else if act is "new-project" then
		set menuPath to {"File", "New", "Project" & ellipsis}
	else if act is "new-agent-chat" then
		set menuPath to {"File", "New", "Agent chat" & ellipsis}
	else if act is "back" then
		set menuPath to {"History", "Back"}
	else
		set menuPath to {"History", "Forward"}
	end if
	set itemLabel to item 1 of menuPath
	repeat with i from 2 to count of menuPath
		set itemLabel to itemLabel & " › " & item i of menuPath
	end repeat
	tell application "System Events"
		set found to (application processes whose bundle identifier is "com.linear")
		if found is {} then return "!Linear is not running"
		tell item 1 of found
			if not frontmost then return "!Linear is not in front"
			if not (exists menu bar item (item 1 of menuPath) of menu bar 1) then return "!Linear has no " & (item 1 of menuPath) & " menu"
			set target to menu bar item (item 1 of menuPath) of menu bar 1
			repeat with i from 2 to count of menuPath
				if not (exists menu item (item i of menuPath) of menu 1 of target) then return "!Linear has no menu item " & itemLabel
				set target to menu item (item i of menuPath) of menu 1 of target
			end repeat
			-- Greyed out (no workspace open yet, nothing to go back to): say so rather than click for nothing.
			if not (enabled of target) then return "!" & itemLabel & " is not available in Linear now"
			click target
		end tell
	end tell
	return ""
end run
OSA

# env -i: System Events, when this starts it, gets the account's own environment, not the agent's token.
if ! answer=$(env -i /usr/bin/osascript -e "$script" $action 2>&1) || [[ $answer == '!'* ]]; then
  case $answer in
    *-1743*) print -u2 -- "The agent may not control System Events: allow it in System Settings → Privacy & Security → Automation" ;;
    *-1719*|*-25211*) print -u2 -- "The agent needs Accessibility: System Settings → Privacy & Security → Accessibility" ;;
    '!'*)    print -ru2 -- "${answer#!}" ;;
    *)       print -ru2 -- "Linear's menu did not respond: ${answer##*execution error: }" ;;
  esac
  exit 1
fi
exit 0
