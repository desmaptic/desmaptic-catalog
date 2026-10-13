# Warp › Next Pane (long press: Previous Pane), Smaller and Bigger (long press: Reset Zoom), and the long press of Find
# (Clear Blocks): a Warp menu item, clicked through System Events.
# Next Pane and Previous Pane, because their shortcuts ⌘] and ⌘[ sit on keys that German, French, Spanish, Nordic, Swiss
# and other layouts type only with Option or Shift, so the keystroke misses there. Zoom In, because its ⌘= misses the
# same way (on German keys = is ⇧0), and Zoom Out and Reset Zoom go with it. Clear Blocks, because its ⌘K must never
# reach another app: with Terminal in front by mistake, ⌘K clears its scrollback.
# Warp's menus are in English whatever the Mac's language (Warp ships no translations), so the item is found by its
# English name, menu by menu. Checked in Warp v0.2026.09.16.08.27.stable_02 by reading only — Warp was not started, so
# its menus could not be read live: the names come from the client's source, warpdotdev/warp at 0eefb74 (master on
# 2026-09-16, the day of the build) — app/src/app_menus.rs builds the menus, each item named by its key binding's
# description in title case (util/bindings.rs, workspace/mod.rs, terminal/view/init.rs); the default build has "ui_zoom",
# so View shows Zoom In / Zoom Out / Reset Zoom (the zoom level of all Warp windows, a Warp setting, as ⌘= / ⌘- / ⌘0
# change it), not font-size items. The script refuses while Warp is not in front — a menu command acts on Warp's key
# window, which it has only then — and refuses an item Warp greys out (Clear Blocks when the pane in front is no
# terminal or has no blocks; Warp sets an item's state when a menu opens or a key is pressed, not when it is read, so it
# may be one step behind — not checked live). It needs Accessibility, and the first tap brings up the macOS question
# about controlling System Events. It never launches Warp.
# Every button's command is one line that names its action, then this file (app.json):
#   "action=next-pane\n@file:menu/click.zsh"   — next-pane, previous-pane, zoom-in, zoom-out, reset-zoom or clear-blocks.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
case $action in
  next-pane)     chain=(Tab 'Activate Next Pane') ;;          # ⌘]
  previous-pane) chain=(Tab 'Activate Previous Pane') ;;      # ⌘[
  zoom-in)       chain=(View 'Zoom In') ;;                    # ⌘=
  zoom-out)      chain=(View 'Zoom Out') ;;                   # ⌘-
  reset-zoom)    chain=(View 'Reset Zoom') ;;                 # ⌘0
  clear-blocks)  chain=(Blocks 'Clear Blocks') ;;             # ⌘K
  *) print -u2 -- "Warp: unknown action \"$action\""; exit 1 ;;
esac
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# By bundle id, not by process name: Warp's process is called "stable". lsappinfo asks this login session, whose Warp
# System Events sees, and prints nothing for an app that is not running.
[[ -n $(lsappinfo info -only pid -app dev.warp.Warp-Stable 2>/dev/null) ]] || { print -u2 -- "Warp is not running"; exit 1 }

# Prints nothing, or "!<why not>". Arguments: the menu bar's item, then the names down to the item to click.
read -r -d '' script <<'OSA'
on run argv
	tell application "System Events"
		set found to (application processes whose bundle identifier is "dev.warp.Warp-Stable")
		if found is {} then return "!Warp is not running"
		tell item 1 of found
			if not frontmost then return "!Warp is not in front"
			set menuPath to item 1 of argv
			if not (exists menu bar item menuPath of menu bar 1) then return "!Warp has no " & menuPath & " menu in this version"
			set target to menu bar item menuPath of menu bar 1
			repeat with k from 2 to count of argv
				set itemName to item k of argv
				set menuPath to menuPath & " › " & itemName
				if not (exists menu item itemName of menu 1 of target) then return "!Warp has no " & menuPath & " in this version"
				set target to menu item itemName of menu 1 of target
			end repeat
			-- Greyed out (Clear Blocks outside a terminal or with no blocks): say so rather than click for nothing.
			if not (enabled of target) then return "!" & menuPath & " is not available in Warp now"
			click target
		end tell
	end tell
	return ""
end run
OSA

# env -i: System Events, when this starts it, gets the account's own environment, not the agent's token.
if ! answer=$(env -i /usr/bin/osascript -e "$script" $chain 2>&1) || [[ $answer == '!'* ]]; then
  case $answer in
    *-1743*) print -u2 -- "The agent may not control System Events: allow it in System Settings → Privacy & Security → Automation" ;;
    *-1719*|*-25211*) print -u2 -- "The agent needs Accessibility: System Settings → Privacy & Security → Accessibility" ;;
    '!'*)    print -ru2 -- "${answer#!}" ;;
    *)       print -ru2 -- "Warp's menu did not respond: ${answer##*execution error: }" ;;
  esac
  exit 1
fi
exit 0
