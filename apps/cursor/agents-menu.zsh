# Cursor › Changes (tap) and Agents (long press): a menu item of Cursor's Agents window, clicked through System Events.
#   action=changes   View › Changes — the open agent's Changes tab (the command openChangesTab)
#   action=open-ide  File › Open IDE — the editor (IDE) window, for the agent in front
# Checked in Cursor 3.22.7 by reading only (out/vs/workbench/workbench.glass.main.js: the Agents window builds its
# File, Edit, View and Help menus itself — glass-native-menubar-data — from its own commands, whose item titles are
# English literals whatever the Mac's and Cursor's language; out/main.js draws them after the Apple and Cursor menus,
# in the order File, Edit, View, Window, Help). Why clicks and not keys: the keys mean something else in the editor
# window — ⌘E there is "Swap Agent Sidebar Location", which switches the window to the agent layout, moves the side
# bars and hides the panel; ⇧⌘N opens an empty new window.
# Only the Agents window has File › Open IDE, so the script first checks that item in the third menu (File, in both
# windows) and refuses while the editor window is in front. It then asks for the item by name in the third to fifth
# menu only (File, Edit, View), never reading the Window menu, whose items are window titles. The item acts on Cursor's
# focused window, so the script also refuses while Cursor is not in front. It needs Accessibility, and the first press
# brings up the macOS question about controlling System Events. It never launches Cursor.
# Every button's command is one line that names the item, then this file (app.json):
#   "action=changes\n@file:agents-menu.zsh"
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
case $action in
  changes)  name='Changes' ;;
  open-ide) name='Open IDE' ;;
  *) print -u2 -- "Cursor: unknown menu item \"$action\""; exit 1 ;;
esac
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# By bundle id: Cursor's executable is just "Cursor", and lsappinfo sees only this account's apps.
if [[ $(lsappinfo info -only pid -app com.todesktop.230313mzl4w4u92 2>/dev/null) != *'"pid"='<->* ]]; then
  print -u2 -- "Cursor is not running"
  exit 1
fi

# Prints nothing, or "!<why not>".
read -r -d '' script <<'OSA'
on run argv
	set itemName to item 1 of argv
	tell application "System Events"
		set found to (application processes whose bundle identifier is "com.todesktop.230313mzl4w4u92")
		if found is {} then return "!Cursor is not running"
		tell item 1 of found
			if not frontmost then return "!Cursor is not in front"
			set menuCount to count of menu bar items of menu bar 1
			if menuCount < 3 then return "!Cursor shows no File menu"
			if not (exists menu item "Open IDE" of menu 1 of menu bar item 3 of menu bar 1) then return "!" & itemName & " is in Cursor's Agents window: bring that window to the front"
			set target to missing value
			repeat with k from 3 to 5
				if k > menuCount then exit repeat
				if exists menu item itemName of menu 1 of menu bar item k of menu bar 1 then
					set target to menu item itemName of menu 1 of menu bar item k of menu bar 1
					exit repeat
				end if
			end repeat
			if target is missing value then return "!Cursor's Agents window has no " & itemName & " menu item"
			if not (enabled of target) then return "!" & itemName & " is not available in Cursor now"
			click target
		end tell
	end tell
	return ""
end run
OSA

# env -i: System Events, when this starts it, gets the account's own environment, not the agent's token.
if ! answer=$(env -i /usr/bin/osascript -e "$script" "$name" 2>&1) || [[ $answer == '!'* ]]; then
  case $answer in
    *-1743*) print -u2 -- "The agent may not control System Events: allow it in System Settings → Privacy & Security → Automation" ;;
    *-1719*|*-25211*) print -u2 -- "The agent needs Accessibility: System Settings → Privacy & Security → Accessibility" ;;
    '!'*)    print -ru2 -- "${answer#!}" ;;
    *)       print -ru2 -- "Cursor's menu did not respond: ${answer##*execution error: }" ;;
  esac
  exit 1
fi
exit 0
