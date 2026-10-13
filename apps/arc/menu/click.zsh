# Arc › every button that would otherwise press one of Arc's shortcuts: it brings Arc to the front and clicks Arc's own
# menu item through System Events, as Raycast's Arc extension does, never a keystroke. Why the menu:
# - A key pressed into a greyed-out item does nothing and says nothing — Arc greys out its tab, Space and page commands
#   while it has no key window, and some in front too: Pin Tab for some tabs (seen with every other Tabs item enabled;
#   which tabs was not looked at — their names are the user's), Separate Page with no Split View. Clicked, the button
#   checks the item first and refuses with the reason, so the phone shakes the button instead of the key vanishing.
# - Some shortcuts sit on keys other layouts type only with Shift or Option: Add Split View ⌃⇧= (German, Spanish,
#   Italian, Nordic, Swiss…), Capture ⇧⌘2 (a digit French and Czech keys type only with Shift). Separate Page from Split
#   View and Capture Full Page have no shortcut at all. The menu works the same on every layout.
# Arc's menus are English whatever the Mac's language: they come from its MainMenu.nib, whose only translations
# (<lang>.lproj/MainMenu.strings) are the Edit menu and its Copy item, and from code in English. So an item is found by
# its English name, and only in the menu that holds it (never the Window menu, whose items are window titles). Two items
# rename with the state, and both names are listed: Tabs › Pin Tab / Unpin Tab, View › Show Sidebar / Hide Sidebar; Arc
# also has the words Show / Hide Developer Tools, so those are accepted beside Developer Tools.
# Checked in Arc 1.166.0 by reading only — the running app's menus through the Accessibility API and System Events, the
# bundle's MainMenu.nib and strings; nothing was clicked (2026-09-27):
#   File   › New Tab… ⌘T (the ⌘T that fires: File comes before Tabs, which has a twin), New Little Arc Window ⌥⌘N,
#            Restore Last Closed Tab ⇧⌘T, Capture… ⇧⌘2, Capture Full Page
#   Tabs   › Pin Tab / Unpin Tab ⌘D, Next Tab ⌥⌘↓, Previous Tab ⌥⌘↑
#   Spaces › Next Space ⌥⌘→, Previous Space ⌥⌘←
#   View   › Show Sidebar / Hide Sidebar ⌘S, Force Refresh the Page ⇧⌘R, Add Split View ⌃⇧=,
#            Separate Page from Split View, Developer › Developer Tools ⌥⌘I, Developer › JavaScript Console ⌥⌘J
# With Arc in the background every one of them but New Tab… and New Little Arc Window reads greyed out: Arc has no key
# window then. So the script brings Arc forward first (System Events sets its frontmost, the Accessibility way, with no
# Apple event to Arc) and reads the item again for up to about a second: Arc makes its window key a moment later, and
# only then are the items enabled and named for that window (Pin Tab / Unpin Tab), so the item is looked up anew on every
# read, never kept from before. It needs Accessibility, and the first tap brings up the macOS question about controlling
# System Events. It never launches Arc.
# Every button's command is one line that names its action, then this file (app.json):
#   "action=next-tab\n@file:menu/click.zsh"   — new-tab, little-arc, restore-tab, capture, capture-page, pin-tab,
#   next-tab, previous-tab, next-space, previous-space, sidebar, force-refresh, split-view, separate, dev-tools, console.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set

# What the refusal adds when the item is greyed out. "…" in item names is U+2026, one character, as Arc writes it.
focus="close Little Arc or the Command Bar first (Esc), or show an Arc window"
page="open a page in Arc, or close Little Arc or the Command Bar first (Esc)"
sub= greyed=$focus
case $action in
  new-tab)        menu=File   names=("New Tab…") ;;
  little-arc)     menu=File   names=("New Little Arc Window") ;;
  restore-tab)    menu=File   names=("Restore Last Closed Tab")
                  greyed="no closed tab to bring back, or Little Arc or the Command Bar has the focus (Esc)" ;;
  capture)        menu=File   names=("Capture…") greyed=$page ;;
  capture-page)   menu=File   names=("Capture Full Page") greyed=$page ;;
  pin-tab)        menu=Tabs   names=("Pin Tab" "Unpin Tab")
                  greyed="Arc can't pin or unpin what is in front now, or Little Arc or the Command Bar has the focus (Esc)" ;;
  next-tab)       menu=Tabs   names=("Next Tab") ;;
  previous-tab)   menu=Tabs   names=("Previous Tab") ;;
  next-space)     menu=Spaces names=("Next Space") ;;
  previous-space) menu=Spaces names=("Previous Space") ;;
  sidebar)        menu=View   names=("Show Sidebar" "Hide Sidebar") ;;
  force-refresh)  menu=View   names=("Force Refresh the Page") greyed=$page ;;
  split-view)     menu=View   names=("Add Split View") greyed=$page ;;
  separate)       menu=View   names=("Separate Page from Split View") greyed="the page is not in a Split View" ;;
  dev-tools)      menu=View   sub=Developer names=("Developer Tools" "Show Developer Tools" "Hide Developer Tools")
                  greyed=$page ;;
  console)        menu=View   sub=Developer names=("JavaScript Console") greyed=$page ;;
  *) print -u2 -- "Arc: unknown action \"$action\""; exit 1 ;;
