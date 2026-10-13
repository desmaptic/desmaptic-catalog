# Postman › Next Tab (tap), Previous Tab (its long press) and Sidebar: an item of Postman's Window or View menu,
# clicked through System Events. Their shortcuts sit on punctuation keys — ⇧⌘] and ⇧⌘[ for the tabs (⌘Tab, the other
# default for Next Tab, is macOS's app switcher), ⌘\ for the sidebar — that German, French, Spanish, Nordic, Swiss and
# other layouts type only with Option or Shift, so a keystroke misses there; and Postman's shortcuts can be changed or
# turned off (Settings › Shortcuts). The menu item works whatever the layout and the shortcuts. Postman names its menus
# in the language chosen in Postman, English or Japanese, and with its flexible layout on, the sidebar item is
# "Toggle Left Sidebar": the script knows all of these (read from its app.asar, Postman 11.89.0). It clicks only while
# Postman is in front: Postman acts on its focused window. It needs Accessibility, and the first tap brings up the
# macOS question about controlling System Events. It never launches Postman.
# The button's command is one line that names the action, then this file (app.json):
#   "action=next-tab\n@file:menu/click.zsh"   — next-tab, previous-tab or sidebar.
[[ $action == (next-tab|previous-tab|sidebar) ]] || { print -u2 -- "Postman: unknown action \"$action\""; exit 1 }
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# pgrep sees every account's processes; -U keeps it to this one, whose Postman System Events sees.
pgrep -xqU $UID Postman || { print -u2 -- "Postman is not running"; exit 1 }

# Prints nothing, or "!<why not>".
read -r -d '' script <<'OSA'
on itemNamed(theItems, theNames)
	repeat with anItem in theItems
		try
			set itemName to name of anItem
			if itemName is not missing value then
				if theNames contains {itemName} then return contents of anItem
			end if
		end try
	end repeat
	return missing value
end itemNamed

on run argv
	set act to item 1 of argv
	-- en, ja
	if act is "sidebar" then
		set menuNames to {"View", "表示"}
		set itemNames to {"Toggle Sidebar", "Toggle Left Sidebar", "サイドバーの表示切り替え"}
		set label to "View › Toggle Sidebar"
	else
		set menuNames to {"Window", "ウインドウ"}
		if act is "next-tab" then
			set itemNames to {"Next Tab", "次のタブ"}
			set label to "Window › Next Tab"
		else
			set itemNames to {"Previous Tab", "前のタブ"}
			set label to "Window › Previous Tab"
		end if
	end if
	tell application "System Events"
		set found to (application processes whose bundle identifier is "com.postmanlabs.mac")
		if found is {} then return "!Postman is not running"
		tell item 1 of found
			if not frontmost then return "!Postman is not in front"
			set barItem to my itemNamed(menu bar items of menu bar 1, menuNames)
			if barItem is missing value then return "!Postman has no " & (item 1 of menuNames) & " menu: is Postman set to English or Japanese?"
			set target to my itemNamed(menu items of menu 1 of barItem, itemNames)
			if target is missing value then return "!Postman has no " & label & " menu item"
			if not (enabled of target) then return "!" & label & " is not available in Postman now"
			click target
		end tell
	end tell
	return ""
end run
OSA

# env -i: System Events, when this starts it, gets the account's own environment, not the agent's token.
if ! answer=$(env -i /usr/bin/osascript -e "$script" "$action" 2>&1) || [[ $answer == '!'* ]]; then
  case $answer in
    *-1743*) print -u2 -- "The agent may not control System Events: allow it in System Settings → Privacy & Security → Automation" ;;
    *-1719*|*-25211*) print -u2 -- "The agent needs Accessibility: System Settings → Privacy & Security → Accessibility" ;;
    '!'*)    print -ru2 -- "${answer#!}" ;;
    *)       print -ru2 -- "Postman's menu did not respond: ${answer##*execution error: }" ;;
  esac
  exit 1
fi
exit 0
