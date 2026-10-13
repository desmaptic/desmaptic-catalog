# iTerm2 › Show in Finder: the folder of the pane in front of iTerm2's front window, in a Finder window. iTerm2 says
# which terminal device the pane has, through its own AppleScript ("tty" of the current session) — the first tap brings
# up the macOS question whether the agent may control iTerm2. The folder is asked from the system (ps, lsof), as on
# the Terminal page: nothing is typed into the pane. It never launches iTerm2, nor the app of a package the pane is in.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# pgrep sees every account's processes; -U keeps it to this one, whose iTerm2 the AppleScript talks to. It also leaves
# out its own ancestors: -a, because an agent started from an iTerm2 tab runs inside iTerm2.
pgrep -axqU $UID iTerm2 || { print -u2 -- "iTerm2 is not running"; exit 1 }

# Prints the device of the current session of iTerm2's current window ("/dev/ttys003"), or "!<why not>".
read -r -d '' script <<'OSA'
on run argv
	if not (application id "com.googlecode.iterm2" is running) then return "!iTerm2 is not running"
	with timeout of 10 seconds
		tell application id "com.googlecode.iterm2"
			set w to missing value
			try
				set w to current window
			end try
			if w is missing value then return "!No iTerm2 window is open"
			set pane to missing value
			try
				set pane to current session of w
			end try
			if pane is missing value then return "!The front iTerm2 window shows no session"
			return tty of pane
		end tell
	end timeout
end run
OSA

if ! answer=$(osascript -e "$script" 2>&1) || [[ $answer == '!'* ]]; then
  case $answer in
    *-1743*) print -u2 -- "The agent may not control iTerm2: allow it in System Settings → Privacy & Security → Automation" ;;
    '!'*)    print -ru2 -- "${answer#!}" ;;
    *)       print -ru2 -- "iTerm2 did not answer: ${answer##*execution error: }" ;;
  esac
  exit 1
fi
device=${answer#/dev/}
# A browser session (iTerm2's web pages) or a finished one has no device.
[[ $device == ttys<-> ]] || { print -ru2 -- "The iTerm2 pane in front has no terminal device"; exit 1 }

# Whose folder, in order: what the pane runs in front (the command, or the shell at its prompt), then the pane’s shell
# (the child of login) — for a command of another user (sudo) whose folder lsof may not read. This account's only.
pids=( ${(f)"$(ps -t $device -o pid=,ppid=,pgid=,tpgid=,uid=,comm= 2>/dev/null | awk -v me="$UID" '
    { pid[NR] = $1; ppid[NR] = $2; uid[NR] = $5; name[$1] = $6
      if ($1 == $3 && $3 == $4 && $5 == me) front = $1 }
    END {
      if (front != "") print front
      for (i = 1; i <= NR; i++) if (uid[i] == me && name[ppid[i]] ~ /(^|\/)login$/) { print pid[i]; exit }
    }')"} )

folder=
for pid in $pids; do
  folder=$(lsof -a -w -p $pid -d cwd -Fn 2>/dev/null | awk '/^n/ { print substr($0, 2); exit }')
  [[ $folder == /* && -d $folder ]] && break
  folder=
done
[[ -n $folder ]] || { print -u2 -- "Cannot tell which folder the iTerm2 pane is in"; exit 1 }

# Finder opens a package (an app, an .xcodeproj) as a double click does — in its app, which it would launch — so a
# package, or a folder whose kind cannot be told, is shown selected in its parent folder instead.
package=$(osascript -l JavaScript -e 'ObjC.import("AppKit"); function run(argv) { return $.NSWorkspace.sharedWorkspace.isFilePackageAtPath(argv[0]) }' "$folder" 2>/dev/null)
if [[ $package == false ]]; then
  # env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
  env -i /usr/bin/open -b com.apple.finder "$folder" || { print -ru2 -- "Finder did not open $folder"; exit 1 }
else
  env -i /usr/bin/open -R "$folder" || { print -ru2 -- "Finder did not show $folder"; exit 1 }
fi
exit 0