esac
where="$menu › ${sub:+$sub › }"
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# pgrep sees every account's processes; -U keeps it to this one, whose Arc System Events sees.
pgrep -xqU $UID Arc || { print -u2 -- "Arc is not running"; exit 1 }

# Prints nothing, or "!<why not>". The arguments: the menu path for messages ("View › Developer › "), what to say when
# the item is greyed out, the menu, the submenu ("" for none), then the item's names — data, never pasted into the script
# text. Only "no such item" (-1728) is a refusal of its own; any other error (no Accessibility: -1719, -25211) goes up to
# the case below, which names the permission.
read -r -d '' script <<'OSA'
on run argv
	set pathText to item 1 of argv
	set greyed to item 2 of argv
	set menuName to item 3 of argv
	set subName to item 4 of argv
	set itemNames to items 5 thru -1 of argv
	with timeout of 10 seconds
		tell application "System Events"
			set found to (application processes whose bundle identifier is "company.thebrowser.Browser")
			if found is {} then return "!Arc is not running"
			tell item 1 of found
				-- A menu command acts on Arc's key window, which Arc has only in front.
				set reads to 1
				if not frontmost then
					set frontmost to true
					repeat 40 times
						if frontmost then exit repeat
						delay 0.05
					end repeat
					if not frontmost then return "!Arc did not come to the front"
					set reads to 8
				end if
				try
					set theMenu to menu 1 of menu bar item menuName of menu bar 1
					if subName is not "" then set theMenu to menu 1 of menu item subName of theMenu
				on error errText number errNum
					if errNum is not -1728 then error errText number errNum
					return "!Arc shows no menu " & (text 1 thru -4 of pathText) & " now: " & greyed
				end try
				set shownName to item 1 of itemNames
				repeat with attempt from 1 to reads
					set target to missing value
					set isOn to false
					try
						repeat with aName in itemNames
							if exists menu item (contents of aName) of theMenu then
								set shownName to contents of aName
								set target to menu item shownName of theMenu
								exit repeat
							end if
						end repeat
						if target is not missing value then set isOn to enabled of target
					on error errText number errNum
						if errNum is not -1728 then error errText number errNum
						set target to missing value
					end try
					if isOn or attempt = reads then exit repeat
					delay 0.05
				end repeat
				if target is missing value then return "!Arc shows no menu item " & pathText & shownName & " now: " & greyed
				if not isOn then return "!" & pathText & shownName & " is greyed out in Arc now: " & greyed
				click target
			end tell
		end tell
	end timeout
	return ""
end run
OSA

# env -i: System Events, when this starts it, gets the account's own environment, not the agent's token.
if ! answer=$(env -i /usr/bin/osascript -e "$script" "$where" "$greyed" "$menu" "$sub" "${names[@]}" 2>&1) || [[ $answer == '!'* ]]; then
  case $answer in
    *-1743*) print -u2 -- "The agent may not control System Events: allow it in System Settings → Privacy & Security → Automation" ;;
    *-1719*|*-25211*) print -u2 -- "The agent needs Accessibility: System Settings → Privacy & Security → Accessibility" ;;
    *-1712*) print -u2 -- "Arc's menu did not answer" ;;
    '!'*)    print -ru2 -- "${answer#!}" ;;
    *)       print -ru2 -- "Arc's menu did not respond: ${answer##*execution error: }" ;;
  esac
  exit 1
fi
exit 0
