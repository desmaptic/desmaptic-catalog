# Xcode › Navigator and Inspector: show or hide a side panel — View › Navigators › Show/Hide Navigator, View ›
# Inspectors › Show/Hide Inspector. Xcode 27 has no shortcut for them (⌘0 opens the Coding Assistant now, ⌥⌘0
# Coding Tools), so the button clicks the menu item through System Events: that needs Accessibility, and the
# first tap brings up the macOS question about controlling System Events. It never launches Xcode.
# Every button's command is one line that names the View submenu and the item, then this file (app.json):
#   "menu=Navigators item=Navigator\n@file:menu/panel.zsh"
[[ -n $menu && -n $item ]] || { print -u2 -- "Xcode: the button names no menu item"; exit 1 }
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# pgrep sees every account's processes; -U keeps it to this one, whose Xcode System Events sees.
pgrep -xqU $UID Xcode || { print -u2 -- "Xcode is not running"; exit 1 }

# Xcode is not localized: its menus are in English everywhere. The item reads "Show <item>" or "Hide <item>",
# so the one that starts either way is clicked.
read -r -d '' script <<'OSA'
on run argv
	set menuName to item 1 of argv
	set itemName to item 2 of argv
	if not (application id "com.apple.dt.Xcode" is running) then return "!Xcode is not running"
	tell application "System Events"
		tell (first application process whose bundle identifier is "com.apple.dt.Xcode")
			set panelMenu to menu 1 of menu item menuName of menu 1 of menu bar item "View" of menu bar 1
			set found to (menu items of panelMenu whose name starts with ("Show " & itemName) or name starts with ("Hide " & itemName))
			if found is {} then return "!Xcode has no View › " & menuName & " › Show " & itemName
			click item 1 of found
		end tell
	end tell
	return ""
end run
OSA

# env -i: System Events, when this starts it, gets the account's own environment, not the agent's token.
if ! answer=$(env -i /usr/bin/osascript -e "$script" $menu $item 2>&1) || [[ $answer == '!'* ]]; then
  case $answer in
    *-1743*) print -u2 -- "The agent may not control System Events: allow it in System Settings → Privacy & Security → Automation" ;;
    *-1719*|*-25211*) print -u2 -- "The agent needs Accessibility: System Settings → Privacy & Security → Accessibility" ;;
    '!'*)    print -ru2 -- "${answer#!}" ;;
    *)       print -ru2 -- "Xcode's menu did not respond: ${answer##*execution error: }" ;;
  esac
  exit 1
fi
exit 0
