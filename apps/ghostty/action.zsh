# Ghostty › every button but Finder Folder and Show in Finder: one of Ghostty's own commands ("actions"), given through
# Ghostty's AppleScript (Resources/Ghostty.sdef of Ghostty 1.3.1, `perform action … on <terminal>`). They work whatever
# the keyboard layout and whatever the user bound to Ghostty's keys, and from any app. Nothing is typed into a terminal:
# the action strings are fixed below and go to osascript as an argument, never into the script text. The first tap
# brings up the macOS question whether the agent may control Ghostty. Checked against the v1.3.1 source (commit
# 332b2aefc, the one Info.plist names): the AppleScript classes in macos/Sources/Features/AppleScript, the core
# (Surface.zig, performBindingAction) and the macOS side of each action (Ghostty.App, the action handlers).
# - Surface actions go to the focused terminal of the selected tab of Ghostty's front window ("front window" leaves out
#   the quick terminal, an NSPanel), and that window comes forward first — so they work from any app, as a key would
#   there. Ghostty answers false when it had nothing to do (one tab, no split to go to, clearing a full-screen program).
# - New Tab and New Window act like ⌘T and ⌘N (the new terminal starts in the folder of the one in front); with no
#   Ghostty window open they make one. New Window starts Ghostty when it isn't running (the button's point), plainly,
#   with Launch Services; the others never launch it.
# - Quick Terminal, Reload Config and Open Config are app actions: any terminal takes them, and Ghostty is not brought
#   forward (the quick terminal comes forward by itself).
# - Close and Clear (long presses) destroy something, so they act only while Ghostty is in front and no Ghostty window
#   floats above the others: the quick terminal is not a scripting window, and with it focused the command would hit
#   the window behind. Windows above normal level are read from the window server, which needs no permission.
# Every button's command is one line that names its action, then this file (app.json):
#   "action=tab\n@file:action.zsh"
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
case $action in
  tab)            ghostty_action=new_tab;                kind=tab ;;
  window)         ghostty_action=new_window;             kind=window ;;
  previous-tab)   ghostty_action=previous_tab;           kind=front ;;     # ⌃⇧⇥
  next-tab)       ghostty_action=next_tab;               kind=front ;;     # ⌃⇥
  split-right)    ghostty_action=new_split:right;        kind=front ;;     # ⌘D
  split-down)     ghostty_action=new_split:down;         kind=front ;;     # ⇧⌘D
  next-split)     ghostty_action=goto_split:next;        kind=front ;;     # ⌘]
  previous-split) ghostty_action=goto_split:previous;    kind=front ;;     # ⌘[
  zoom-split)     ghostty_action=toggle_split_zoom;      kind=front ;;     # ⇧⌘↩
  find)           ghostty_action=start_search;           kind=front ;;     # ⌘F
  palette)        ghostty_action=toggle_command_palette; kind=front ;;     # ⇧⌘P
  smaller)        ghostty_action=decrease_font_size:1;   kind=front ;;     # ⌘-
  bigger)         ghostty_action=increase_font_size:1;   kind=front ;;     # ⌘+
  default-size)   ghostty_action=reset_font_size;        kind=front ;;     # ⌘0
  close)          ghostty_action=close_surface;          kind=guarded ;;   # ⌘W
  clear)          ghostty_action=clear_screen;           kind=guarded ;;   # ⌘K
  quick-terminal) ghostty_action=toggle_quick_terminal;  kind=app ;;       # no default key
  reload-config)  ghostty_action=reload_config;          kind=app ;;       # ⇧⌘,
  open-config)    ghostty_action=open_config;            kind=app ;;       # ⌘,
  *) print -u2 -- "Ghostty: unknown action \"$action\""; exit 1 ;;
