# Zed › most buttons of the page: an item of Zed's own menu, clicked through System Events. Zed's shortcuts move with
# the user's choices — the Base Keymap setting (VS Code by default; JetBrains, Sublime Text, Atom, TextMate, Emacs and
# Cursor give ⌘P, ⇧⌘O, F2 or ⇧Esc to other commands), vim mode, their own keymap.json — and several sit on punctuation
# keys (⌘/, ⌘\, ⌃`, ⌘?) that German, French, Spanish and other layouts type only with Shift or Option, so a keystroke
# would miss there or zoom out instead. The menu item runs the same action as the shortcut, whatever the keys are.
# Checked in Zed 1.21.0 (dev.zed.Zed, CFBundleVersion 20260923.151803) against crates/zed/src/zed/app_menus.rs at the
# tag v1.21.0 (the menus are built in code; the default key bindings embedded in the installed binary are byte for byte
# assets/keymaps/default-macos.json of that tag): Go › Command Palette..., Go to File..., Go to Symbol in Editor... end
# with three full stops, File › Open Recent… with U+2026, as Zed spells them. Zed ships no translations, so its menus
# are English on every Mac and the item is found by its English name. View › Agent Panel is there only while Zed's AI
# features are on. The item acts on Zed's focused window, so the script refuses while Zed is not in front, and says so
# when the item is greyed out (Go to Definition with no editor focused). It needs Accessibility, and the first tap
# brings up the macOS question about controlling System Events. It never launches Zed.
# Every button's command is one line that names its action, then this file (app.json):
#   "action=command-palette\n@file:menu/click.zsh"
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
case $action in
  command-palette) items=(Go 'Command Palette...') ;;
  go-to-file)      items=(Go 'Go to File...') ;;
  open-recent)     items=(File 'Open Recent…') ;;
  find-in-project) items=(Edit 'Find in Project') ;;
  go-to-symbol)    items=(Go 'Go to Symbol in Editor...') ;;
  project-panel)   items=(View 'Project Panel') ;;
  left-dock)       items=(View 'Toggle Left Dock') ;;
  git-panel)       items=(View 'Git Panel') ;;
  terminal)        items=(View 'Terminal Panel') ;;
  agent)           items=(View 'Agent Panel') ;;
  comment)         items=(Edit 'Toggle Line Comment') ;;
  definition)      items=(Go 'Go to Definition') ;;
  references)      items=(Go 'Find All References') ;;
  split-right)     items=(View 'Editor Layout' 'Split Right') ;;
  split-down)      items=(View 'Editor Layout' 'Split Down') ;;
  tasks)           items=(Run 'Spawn Task') ;;
  diagnostics)     items=(View 'Diagnostics') ;;
  next-problem)    items=(Go 'Next Problem') ;;
  *) print -u2 -- "Zed: unknown action \"$action\""; exit 1 ;;
esac
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# By bundle id through lsappinfo, not pgrep by name: Zed Preview (dev.zed.Zed-Preview) is a "zed" process too. lsappinfo
# asks this login session's Launch Services and prints nothing for an app that is not running.
[[ $(lsappinfo info -only pid -app dev.zed.Zed 2>/dev/null) == *'"pid"='<->* ]] || { print -u2 -- "Zed is not running"; exit 1 }

# The menu, any submenus and the item come as arguments. Prints nothing, or "!<why not>".
read -r -d '' script <<'OSA'
on run argv
	set itemLabel to item 1 of argv
	repeat with i from 2 to count of argv
		set itemLabel to itemLabel & " › " & item i of argv
	end repeat
	tell application "System Events"
		set found to (application processes whose bundle identifier is "dev.zed.Zed")
		if found is {} then return "!Zed is not running"
		tell item 1 of found
			if not frontmost then return "!Zed is not in front"
			if not (exists menu bar item (item 1 of argv) of menu bar 1) then return "!Zed has no " & (item 1 of argv) & " menu"
			set target to menu bar item (item 1 of argv) of menu bar 1
			repeat with i from 2 to count of argv
				if not (exists menu item (item i of argv) of menu 1 of target) then return "!Zed has no menu item " & itemLabel
				set target to menu item (item i of argv) of menu 1 of target
			end repeat
			-- Greyed out (no editor focused, no window open): say so rather than click for nothing.
			if not (enabled of target) then return "!" & itemLabel & " is not available in Zed now"
			click target
		end tell
	end tell
	return ""
end run
OSA

# env -i: System Events, when this starts it, gets the account's own environment, not the agent's token.
if ! answer=$(env -i /usr/bin/osascript -e "$script" "${items[@]}" 2>&1) || [[ $answer == '!'* ]]; then
  case $answer in
    *-1743*) print -u2 -- "The agent may not control System Events: allow it in System Settings → Privacy & Security → Automation" ;;
    *-1719*|*-25211*) print -u2 -- "The agent needs Accessibility: System Settings → Privacy & Security → Accessibility" ;;
    '!Zed has no menu item View › Agent Panel') print -u2 -- "Zed shows no Agent Panel: are its AI features turned off in Zed's settings?" ;;
    '!'*)    print -ru2 -- "${answer#!}" ;;
    *)       print -ru2 -- "Zed's menu did not respond: ${answer##*execution error: }" ;;
  esac
  exit 1
fi
exit 0
