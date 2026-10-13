# JetBrains IDE › Run, Debug, Resume, Stop, the debugger's steps, Breakpoint, Declaration, Rename, Commit, Search
# Everywhere and Find Action: an item of the IDE's own menus, clicked through System Events.
# Why not the shortcut: while the IDE's terminal has focus, it keeps every key that is not on its short list of IDE
# actions for the shell — ⌃D (Debug) would end the program running there, ⌃R (Run) starts a history search, F7, F8,
# ⇧F8 and ⇧F6 type escape sequences, ⌘K (Commit) clears the terminal — and ⌘B (Declaration) makes text bold in a
# Markdown file. A menu item runs the IDE's action whatever has focus, whatever the keymap and the keyboard layout.
# Search Everywhere has no shortcut a button can press: it is Shift pressed twice. Find Action's ⇧⌘A is also the macOS
# service "Search man Page Index in Terminal", on by default: with text selected, the key opens Terminal and runs apropos
# instead (JetBrains' own support article), so Find Action is Help › Find Action… here.
# The IDE fills a menu only when it opens (its native menu refills on menuNeedsUpdate and is cleared after closing), so
# the script opens each menu on the way, as a click would, and closes them again (AXCancel, never a key: an Escape that
# reached the IDE's terminal would interrupt the program there) when the item is missing or greyed out or a step
# fails. Items are found by their English names, the IDE's language unless a Chinese, Japanese or Korean language pack
# is on; Run, Debug and Stop carry the run configuration's name ("Run 'App'"), so they are found by how they start.
# It acts only on a JetBrains IDE that is in front — a menu command acts on its focused window — and never launches
# one. It needs Accessibility, and the first tap brings up the macOS question about controlling System Events.
# Every button's command is one line that names the item, then this file (app.json):
#   "item=step-over\n@file:menu/click.zsh"
# A level lists what its item may be called, one per line: "=Name" is the whole name, "^Start" its beginning.
case $item in
  run)               shown='Run › Run'                  levels=('=Run' $'=Run\n^Run \'') ;;
  run-choose)        shown='Run › Run…'                 levels=('=Run' '=Run…') ;;
  debug)             shown='Run › Debug'                levels=('=Run' $'=Debug\n^Debug \'') ;;
  debug-choose)      shown='Run › Debug…'               levels=('=Run' '=Debug…') ;;
  stop)              shown='Run › Stop'                 levels=('=Run' $'=Stop\n=Stop…\n^Stop \'') ;;
  resume)            shown='Run › Debugging Actions › Resume Program'  levels=('=Run' '=Debugging Actions' '=Resume Program') ;;
  step-over)         shown='Run › Debugging Actions › Step Over'       levels=('=Run' '=Debugging Actions' '=Step Over') ;;
  step-into)         shown='Run › Debugging Actions › Step Into'       levels=('=Run' '=Debugging Actions' '=Step Into') ;;
  smart-step-into)   shown='Run › Debugging Actions › Smart Step Into' levels=('=Run' '=Debugging Actions' '=Smart Step Into') ;;
  step-out)          shown='Run › Debugging Actions › Step Out'        levels=('=Run' '=Debugging Actions' '=Step Out') ;;
  breakpoint)        shown='Run › Toggle Breakpoint › Line Breakpoint' levels=('=Run' '=Toggle Breakpoint' '=Line Breakpoint') ;;
  view-breakpoints)  shown='Run › View Breakpoints…'    levels=('=Run' '=View Breakpoints…') ;;
  search-everywhere) shown='Navigate › Search Everywhere'      levels=('=Navigate' '=Search Everywhere') ;;
  find-action)       shown='Help › Find Action…'        levels=('=Help' '=Find Action…') ;;
  declaration)       shown='Navigate › Declaration or Usages'  levels=('=Navigate' '=Declaration or Usages') ;;
  implementation)    shown='Navigate › Implementation(s)'      levels=('=Navigate' '=Implementation(s)') ;;
  rename)            shown='Refactor › Rename…'         levels=('=Refactor' '=Rename…') ;;
  commit)            shown='Git › Commit…'              levels=($'=Git\n=VCS' '=Commit…') ;;
  *) print -u2 -- "JetBrains IDE: unknown menu item \"$item\""; exit 1 ;;
