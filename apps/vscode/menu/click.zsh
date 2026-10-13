# VS Code › Terminal, Comment and Split Editor: a VS Code menu item, clicked through System Events.
# Their shortcuts (⌃`, ⌃⇧`, ⌘/, ⌘\) sit on punctuation keys that German, French, Spanish, Italian, Nordic, Swiss
# and other layouts — and the Russian one — type only with Shift or Option, so the keystroke misses there (⌘/
# even zooms out on a German keyboard). The menu works on every layout. VS Code runs a menu command only in its
# focused window, so the script refuses while VS Code is not in front; and it finds the item by its English name,
# so VS Code's menus must be in English (no language pack). It needs Accessibility, and the first tap brings up
# the macOS question about controlling System Events. It never launches VS Code.
# Every button's command is one line that names the menu, an optional submenu and the item, then this file:
#   "menu=View item=Terminal\n@file:menu/click.zsh"
#   "menu=View submenu='Editor Layout' item='Split Right'\n@file:menu/click.zsh"
[[ -n $menu && -n $item ]] || { print -u2 -- "VS Code: the button names no menu item"; exit 1 }
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# pgrep sees every account's processes; -U keeps it to this one, whose VS Code System Events sees. -a: pgrep
# skips its own ancestors, and an agent started from VS Code's integrated terminal has VS Code among them.
pgrep -axqU $UID Code || { print -u2 -- "VS Code is not running"; exit 1 }

read -r -d '' script <<'OSA'
on run argv
	set menuName to item 1 of argv
	set subName to item 2 of argv
	set itemName to item 3 of argv
	tell application "System Events"
		set found to (application processes whose bundle identifier is "com.microsoft.VSCode")
		if found is {} then return "!VS Code is not running"
		tell item 1 of found
			if not frontmost then return "!VS Code is not in front"
			if not (exists menu bar item menuName of menu bar 1) then return "!VS Code has no " & menuName & " menu: are its menus in English?"
			set target to menu 1 of menu bar item menuName of menu bar 1
			set menuPath to menuName
			if subName is not "" then
				if not (exists menu item subName of target) then return "!VS Code has no " & menuPath & " › " & subName & ": are its menus in English?"
				set target to menu 1 of menu item subName of target
				set menuPath to menuPath & " › " & subName
			end if
			-- A language pack keeps some menu names ("Terminal" in German, French, Spanish) but not the items.
			if not (exists menu item itemName of target) then return "!VS Code has no " & menuPath & " › " & itemName & ": are its menus in English?"
			-- Greyed out (Split Right with no file open): say so rather than click for nothing.
			if not (enabled of menu item itemName of target) then return "!" & menuPath & " › " & itemName & " is not available in VS Code now"
			click menu item itemName of target
		end tell
	end tell
	return ""
end run
OSA

# env -i: System Events, when this starts it, gets the account's own environment, not the agent's token.
if ! answer=$(env -i /usr/bin/osascript -e "$script" "$menu" "$submenu" "$item" 2>&1) || [[ $answer == '!'* ]]; then
  case $answer in
    *-1743*) print -u2 -- "The agent may not control System Events: allow it in System Settings → Privacy & Security → Automation" ;;
    *-1719*|*-25211*) print -u2 -- "The agent needs Accessibility: System Settings → Privacy & Security → Accessibility" ;;
    '!'*)    print -ru2 -- "${answer#!}" ;;
    *)       print -ru2 -- "VS Code's menu did not respond: ${answer##*execution error: }" ;;
  esac
  exit 1
fi
exit 0
