# Reminders › From Clipboard, the tap: the text on the Mac's clipboard becomes a reminder in the default list
# ($reminder_js clipboard, add/reminder.zsh). The copied text never passes through the shell: osascript reads the
# clipboard itself (pbpaste would read it in the C locale and mangle every letter outside ASCII). It never launches
# Reminders; the new reminder shows up there and on the user's other devices by itself. It has no date, so the
# Reminders widget, which counts what is due, does not list it.
# Silent when it worked; otherwise one line on stderr and the phone shakes the button. The command is (app.json):
#   "@file:add/reminder.zsh\n@file:add/clipboard.zsh"
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

answer=$(/usr/bin/osascript -l JavaScript -e "$reminder_js" clipboard 2>&1)
[[ $answer == ok ]] && exit 0
reminder_refusal "$answer"
exit 1