esac
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# Asked by bundle id, not with pgrep: `ghostty` is also the name of Ghostty's command-line tool (the same binary), which
# may run in a shell while the app does not. Launch Services answers for this login session only, whose Ghostty the
# AppleScript talks to — not another account's.
pid=$(lsappinfo info -only pid -app com.mitchellh.ghostty 2>/dev/null)
pid=${pid##*=}
if [[ $pid != <1-> ]]; then
  if [[ $action == window ]]; then
    # env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
    env -i /usr/bin/open -b com.mitchellh.ghostty || { print -u2 -- "Ghostty did not start"; exit 1 }
    exit 0
  fi
  print -u2 -- "Ghostty is not running"; exit 1
fi

if [[ $kind == guarded ]]; then
  # How many of Ghostty's windows on screen sit above the normal level (the quick terminal: 3, or 101 while it slides
  # in; a window set to float on top: 3). Anything but a plain 0 — an error included — is a refusal.
  floating=$(osascript -l JavaScript -e 'ObjC.import("CoreGraphics")
function run(argv) {
  const pid = Number(argv[0])
  const list = ObjC.deepUnwrap(ObjC.castRefToObject($.CGWindowListCopyWindowInfo($.kCGWindowListOptionOnScreenOnly | $.kCGWindowListExcludeDesktopElements, $.kCGNullWindowID)))
  if (!Array.isArray(list)) return "?"
  return String(list.filter(w => w.kCGWindowOwnerPID === pid && w.kCGWindowLayer !== 0).length)
}' "$pid" 2>/dev/null)
  [[ $floating == 0 ]] ||
    { print -u2 -- "A Ghostty window floats above the others (the quick terminal?): this acts only on a regular window in front"; exit 1 }
fi

# Prints nothing, "!<why not>", or "?" when Ghostty had nothing to do. Arguments: Ghostty's action, then its kind.
read -r -d '' script <<'OSA'
on run argv
	set ghosttyAction to item 1 of argv
	set kind to item 2 of argv
	if not (application id "com.mitchellh.ghostty" is running) then return "!Ghostty is not running"
	with timeout of 20 seconds
		tell application id "com.mitchellh.ghostty"
			if kind is "app" then
				if (count of terminals) is 0 then
					-- With macos-applescript = false Ghostty lists nothing and refuses every command with -10004.
					new surface configuration
					return "!Ghostty has no terminal open to take the command: open a window first"
				end if
				if not (perform action ghosttyAction on terminal 1) then return "?"
				return ""
			end if
			set w to missing value
			try
				set w to front window
			end try
			if w is missing value then
				new surface configuration
				if kind is "tab" or kind is "window" then
					set w to new window
					activate window w
					return ""
				end if
				return "!No Ghostty window is open"
			end if
			if kind is "guarded" and not frontmost then return "!Ghostty is not in front"
			set t to missing value
			try
				set t to focused terminal of selected tab of w
			end try
			if t is missing value then return "!Ghostty did not say which terminal is in front"
			if kind is "front" then activate window w
			set done to (perform action ghosttyAction on t)
			if kind is "tab" or kind is "window" then activate
			if not done then return "?"
		end tell
	end timeout
	return ""
end run
OSA

if ! answer=$(osascript -e "$script" "$ghostty_action" "$kind" 2>&1) || [[ $answer == ('!'|'?')* ]]; then
  case $answer in
    *-1743*)  print -u2 -- "The agent may not control Ghostty: allow it in System Settings → Privacy & Security → Automation" ;;
    *-10004*|*macos-applescript*) print -u2 -- "Ghostty's AppleScript is turned off: macos-applescript = false in its config" ;;
    # No answer in 20 s: Ghostty waits on a dialog of its own (New Tab with window-decorations off asks with runModal).
    *-1712*)  print -u2 -- "Ghostty did not answer: a Ghostty dialog may be waiting" ;;
    '?'*)
      case $action in
        previous-tab|next-tab)     print -u2 -- "This Ghostty window has only one tab" ;;
        next-split|previous-split) print -u2 -- "This Ghostty tab has no other split" ;;
        zoom-split)                print -u2 -- "This Ghostty tab has no splits to zoom" ;;
        clear)                     print -u2 -- "Ghostty clears nothing while a full-screen program (vim, less…) runs" ;;
        *)                         print -u2 -- "Ghostty did not do it: $ghostty_action" ;;
      esac ;;
    '!'*)     print -ru2 -- "${answer#!}" ;;
    *)        print -ru2 -- "Ghostty did not answer: ${answer##*execution error: }" ;;
  esac
  exit 1
fi
exit 0
