# Terminal › Show in Finder: the folder of the tab in front of Terminal's front window, in a Finder window. Terminal says
# which terminal device the tab has, through its own AppleScript — the first tap brings up the macOS question whether the
# agent may control Terminal. The folder is asked from the system (ps, lsof): nothing is typed into the tab. It
# never launches Terminal, nor the app of a package the tab is in.
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# pgrep sees every account's processes; -U keeps it to this one, whose Terminal the AppleScript talks to. It also leaves
# out its own ancestors: -a, because an agent started from a Terminal tab runs inside Terminal.
pgrep -axqU $UID Terminal || { print -u2 -- "Terminal is not running"; exit 1 }

# Prints the device of the selected tab of the frontmost Terminal window that has one ("/dev/ttys003"), or "!<why not>".
read -r -d '' script <<'OSA'
on run argv
	if not (application id "com.apple.Terminal" is running) then return "!Terminal is not running"
	tell application id "com.apple.Terminal"
		repeat with w in windows
			try
				return tty of selected tab of w
			end try
		end repeat
	end tell
	return "!No Terminal window is open"
end run
OSA

if ! answer=$(osascript -e "$script" 2>&1) || [[ $answer == '!'* ]]; then
  case $answer in
    *-1743*) print -u2 -- "The agent may not control Terminal: allow it in System Settings → Privacy & Security → Automation" ;;
    '!'*)    print -ru2 -- "${answer#!}" ;;
    *)       print -ru2 -- "Terminal did not answer: ${answer##*execution error: }" ;;
  esac
  exit 1
fi
device=${answer#/dev/}
[[ $device == ttys<-> ]] || { print -ru2 -- "Terminal named no terminal device: $answer"; exit 1 }

# Whose folder, in order: what the tab runs in front (the command, or the shell at its prompt), then the tab's shell
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
[[ -n $folder ]] || { print -u2 -- "Cannot tell which folder the Terminal tab is in"; exit 1 }

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