esac
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# The JetBrains IDEs of this page (app.json "bundleIds"); the one in front of this session, asked without an Apple event.
ides=(com.jetbrains.intellij com.jetbrains.intellij.ce com.jetbrains.pycharm com.jetbrains.pycharm.ce
  com.jetbrains.WebStorm com.jetbrains.goland com.jetbrains.PhpStorm com.jetbrains.rubymine com.jetbrains.CLion
  com.jetbrains.rustrover)
front=$(lsappinfo info -only bundleid "$(lsappinfo front 2>/dev/null)" 2>/dev/null)
front=${${front#*=}//\"/}
(( ${ides[(Ie)$front]} )) || { print -u2 -- "No JetBrains IDE is in front"; exit 1 }

# Prints nothing, or "!<why not>", "?<level that is missing>" (1 is the menu bar), "-" when an item on the way is greyed out.
read -r -d '' script <<'OSA'
on run argv
	set bundleId to item 1 of argv
	set levelCount to (count argv) - 1
	tell application "System Events"
		set found to (application processes whose bundle identifier is bundleId)
		if found is {} then return "!The JetBrains IDE is not running"
		set ide to item 1 of found
		if not (frontmost of ide) then return "!The JetBrains IDE is not in front"
		set barItem to my barItemNamed(ide, paragraphs of (item 2 of argv))
		if barItem is missing value then return "?1"
		click barItem
		set holder to barItem
		try
			repeat with depth from 2 to levelCount
				set target to my itemNamed(menu 1 of holder, paragraphs of (item (depth + 1) of argv))
				if target is missing value then
					my shutMenus(barItem)
					return "?" & depth
				end if
				-- Greyed out: Step Over with no debug session paused, Rename with no symbol at the caret.
				if not (enabled of target) then
					my shutMenus(barItem)
					return "-"
				end if
				click target
				set holder to target
			end repeat
		on error errorText number errorNumber
			-- A step that fails must not leave the IDE's menu open.
			my shutMenus(barItem)
			error errorText number errorNumber
		end try
	end tell
	return ""
end run

on barItemNamed(ide, patterns)
	tell application "System Events"
		repeat with pattern in patterns
			set pattern to contents of pattern
			set label to text 2 thru -1 of pattern
			if pattern starts with "=" then
				set hits to (menu bar items of menu bar 1 of ide whose name is label)
			else
				set hits to (menu bar items of menu bar 1 of ide whose name starts with label)
			end if
			if hits is not {} then return item 1 of hits
		end repeat
	end tell
	return missing value
end barItemNamed

-- The menu was just opened: the IDE may still be filling it, so it is asked again for a moment.
on itemNamed(theMenu, patterns)
	repeat 80 times
		tell application "System Events"
			repeat with pattern in patterns
				set pattern to contents of pattern
				set label to text 2 thru -1 of pattern
				try
					if pattern starts with "=" then
						set hits to (menu items of theMenu whose name is label)
					else
						set hits to (menu items of theMenu whose name starts with label)
					end if
					if hits is not {} then return item 1 of hits
				end try
			end repeat
		end tell
		delay 0.05
	end repeat
	return missing value
end itemNamed

-- Closes what the script opened (cancelling the top menu ends the whole menu session, submenus included). Never with
-- Escape: a key that reached the IDE after the menu had closed would go to its focused terminal or editor.
on shutMenus(barItem)
	tell application "System Events"
		try
			perform action "AXCancel" of menu 1 of barItem
		on error
			try
				perform action "AXCancel" of barItem
			end try
		end try
	end tell
end shutMenus
OSA

# env -i: System Events, when this starts it, gets the account's own environment, not the agent's token.
if ! answer=$(env -i /usr/bin/osascript -e "$script" "$front" "${levels[@]}" 2>&1) || [[ -n $answer ]]; then
  parts=("${(@s: › :)shown}")
  case $answer in
    *-1743*) print -u2 -- "The agent may not control System Events: allow it in System Settings → Privacy & Security → Automation" ;;
    *-1719*|*-25211*) print -u2 -- "The agent needs Accessibility: System Settings → Privacy & Security → Accessibility" ;;
    '!'*)    print -ru2 -- "${answer#!}" ;;
    '?1')    print -ru2 -- "The IDE shows no ${parts[1]} menu: open a project window, with the IDE's menus in English" ;;
    '?'*)    print -ru2 -- "The IDE shows no $shown now" ;;
    -)       print -ru2 -- "${parts[-1]} is not available in the IDE now" ;;
    *)       print -ru2 -- "The IDE's menu did not respond: ${answer##*execution error: }" ;;
  esac
  exit 1
fi
exit 0
