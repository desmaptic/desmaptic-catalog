#!/bin/zsh
# Reminders › Today, the tap: opens Reminders on its Today list — launching it when it is closed, which is the point.
# While the widget has no access to Reminders it opens the Reminders pane of Privacy & Security instead.
# The link is Reminders' own (x-apple-reminderkit, its Info.plist; "today" is a host its link parser knows — ReminderKit
# of Reminders 7.0 / macOS 26). No permission needed: Launch Services opens it.
export LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# The widget's loop writes "settings" here while macOS denies it Reminders (startup.zsh).
state=""
file="$DESMAPTIC_STORAGE/gallery/{{CELL_ID}}/state"
[[ -r $file ]] && IFS= read -r state < "$file"

if [[ $state == settings ]]; then
  # env -i: an app this starts gets the account's own environment, as from the Dock, not the agent's token.
  env -i /usr/bin/open "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders" || { print -u2 -- "Reminders: System Settings did not open"; exit 1 }
else
  env -i /usr/bin/open "x-apple-reminderkit://today" || { print -u2 -- "Reminders did not open"; exit 1 }
fi
exit 0
