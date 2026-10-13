# Figma › Zoom to Fit, Zoom to Selection and Zoom to 100%: an item of Figma's View menu, clicked through System
# Events. Their keys are not fixed: with Figma's "Use number keys for opacity" preference on, 1 and 2 set the
# selection's opacity and ⇧1 / ⇧2 zoom; with it off it is the other way round — a keystroke would change a layer
# in one of the two cases. The menu item does the same whatever the preference and the keyboard layout.
# Figma fills the macOS menu bar only for the design file in front, runs a clicked item only in its focused window
# (so the script refuses while Figma is not in front), and names the items in its own language: the script finds
# them by their English names, so Figma must be set to English. It needs Accessibility, and the first tap brings
# up the macOS question about controlling System Events. It never launches Figma.
# Every button's command is one line that names the menu and the item, then this file (app.json):
#   "menu=View item='Zoom to fit'\n@file:menu/click.zsh"
[[ -n $menu && -n $item ]] || { print -u2 -- "Figma: the button names no menu item"; exit 1 }
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# pgrep sees every account's processes; -U keeps it to this one, whose Figma System Events sees.
pgrep -xqU $UID Figma || { print -u2 -- "Figma is not running"; exit 1 }

read -r -d '' script <<'OSA'
on run argv
	set menuName to item 1 of argv
	set itemName to item 2 of argv
	tell application "System Events"
		set found to (application processes whose bundle identifier is "com.figma.Desktop")
		if found is {} then return "!Figma is not running"
		tell item 1 of found
			if not frontmost then return "!Figma is not in front"
			if not (exists menu bar item menuName of menu bar 1) then return "!Figma has no " & menuName & " menu: is Figma set to English?"
			set target to menu 1 of menu bar item menuName of menu bar 1
			-- The file browser, and a file still loading, have the desktop shell's own View menu: no zoom items.
			if not (exists menu item itemName of target) then return "!Figma has no " & menuName & " › " & itemName & ": is a design file in front, with Figma set to English?"
			-- Figma 126 greys none of the zoom items out (not even Zoom to selection with nothing selected); should a
			-- later version, say so rather than click for nothing.
			if not (enabled of menu item itemName of target) then return "!" & menuName & " › " & itemName & " is not available in Figma now"
			click menu item itemName of target
		end tell
	end tell
	return ""
end run
OSA

# env -i: System Events, when this starts it, gets the account's own environment, not the agent's token.
if ! answer=$(env -i /usr/bin/osascript -e "$script" "$menu" "$item" 2>&1) || [[ $answer == '!'* ]]; then
  case $answer in
    *-1743*) print -u2 -- "The agent may not control System Events: allow it in System Settings → Privacy & Security → Automation" ;;
    *-1719*|*-25211*) print -u2 -- "The agent needs Accessibility: System Settings → Privacy & Security → Accessibility" ;;
    '!'*)    print -ru2 -- "${answer#!}" ;;
    *)       print -ru2 -- "Figma's menu did not respond: ${answer##*execution error: }" ;;
  esac
  exit 1
fi
exit 0
