# Mail › Get Mail: Mail's own AppleScript command "check for new mail" (Mail.sdef of Mail 16.0, code emalchma), the
# same as Mailbox › Get All New Mail for every account. It works with Mail in the background, whatever its keyboard
# shortcuts and language, and it never launches Mail. The first tap brings up the macOS question whether the agent may
# control Mail. The button's command is this file (app.json).
emulate -R zsh                                  # zsh's own options, whatever ~/.zshenv set (zsh -c reads it)
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# pgrep sees every account's processes; -U keeps it to this one, whose Mail the AppleScript talks to.
pgrep -xqU $UID Mail || { print -u2 -- "Mail is not running"; exit 1 }

# Prints nothing, or "!<why not>". "is running" asks Launch Services, not Mail: the check never launches it either.
read -r -d '' script <<'OSA'
on run argv
	if not (application id "com.apple.mail" is running) then return "!Mail is not running"
	with timeout of 10 seconds -- a hung Mail: -1712, not the tap's 60 s limit
		tell application id "com.apple.mail" to check for new mail
	end timeout
	return ""
end run
OSA

if ! answer=$(osascript -e "$script" 2>&1) || [[ $answer == '!'* ]]; then
  case $answer in
    *-1743*) print -u2 -- "The agent may not control Mail: allow it in System Settings → Privacy & Security → Automation" ;;
    *-1712*) print -u2 -- "Mail did not answer in time" ;;
    *-600*)  print -u2 -- "Mail is not running" ;;
    '!'*)    print -ru2 -- "${answer#!}" ;;
    *)       print -ru2 -- "Mail did not take the command: ${answer##*execution error: }" ;;
  esac
  exit 1
fi
exit 0
