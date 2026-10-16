# Ghostty › Project Tab: a new Ghostty tab in the project folder set on the first line of the button's script, and, when
# the second line sets it, a command typed there once the shell starts (claude, npm run dev…). Through Ghostty's own
# AppleScript (Resources/Ghostty.sdef of Ghostty 1.3.1): a `surface configuration` with an `initial working directory`
# and an `initial input`, given to `new tab … with configuration` — a tab of the front window — or, with no Ghostty
# window open, to `new window with configuration`. It works from any app and brings Ghostty forward; when Ghostty isn't
# running it starts it with Launch Services and puts the tab next to the window Ghostty opens at launch. The folder and
# the command go to osascript as arguments, never into the script text. The first tap brings up the macOS question
# whether the agent may control Ghostty.
# The button's command is its two settings, then this file (app.json):
#   "folder=\"\"   # ← …\ninput=\"\"   # ← …\n@file:project-tab.zsh"
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

[[ -n $folder ]] ||
  { print -u2 -- "Project Tab: set your project folder in this button’s settings, e.g. folder=\"~/Projects/app\""; exit 1 }
# "~/…" in quotes is not expanded by zsh: do it here, for this account's home only.
[[ $folder == '~' || $folder == '~/'* ]] && folder=$HOME${folder#\~}
[[ $folder == /* && -d $folder ]] ||
  { print -ru2 -- "Project Tab: no such folder: $folder (check this button’s settings)"; exit 1 }

# Asked by bundle id, not with pgrep: `ghostty` is also the name of Ghostty's command-line tool (the same binary), which
# may run in a shell while the app does not.
pid=$(lsappinfo info -only pid -app com.mitchellh.ghostty 2>/dev/null)
pid=${pid##*=}
launched=0
if [[ $pid != <1-> ]]; then
  # env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
  env -i /usr/bin/open -b com.mitchellh.ghostty || { print -u2 -- "Ghostty did not start"; exit 1 }
  launched=1
fi

# Prints nothing, or "!<why not>". Arguments: the folder, what to type (may be empty), 1 when Ghostty was just started.
read -r -d '' script <<'OSA'
on run argv
	set dir to item 1 of argv
	set typed to item 2 of argv
	set justStarted to (item 3 of argv is "1")
	if not (application id "com.mitchellh.ghostty" is running) then return "!Ghostty is not running"
	with timeout of 20 seconds
		tell application id "com.mitchellh.ghostty"
			if justStarted then
				-- Wait up to 3 s for the window Ghostty opens at launch, so the tab joins it instead of a second window.
				repeat 15 times
					if (count of windows) > 0 then exit repeat
					delay 0.2
				end repeat
			end if
			set cfg to {initial working directory:dir}
			if typed is not "" then set cfg to cfg & {initial input:typed & linefeed}
			if (count of windows) > 0 then
				new tab in front window with configuration cfg
				activate
			else
				activate window (new window with configuration cfg)
			end if
		end tell
	end timeout
	return ""
end run
OSA

if ! answer=$(osascript -e "$script" "$folder" "$input" "$launched" 2>&1) || [[ $answer == '!'* ]]; then
  case $answer in
    *-1743*)  print -u2 -- "The agent may not control Ghostty: allow it in System Settings → Privacy & Security → Automation" ;;
    *-10004*|*macos-applescript*) print -u2 -- "Ghostty's AppleScript is turned off: macos-applescript = false in its config" ;;
    *-1712*)  print -u2 -- "Ghostty did not answer: a Ghostty dialog may be waiting" ;;
    '!'*)     print -ru2 -- "${answer#!}" ;;
    *)        print -ru2 -- "Ghostty did not answer: ${answer##*execution error: }" ;;
  esac
  exit 1
fi
exit 0
