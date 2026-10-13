# iTerm2 › New Tab, New Window, Previous Tab, Next Tab, Split Right and Split Down, through iTerm2's own AppleScript
# (Resources/iTerm2.sdef of iTerm2 3.7.3): they work from any app, whatever the keyboard layout and whatever the user
# bound to iTerm2's keys, and each brings iTerm2 forward. Nothing is typed into a session, and no command is given to
# the new ones: they start as the profile says. The first tap brings up the macOS question whether the agent may
# control iTerm2.
# - Tabs are picked by position, not with ⌘← / ⌘→: iTerm2's "Natural Text Editing" key preset turns those into
#   start and end of line; Window › Select Next Tab is ⇧⌘], a key many layouts type only with Option.
# - A split is made with the pane's own profile, as Shell › Split Vertically with Current Profile (⌘D) does; iTerm2's
#   AppleScript hands the focus back to the old pane (PTYSession+Scripting.m), so the new one is selected after.
# - New Window starts iTerm2 when it isn't running (the button's point), plainly, with Launch Services: an Apple event
#   would start it and then add a second window to the one it opens at launch. The others never launch iTerm2.
# Every button's command is one line that names its action, then this file (app.json):
#   "action=tab\n@file:action.zsh"   — tab, window, previous-tab, next-tab, split-right or split-down.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
[[ $action == (tab|window|previous-tab|next-tab|split-right|split-down) ]] || { print -u2 -- "iTerm2: unknown action \"$action\""; exit 1 }
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# pgrep sees every account's processes; -U keeps it to this one, whose iTerm2 the AppleScript talks to. It also leaves
# out its own ancestors: -a, because an agent started from an iTerm2 tab runs inside iTerm2.
if ! pgrep -axqU $UID iTerm2; then
  if [[ $action == window ]]; then
    # env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
    env -i /usr/bin/open -b com.googlecode.iterm2 || { print -u2 -- "iTerm2 did not start"; exit 1 }
    exit 0
  fi
  print -u2 -- "iTerm2 is not running"; exit 1
fi

# Prints nothing, or "!<why not>".
read -r -d '' script <<'OSA'
on run argv
	set act to item 1 of argv
	if not (application id "com.googlecode.iterm2" is running) then return "!iTerm2 is not running"
	with timeout of 20 seconds
		tell application id "com.googlecode.iterm2"
			if act is "window" then
				create window with default profile
				activate
				return ""
			end if
			set w to missing value
			try
				set w to current window
			end try
			if w is missing value then
				if act is "tab" then
					create window with default profile
					activate
					return ""
				end if
				return "!No iTerm2 window is open"
			end if
			if act is "tab" then
				tell w to create tab with default profile
			else if act is "previous-tab" or act is "next-tab" then
				-- The tab in front is the one holding the window's current session: tabs have no id of their own.
				set frontId to id of current session of w
				set tabCount to count of tabs of w
				set frontIndex to 0
				repeat with k from 1 to tabCount
					if (id of current session of tab k of w) is frontId then
						set frontIndex to k
						exit repeat
					end if
				end repeat
				if frontIndex is 0 then return "!iTerm2 did not say which tab is in front"
				if act is "next-tab" then
					set wanted to (frontIndex mod tabCount) + 1
				else
					set wanted to ((frontIndex + tabCount - 2) mod tabCount) + 1
				end if
				select tab wanted of w
			else
				set tabBefore to current tab of w
				set paneCount to count of sessions of tabBefore
				set pane to current session of w
				set newPane to missing value
				try
					-- iTerm2 3.7.3 never answers a split it refuses because the pane is too small or Instant Replay is
					-- on (PseudoTerminal.m beeps and returns without calling back), so wait 8 s, not the 20 above.
					with timeout of 8 seconds
						if act is "split-right" then
							tell pane to set newPane to (split vertically with same profile)
						else
							tell pane to set newPane to (split horizontally with same profile)
						end if
					end timeout
				on error errText number errNumber
					-- -2763, no result: a locked layout (Window › Lock Layout) or a failed tmux split. -1712: no answer (above).
					-- The count below tells either way.
					if errNumber is not in {-2763, -1712} then error errText number errNumber
				end try
				if (count of sessions of tabBefore) ≤ paneCount then return "!iTerm2 did not split the pane: it is too small, Instant Replay is on, or Window › Lock Layout is on"
				if newPane is not missing value then tell newPane to select
			end if
			activate
		end tell
	end timeout
	return ""
end run
OSA

if ! answer=$(osascript -e "$script" "$action" 2>&1) || [[ $answer == '!'* ]]; then
  case $answer in
    *-1743*) print -u2 -- "The agent may not control iTerm2: allow it in System Settings → Privacy & Security → Automation" ;;
    '!'*)    print -ru2 -- "${answer#!}" ;;
    *)       print -ru2 -- "iTerm2 did not answer: ${answer##*execution error: }" ;;
  esac
  exit 1
fi
exit 0
