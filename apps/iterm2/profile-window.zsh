# iTerm2 › Profile Window: a new iTerm2 window with the profile named on the first line of the button's script — a
# server over SSH, a project's shell: whatever the profile starts. Through iTerm2's own AppleScript (Resources/iTerm2.sdef
# of iTerm2 3.7.3, `create window with profile`): it works from any app and brings iTerm2 forward. Nothing is typed into
# a session; the profile name goes to osascript as an argument, never into the script text. When iTerm2 isn't running
# it starts it plainly, with Launch Services (an Apple event would start it too, then add the window to the one it
# opens at launch all the same), and the profile window comes on top. The first tap brings up the macOS question
# whether the agent may control iTerm2.
# The button's command is its setting, then this file (app.json):
#   "profile=\"\"   # ← …\n@file:profile-window.zsh"
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

[[ -n $profile ]] ||
  { print -u2 -- "Profile Window: set the name of an iTerm2 profile on the first line of the button's script, e.g. profile=\"Work\""; exit 1 }

# pgrep sees every account's processes; -U keeps it to this one, whose iTerm2 the AppleScript talks to. It also leaves
# out its own ancestors: -a, because an agent started from an iTerm2 tab runs inside iTerm2.
launched=0
if ! pgrep -axqU $UID iTerm2; then
  # env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
  env -i /usr/bin/open -b com.googlecode.iterm2 || { print -u2 -- "iTerm2 did not start"; exit 1 }
  launched=1
fi

# Prints nothing, or "!<why not>". Arguments: the profile's name, 1 when iTerm2 was just started.
read -r -d '' script <<'OSA'
on run argv
	set profileName to item 1 of argv
	set justStarted to (item 2 of argv is "1")
	if not (application id "com.googlecode.iterm2" is running) then return "!iTerm2 is not running"
	with timeout of 20 seconds
		tell application id "com.googlecode.iterm2"
			if justStarted then
				-- Wait up to 3 s for the window iTerm2 opens at launch, so the profile window comes on top of it.
				repeat 15 times
					if (count of windows) > 0 then exit repeat
					delay 0.2
				end repeat
			end if
			create window with profile profileName
			activate
		end tell
	end timeout
	return ""
end run
OSA

if ! answer=$(osascript -e "$script" "$profile" "$launched" 2>&1) || [[ $answer == '!'* ]]; then
  case $answer in
    *-1743*)        print -u2 -- "The agent may not control iTerm2: allow it in System Settings → Privacy & Security → Automation" ;;
    *'No profile'*) print -ru2 -- "iTerm2 has no profile named \"$profile\": see iTerm2 › Settings › Profiles" ;;
    *-1712*)        print -u2 -- "iTerm2 did not answer: a dialog may be waiting (iTerm2's, or the macOS question about Automation)" ;;
    '!'*)           print -ru2 -- "${answer#!}" ;;
    *)              print -ru2 -- "iTerm2 did not answer: ${answer##*execution error: }" ;;
  esac
  exit 1
fi
exit 0
