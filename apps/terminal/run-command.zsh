# Terminal › Run Command: a new Terminal window that runs the command set on the first line of the button's script —
# cd ~/Projects/app && claude, ssh to a server… Through Terminal's own AppleScript (`do script` in Terminal's sdef, 2.15):
# the command is typed into the new window's shell as if you typed it, so it runs with your shell, its aliases and
# PATH. It works from any app and brings Terminal forward. The command goes to osascript as an argument, never into the
# script text. When Terminal isn't running it starts it plainly, with Launch Services, and runs the command in the
# window Terminal opens at launch when that is the only one and nothing runs in it yet — `do script` alone would start
# Terminal and then open a second window. The first tap brings up the macOS question whether the agent may control
# Terminal.
# The button's command is its setting, then this file (app.json):
#   "cmd=''   # ← …\n@file:run-command.zsh"
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

[[ $cmd == *[^[:space:]]* ]] ||
  { print -u2 -- "Run Command: set the command in this button’s settings, e.g. cmd='cd ~/Projects/app && claude'"; exit 1 }

# pgrep sees every account's processes; -U keeps it to this one, whose Terminal the AppleScript talks to. It also leaves
# out its own ancestors: -a, because an agent started from a Terminal tab runs inside Terminal.
launched=0
if ! pgrep -axqU $UID Terminal; then
  # env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
  env -i /usr/bin/open -b com.apple.Terminal || { print -u2 -- "Terminal did not start"; exit 1 }
  launched=1
fi

# Prints nothing, or "!<why not>". Arguments: the command, 1 when Terminal was just started.
read -r -d '' script <<'OSA'
on run argv
	set theCommand to item 1 of argv
	set justStarted to (item 2 of argv is "1")
	if not (application id "com.apple.Terminal" is running) then return "!Terminal is not running"
	with timeout of 20 seconds
		tell application id "com.apple.Terminal"
			set here to missing value
			if justStarted then
				-- Wait up to 3 s for the window Terminal opens at launch, and use it while it is the only one and idle.
				repeat 15 times
					if (count of windows) > 0 then exit repeat
					delay 0.2
				end repeat
				try
					if (count of windows) is 1 then
						set t to selected tab of window 1
						if not (busy of t) then set here to t
					end if
				end try
			end if
			if here is missing value then
				do script theCommand
			else
				do script theCommand in here
			end if
			activate
		end tell
	end timeout
	return ""
end run
OSA

if ! answer=$(osascript -e "$script" "$cmd" "$launched" 2>&1) || [[ $answer == '!'* ]]; then
  case $answer in
    *-1743*) print -u2 -- "The agent may not control Terminal: allow it in System Settings → Privacy & Security → Automation" ;;
    *-1712*) print -u2 -- "Terminal did not answer: a dialog may be waiting (Terminal's, or the macOS question about Automation)" ;;
    '!'*)    print -ru2 -- "${answer#!}" ;;
    *)       print -ru2 -- "Terminal did not answer: ${answer##*execution error: }" ;;
  esac
  exit 1
fi
exit 0
